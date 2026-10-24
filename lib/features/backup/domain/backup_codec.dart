import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../../core/errors/failures.dart';
import '../../../shared/models/models.dart';

/// Everything needed to rebuild a device workspace on another phone.
class BackupContents {
  final WorkspaceData workspace;

  /// Attachment bytes, by document ID.
  final Map<String, Uint8List> files;

  /// Salted password verifiers for accounts created on the device, so
  /// people can sign in after a restore. Never plain passwords.
  final Map<String, String> accounts;
  final DateTime createdAt;
  const BackupContents({
    required this.workspace,
    required this.files,
    required this.accounts,
    required this.createdAt,
  });
}

/// A `.duedesk` backup: the workspace, attachments and account verifiers,
/// encrypted with a key derived from a password the person chooses.
///
/// Layout: `DDBK | version (1) | iterations (4, big-endian) | salt (16) |
/// nonce (12) | AES-256-GCM ciphertext | tag (16)`. The key comes from
/// PBKDF2-HMAC-SHA256, so the file is useless without the password, and a
/// wrong password or any tampering is detected rather than producing
/// garbage.
abstract final class BackupCodec {
  static const extension = 'duedesk';
  static const minPasswordLength = 8;
  static const _magic = [0x44, 0x44, 0x42, 0x4B];
  static const _version = 1;
  static const _salt = 16, _nonce = 12, _tag = 16;
  static const _header = 4 + 1 + 4 + _salt;

  static Future<Uint8List> create(
    BackupContents contents,
    String password, {
    int iterations = 210000,
  }) {
    if (password.length < minPasswordLength) {
      throw const ValidationFailure(
        'Use a backup password of at least $minPasswordLength characters.',
      );
    }
    final payload = utf8.encode(
      jsonEncode({
        'format': 'duedesk-backup',
        'version': _version,
        'createdAt': contents.createdAt.toUtc().toIso8601String(),
        'workspace': contents.workspace.toJson(),
        'files': contents.files.map((k, v) => MapEntry(k, base64Encode(v))),
        'accounts': contents.accounts,
      }),
    );
    return Isolate.run(() => _seal(payload, password, iterations));
  }

  static Future<BackupContents> open(Uint8List bytes, String password) async {
    if (bytes.length < _header + _nonce + _tag ||
        !Iterable.generate(4).every((i) => bytes[i] == _magic[i])) {
      throw const ValidationFailure('This is not a DueDesk backup file.');
    }
    if (bytes[4] != _version) {
      throw const ValidationFailure(
        'This backup was made by a newer version of DueDesk. Update the app and try again.',
      );
    }
    // A crafted file could ask for an absurd amount of work.
    final iterations = ByteData.sublistView(bytes, 5, 9).getUint32(0);
    if (iterations < 1000 || iterations > 5000000) {
      throw const ValidationFailure('This is not a DueDesk backup file.');
    }
    final Uint8List plain;
    try {
      plain = await Isolate.run(() => _open(bytes, password));
    } on SecretBoxAuthenticationError {
      throw const ValidationFailure(
        'Wrong password, or the backup file is damaged.',
      );
    }
    final json = jsonDecode(utf8.decode(plain)) as Json;
    if (json['format'] != 'duedesk-backup') {
      throw const ValidationFailure('This is not a DueDesk backup file.');
    }
    return BackupContents(
      workspace: WorkspaceData.fromJson(json['workspace'] as Json),
      files: (json['files'] as Map).map(
        (k, v) => MapEntry(k as String, base64Decode(v as String)),
      ),
      accounts: Map<String, String>.from(json['accounts'] as Map? ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static Future<SecretKey> _key(
    String password,
    List<int> salt,
    int iterations,
  ) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  static Future<Uint8List> _seal(
    List<int> plain,
    String password,
    int iterations,
  ) async {
    final salt = SecretKeyData.random(length: _salt).bytes;
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: await _key(password, salt, iterations),
    );
    final header = ByteData(_header)
      ..setUint8(4, _version)
      ..setUint32(5, iterations);
    final out = header.buffer.asUint8List()..setRange(0, 4, _magic);
    out.setRange(9, _header, salt);
    return Uint8List.fromList([...out, ...box.concatenation()]);
  }

  static Future<Uint8List> _open(Uint8List bytes, String password) async {
    final iterations = ByteData.sublistView(bytes, 5, 9).getUint32(0);
    final salt = bytes.sublist(9, _header);
    final box = SecretBox.fromConcatenation(
      bytes.sublist(_header),
      nonceLength: _nonce,
      macLength: _tag,
    );
    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _key(password, salt, iterations),
      ),
    );
  }
}
