import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../config/environment.dart';
import 'file_local_store.dart';
import 'local_store.dart';
import 'storage_cipher.dart';

/// Opens the DueDesk folder in the app's documents directory, encrypted with
/// [key]. Hive must be initialised first so data from earlier versions can be
/// moved across.
Future<LocalStore> openDeviceStore(List<int> key) async {
  final documents = await getApplicationDocumentsDirectory();
  final store = FileLocalStore(
    Directory('${documents.path}${Platform.pathSeparator}DueDesk'),
    cipher: StorageCipher(key),
  );
  await store.root.create(recursive: true);
  if (AppConfig.isDemo && !await store.workspaceFile.exists()) {
    await moveLegacyWorkspace(
      store,
      '${AppConfig.environmentName}-workspace',
      '${AppConfig.environmentName}-files',
    );
  }
  return store;
}

/// Copies a workspace that earlier versions kept in Hive into [store]. The
/// old boxes are deleted only after the copy reads back identically; files go
/// first and the workspace last, so an interrupted copy is retried next time.
Future<void> moveLegacyWorkspace(
  FileLocalStore store,
  String recordsBox,
  String filesBox,
) async {
  if (!await Hive.boxExists(recordsBox)) return;
  final records = await Hive.openBox<String>(recordsBox);
  final files = await Hive.openBox<List<int>>(filesBox);
  final legacy = HiveLocalStore(records, files);
  final data = await legacy.read();
  if (data != null) {
    for (final key in files.keys) {
      await store.putFile(key.toString(), Uint8List.fromList(files.get(key)!));
    }
    await store.write(data);
    final copied = await store.read();
    if (jsonEncode(copied?.toJson()) != jsonEncode(data.toJson())) return;
  }
  await records.deleteFromDisk();
  await files.deleteFromDisk();
}
