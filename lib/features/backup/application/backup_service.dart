import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/errors/failures.dart';
import '../domain/backup_codec.dart';

/// Saving a file the person names, and choosing one to open.
abstract interface class FileExporter {
  /// Returns false when the person cancels.
  Future<bool> save(String fileName, Uint8List bytes);
  Future<Uint8List?> pick();
}

/// The system save and open dialogs (Files on iOS, the document picker on
/// Android), so files can go to the device, iCloud Drive or Google Drive.
class PickerFileExporter implements FileExporter {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      bytes: bytes,
    );
    return path != null;
  }

  @override
  Future<Uint8List?> pick() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    return result?.files.singleOrNull?.bytes;
  }
}

final fileExporterProvider = Provider<FileExporter>(
  (ref) => PickerFileExporter(),
);

final backupServiceProvider = Provider<BackupService>(BackupService.new);

/// Builds and restores device backups. A server keeps its own data, so this
/// applies to device storage only.
class BackupService {
  static const _accountPrefix = 'demo-account-';
  final Ref ref;
  BackupService(this.ref);

  Future<BackupContents> collect() async {
    final store = ref.read(localStoreProvider);
    final data = await store.read();
    if (data == null) {
      throw const ValidationFailure('There is nothing to back up yet.');
    }
    final files = <String, Uint8List>{};
    for (final doc in data.documents) {
      // Sample evidence ships with the app and needs no copy.
      if (doc.url.startsWith('asset:')) continue;
      final bytes = await store.getFile(doc.id);
      if (bytes != null) files[doc.id] = bytes;
    }
    final prefs = ref.read(preferencesProvider);
    return BackupContents(
      workspace: data,
      files: files,
      accounts: {
        for (final key in prefs.getKeys())
          if (key.startsWith(_accountPrefix)) key: prefs.getString(key)!,
      },
      createdAt: DateTime.now(),
    );
  }

  /// Replaces everything on this device with [contents], then signs out so
  /// the restored accounts are used from here on.
  Future<void> restore(BackupContents contents) async {
    final store = ref.read(localStoreProvider);
    await store.clear();
    for (final entry in contents.files.entries) {
      await store.putFile(entry.key, entry.value);
    }
    await store.write(contents.workspace);
    final prefs = ref.read(preferencesProvider);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_accountPrefix)) await prefs.remove(key);
    }
    for (final entry in contents.accounts.entries) {
      await prefs.setString(entry.key, entry.value);
    }
    await prefs.remove('organisation');
    await ref.read(authProvider.notifier).logout();
  }

  Future<void> markBackedUp() => ref
      .read(preferencesProvider)
      .setString('lastBackupAt', DateTime.now().toUtc().toIso8601String());

  DateTime? get lastBackup => DateTime.tryParse(
    ref.read(preferencesProvider).getString('lastBackupAt') ?? '',
  )?.toLocal();
}
