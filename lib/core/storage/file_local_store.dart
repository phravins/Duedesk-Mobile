import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../shared/models/models.dart';
import 'local_store.dart';
import 'storage_cipher.dart';

/// Keeps the workspace as ordinary files in a folder on the device's drive:
/// `workspace.json` holds the records and `files/` holds attachments.
///
/// Every write goes to a temporary file that is then renamed over the old
/// one, so a crash or power cut leaves either the previous or the new copy,
/// never a half-written file. Operations run one at a time.
///
/// With a [cipher], records and attachments are encrypted at rest, so the
/// files are unreadable outside DueDesk (for example in a device backup).
class FileLocalStore implements LocalStore {
  final Directory root;
  final StorageCipher? cipher;
  FileLocalStore(this.root, {this.cipher});
  Future<void> _pending = Future.value();

  String _path(String name) => '${root.path}${Platform.pathSeparator}$name';
  File get workspaceFile => File(_path('workspace.json'));
  Directory get filesDirectory => Directory(_path('files'));

  File _attachment(String id) {
    final name = RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(id)
        ? id
        : '~${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';
    return File('${filesDirectory.path}${Platform.pathSeparator}$name');
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _pending.then((_) => task());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _replace(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    final stored = cipher == null ? bytes : await cipher!.seal(bytes);
    await temp.writeAsBytes(stored, flush: true);
    await temp.rename(target.path);
  }

  Future<Uint8List> _load(File file) async {
    final bytes = await file.readAsBytes();
    return cipher == null ? bytes : cipher!.open(bytes);
  }

  @override
  Future<WorkspaceData?> read() => _serial(() async {
    if (!await workspaceFile.exists()) return null;
    return WorkspaceData.fromJson(
      jsonDecode(utf8.decode(await _load(workspaceFile))) as Json,
    );
  });

  @override
  Future<void> write(WorkspaceData data) => _serial(
    () => _replace(workspaceFile, utf8.encode(jsonEncode(data.toJson()))),
  );

  @override
  Future<void> putFile(String id, Uint8List bytes) =>
      _serial(() => _replace(_attachment(id), bytes));

  @override
  Future<Uint8List?> getFile(String id) => _serial(() async {
    final file = _attachment(id);
    return await file.exists() ? _load(file) : null;
  });

  @override
  Future<void> removeFile(String id) => _serial(() async {
    final file = _attachment(id);
    if (await file.exists()) await file.delete();
  });

  @override
  Future<void> clear() => _serial(() async {
    if (await workspaceFile.exists()) await workspaceFile.delete();
    if (await filesDirectory.exists()) {
      await filesDirectory.delete(recursive: true);
    }
  });

  @override
  String get location => root.path;

  @override
  Future<int> sizeInBytes() => _serial(() async {
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  });
}
