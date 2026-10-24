import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:duedesk/app/providers.dart';
import 'package:duedesk/core/errors/failures.dart';
import 'package:duedesk/core/storage/local_store.dart';
import 'package:duedesk/features/backup/application/backup_service.dart';
import 'package:duedesk/features/backup/domain/backup_codec.dart';
import 'package:duedesk/features/backup/domain/exports.dart';
import 'package:duedesk/features/due_items/data/demo_seed.dart';
import 'package:duedesk/shared/models/models.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  final today = DateTime.utc(2026, 10, 24);

  group('Encrypted backup file', () {
    final contents = BackupContents(
      workspace: demoSeed(now: today),
      files: {'doc-1': Uint8List.fromList(utf8.encode('evidence'))},
      accounts: {'demo-account-a@b.in': '{"verifier":"x"}'},
      createdAt: DateTime.utc(2026, 10, 24, 10),
    );
    Future<Uint8List> make([String password = 'correct horse']) =>
        BackupCodec.create(contents, password, iterations: 1000);

    test('round-trips with the right password only', () async {
      final bytes = await make();
      expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('GSTR')));
      final opened = await BackupCodec.open(bytes, 'correct horse');
      expect(opened.workspace.toJson(), contents.workspace.toJson());
      expect(utf8.decode(opened.files['doc-1']!), 'evidence');
      expect(opened.accounts, contents.accounts);
      expect(opened.createdAt, contents.createdAt);
      await expectLater(
        BackupCodec.open(bytes, 'wrong horse'),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('Wrong password'),
          ),
        ),
      );
    });

    test('rejects tampering, other files and weak passwords', () async {
      final bytes = await make();
      final tampered = Uint8List.fromList(bytes)..[bytes.length - 20] ^= 1;
      await expectLater(
        BackupCodec.open(tampered, 'correct horse'),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        BackupCodec.open(Uint8List.fromList(utf8.encode('%PDF-1.7 hi')), 'x'),
        throwsA(isA<ValidationFailure>()),
      );
      final greedy = Uint8List.fromList(bytes)
        ..setRange(5, 9, [255, 255, 255, 255]);
      await expectLater(
        BackupCodec.open(greedy, 'correct horse'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(() => make('short'), throwsA(isA<ValidationFailure>()));
    });

    test('restoring on a new device brings back records and sign-in', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final store = MemoryLocalStore();
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authProvider.future);
      await c
          .read(authProvider.notifier)
          .register(
            'Asha Rao',
            'asha@example.in',
            'local-pass-123',
            '+919876543210',
          );
      await store.putFile('doc-x', Uint8List.fromList([1, 2, 3]));
      final data = (await store.read())!;
      await store.write(
        data.copyWith(
          documents: [
            ...data.documents,
            Document(
              id: 'doc-x',
              organisationId: data.organisations.last.id,
              dueItemId: 'none',
              filename: 'a.pdf',
              fileType: 'pdf',
              mimeType: 'application/pdf',
              url: 'local:doc-x',
              uploadedBy: 'Asha Rao',
              fileSize: 3,
              uploadedAt: today,
            ),
          ],
        ),
      );
      final backup = await BackupCodec.create(
        await c.read(backupServiceProvider).collect(),
        'family-secret',
        iterations: 1000,
      );

      // A fresh phone.
      SharedPreferences.setMockInitialValues({});
      final freshPrefs = await SharedPreferences.getInstance();
      final freshStore = MemoryLocalStore();
      final fresh = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(freshPrefs),
          localStoreProvider.overrideWithValue(freshStore),
        ],
      );
      addTearDown(fresh.dispose);
      await fresh.read(authProvider.future);
      await fresh
          .read(backupServiceProvider)
          .restore(await BackupCodec.open(backup, 'family-secret'));
      expect(await freshStore.getFile('doc-x'), [1, 2, 3]);
      await fresh
          .read(authProvider.notifier)
          .login('asha@example.in', 'local-pass-123', true);
      expect(fresh.read(authProvider).value?.name, 'Asha Rao');
    });
  });

  group('Exports', () {
    final seed = demoSeed(now: today);
    final org = seed.organisations.firstWhere((o) => o.id == 'realoffice');
    final items = seed.items.where((i) => i.organisationId == org.id).toList();

    test('CSV escapes quotes and neutralises spreadsheet formulas', () {
      final risky = items.first.patch({
        'title': '=HYPERLINK("http://x")',
        'notes': 'n',
        'referenceNumber': 'A, "B"',
      });
      final csv = Exports.csv([risky, ...items.skip(1)], today);
      final lines = csv.trimRight().split('\r\n');
      expect(lines.first, startsWith('"Title","Category","Due date"'));
      expect(lines, hasLength(items.length + 1));
      expect(csv, contains('"\'=HYPERLINK(""http://x"")"'));
      expect(csv, contains('"A, ""B"""'));
    });

    test('calendar file repeats, reminds and folds long lines', () {
      final monthEnd = items.first.patch({
        'id': 'pt',
        'title': 'Professional tax; state, monthly',
        'dueDate': DateTime.utc(2026, 10, 31).toIso8601String(),
        'frequency': Frequency.monthly.name,
        'status': DueStatus.upcoming.name,
        'description': 'x' * 120,
        'reminderConfiguration': const ReminderConfiguration(
          daysBefore: [7, 0],
        ).toJson(),
      });
      final closed = items.first.patch({
        'id': 'done',
        'status': DueStatus.completed.name,
      });
      final ics = Exports.ics([monthEnd, closed], org, now: today);
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('UID:pt@duedesk.app'));
      expect(ics, isNot(contains('UID:done@duedesk.app')));
      expect(ics, contains('DTSTART;VALUE=DATE:20261031'));
      expect(ics, contains('RRULE:FREQ=MONTHLY;BYMONTHDAY=-1'));
      expect(ics, contains(r'SUMMARY:Professional tax\; state\, monthly'));
      expect(ics, contains('TRIGGER:-P6DT15H'));
      expect(ics, contains('TRIGGER:PT9H'));
      for (final line in ics.split('\r\n')) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75));
      }
    });

    test('PDF report renders with the bundled fonts', () async {
      final pdf = await Exports.pdf(
        items: items,
        organisation: org,
        today: today,
        preparedBy: 'Management',
        bodyFont: ByteData.sublistView(
          File('assets/fonts/Inter.ttf').readAsBytesSync(),
        ),
        headingFont: ByteData.sublistView(
          File('assets/fonts/NotoSerif-Medium.ttf').readAsBytesSync(),
        ),
        now: today,
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(5000));
    });
  });
}
