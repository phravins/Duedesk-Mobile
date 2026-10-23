import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:duedesk/core/storage/device_store_io.dart';
import 'package:duedesk/core/storage/file_local_store.dart';
import 'package:duedesk/core/storage/local_store.dart';
import 'package:duedesk/core/storage/storage_cipher.dart';
import 'package:duedesk/core/storage/storage_settings.dart';
import 'package:duedesk/features/due_items/data/demo_seed.dart';
import 'package:duedesk/shared/models/models.dart';

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('duedesk'));
  tearDown(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('Device store writes real files to the chosen folder', () async {
    final store = FileLocalStore(Directory('${temp.path}/DueDesk'));
    expect(await store.read(), isNull);
    final seed = demoSeed();
    await store.write(seed);
    await store.putFile('doc-1', Uint8List.fromList([1, 2, 3]));
    await store.putFile('../escape/é', Uint8List.fromList([4]));

    expect(store.workspaceFile.existsSync(), isTrue);
    expect(File('${temp.path}/DueDesk/files/doc-1').readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    expect(Directory('${temp.path}/escape').existsSync(), isFalse);
    expect(await store.getFile('../escape/é'), [4]);
    expect(
      store.filesDirectory
          .listSync()
          .map((f) => f.path)
          .where((p) => p.endsWith('.tmp')),
      isEmpty,
    );

    final reopened = FileLocalStore(Directory('${temp.path}/DueDesk'));
    expect((await reopened.read())!.toJson(), (await store.read())!.toJson());
    expect(await reopened.sizeInBytes(), greaterThan(4));
    expect(store.location, '${temp.path}/DueDesk');

    await store.removeFile('doc-1');
    expect(await store.getFile('doc-1'), isNull);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('Concurrent writes leave the last workspace intact', () async {
    final store = FileLocalStore(Directory('${temp.path}/DueDesk'));
    final seed = demoSeed();
    await Future.wait([
      for (var i = 0; i < 10; i++)
        store.write(
          seed.copyWith(
            organisations: [
              ...seed.organisations,
              Organisation(id: 'extra', name: 'Org $i', slug: 'extra'),
            ],
          ),
        ),
    ]);
    final saved = await store.read();
    expect(
      saved!.organisations.singleWhere((o) => o.id == 'extra').name,
      'Org 9',
    );
  });

  test('Earlier Hive data moves into the device folder once', () async {
    Hive.init(temp.path);
    final records = await Hive.openBox<String>('demo-workspace');
    final files = await Hive.openBox<List<int>>('demo-files');
    final seed = demoSeed();
    await HiveLocalStore(records, files).write(seed);
    await files.put('evidence', [9, 9]);
    await records.close();
    await files.close();

    final store = FileLocalStore(Directory('${temp.path}/DueDesk'));
    await moveLegacyWorkspace(store, 'demo-workspace', 'demo-files');

    expect((await store.read())!.toJson(), seed.toJson());
    expect(await store.getFile('evidence'), [9, 9]);
    expect(await Hive.boxExists('demo-workspace'), isFalse);
    expect(await Hive.boxExists('demo-files'), isFalse);
  });

  test('Server addresses need HTTPS outside the local network', () {
    expect(parseServerUrl('due.example.com/').url, 'https://due.example.com');
    expect(
      parseServerUrl(' https://due.example.com/api/v1/ ').url,
      'https://due.example.com/api/v1',
    );
    expect(parseServerUrl('http://192.168.1.20:8080').url, isNotNull);
    expect(parseServerUrl('http://localhost:3000').url, isNotNull);
    expect(parseServerUrl('http://nas.local').url, isNotNull);
    expect(parseServerUrl('http://due.example.com').error, contains('https'));
    expect(parseServerUrl('http://172.32.0.1').error, isNotNull);
    expect(parseServerUrl('ftp://due.example.com').error, isNotNull);
    expect(parseServerUrl('https://user:pw@due.example.com').error, isNotNull);
    expect(parseServerUrl('').error, 'Enter your server address.');
  });

  group('Encrypted device storage', () {
    final key = List<int>.generate(32, (i) => i * 7 % 256);
    test('records and attachments are unreadable on disk', () async {
      final dir = Directory('${temp.path}/DueDesk');
      final store = FileLocalStore(dir, cipher: StorageCipher(key));
      final seed = demoSeed();
      await store.write(seed);
      await store.putFile('doc-1', Uint8List.fromList(utf8.encode('secret')));
      final raw = store.workspaceFile.readAsBytesSync();
      expect(StorageCipher.isSealed(raw), isTrue);
      expect(utf8.decode(raw, allowMalformed: true), isNot(contains('GSTR')));
      final file = File('${dir.path}/files/doc-1').readAsBytesSync();
      expect(
        utf8.decode(file, allowMalformed: true),
        isNot(contains('secret')),
      );

      final reopened = FileLocalStore(dir, cipher: StorageCipher(key));
      expect((await reopened.read())!.toJson(), seed.toJson());
      expect(utf8.decode((await reopened.getFile('doc-1'))!), 'secret');

      final wrongKey = FileLocalStore(
        dir,
        cipher: StorageCipher(List<int>.filled(32, 1)),
      );
      await expectLater(wrongKey.read(), throwsA(anything));
    });

    test('unencrypted data from earlier versions is upgraded', () async {
      final dir = Directory('${temp.path}/DueDesk');
      final seed = demoSeed();
      await FileLocalStore(dir).write(seed);
      final store = FileLocalStore(dir, cipher: StorageCipher(key));
      final legacy = await store.read();
      expect(legacy!.toJson(), seed.toJson());
      await store.write(legacy);
      expect(
        StorageCipher.isSealed(store.workspaceFile.readAsBytesSync()),
        true,
      );
      expect((await store.read())!.toJson(), seed.toJson());
    });

    test('large attachments round-trip off the UI thread', () async {
      final cipher = StorageCipher(key);
      final big = Uint8List.fromList(
        List<int>.generate(600 * 1024, (i) => i % 251),
      );
      final sealed = await cipher.seal(big);
      expect(sealed.length, big.length + 4 + 12 + 16);
      expect(await cipher.open(sealed), big);
    });
  });
}
