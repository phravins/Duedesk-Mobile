import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts what DueDesk writes to the device with AES-256-GCM.
///
/// Sealed data is `DDE1 | nonce (12) | ciphertext | tag (16)`. The key is
/// random, made once per installation and kept in the platform Keychain /
/// Keystore, never beside the data. Data written by earlier versions is
/// still read as plain text and is encrypted the next time it is saved.
class StorageCipher {
  static const _magic = [0x44, 0x44, 0x45, 0x31];
  static const _nonce = 12, _tag = 16;

  /// Above this size the work moves off the UI thread.
  static const _backgroundThreshold = 256 * 1024;
  final List<int> _key;
  StorageCipher(List<int> key) : _key = List.unmodifiable(key) {
    if (key.length != 32) throw ArgumentError('Expected a 256-bit key.');
  }

  static bool isSealed(List<int> bytes) =>
      bytes.length >= _magic.length + _nonce + _tag &&
      Iterable.generate(_magic.length).every((i) => bytes[i] == _magic[i]);

  Future<Uint8List> seal(List<int> plain) =>
      _run(plain, (key, data) => _seal(key, data));

  /// Returns the plain bytes. Unsealed (legacy) data passes through.
  Future<Uint8List> open(List<int> bytes) async {
    if (!isSealed(bytes)) return Uint8List.fromList(bytes);
    return _run(bytes, (key, data) => _open(key, data));
  }

  Future<Uint8List> _run(
    List<int> data,
    Future<Uint8List> Function(List<int> key, List<int> data) task,
  ) {
    final key = _key;
    if (data.length < _backgroundThreshold) return task(key, data);
    return Isolate.run(() => task(key, data));
  }

  static Future<Uint8List> _seal(List<int> key, List<int> plain) async {
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList([..._magic, ...box.concatenation()]);
  }

  static Future<Uint8List> _open(List<int> key, List<int> sealed) async {
    final box = SecretBox.fromConcatenation(
      sealed.sublist(_magic.length),
      nonceLength: _nonce,
      macLength: _tag,
      copy: false,
    );
    return Uint8List.fromList(
      await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key)),
    );
  }
}

/// Reads this installation's storage key from secure storage, creating it
/// the first time.
Future<List<int>> loadStorageKey(FlutterSecureStorage storage) async {
  const name = 'device_storage_key';
  final saved = await storage.read(key: name);
  if (saved != null) return base64Decode(saved);
  final key = SecretKeyData.random(length: 32).bytes;
  await storage.write(key: name, value: base64Encode(key));
  return key;
}
