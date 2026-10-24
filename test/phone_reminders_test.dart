import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:duedesk/app/providers.dart';
import 'package:duedesk/core/storage/local_store.dart';
import 'package:duedesk/features/due_items/data/demo_seed.dart';
import 'package:duedesk/features/notifications/application/reminder_scheduler.dart';
import 'package:duedesk/features/notifications/domain/reminders.dart';
import 'package:duedesk/shared/models/models.dart';
import 'fake_notifications.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  final today = DateTime.utc(2026, 10, 7);
  final seed = demoSeed(now: today);
  final orgs = {for (final o in seed.organisations) o.id: o};
  final base = seed.items.firstWhere(
    (i) => !i.isClosed && i.organisationId == 'realoffice',
  );
  DueItem due(int days, {List<int> reminders = const [7, 3, 1, 0]}) =>
      base.patch({
        'id': 'item-$days',
        'title': 'GST return',
        'dueDate': today.add(Duration(days: days)).toIso8601String(),
        'status': DueStatus.upcoming.name,
        'reminderConfiguration': ReminderConfiguration(
          daysBefore: reminders,
        ).toJson(),
      });
  // 07:00 in Kolkata on the 7th: today's 9am reminder is still ahead.
  final now = DateTime.utc(2026, 10, 7, 1, 30);

  group('Phone reminder plan', () {
    test('one reminder per threshold at 9am organisation time', () {
      final plan = planReminders(
        items: [due(3)],
        organisations: orgs,
        now: now,
      );
      expect(plan.map((p) => p.type), [
        'dueSoon',
        'dueSoon',
        'dueToday',
        'overdue',
      ]);
      final first = plan.first;
      expect(first.when.location.name, 'Asia/Kolkata');
      expect([first.when.day, first.when.hour], [7, 9]);
      expect(first.title, 'GST return');
      expect(first.body, startsWith('Due in 3 days · 10 Oct'));
      expect(plan[1].body, startsWith('Due tomorrow'));
      expect([plan.last.when.day, plan.last.body], [11, startsWith('Overdue')]);
      expect(plan.every((p) => p.itemId == 'item-3'), isTrue);
    });

    test('skips past moments, closed items and disabled reminders', () {
      final later = DateTime.utc(2026, 10, 7, 6); // 11:30 in Kolkata
      final plan = planReminders(
        items: [
          due(3),
          due(5).patch({'id': 'done', 'status': DueStatus.completed.name}),
          due(4).patch({
            'id': 'quiet',
            'reminderConfiguration': const ReminderConfiguration(
              enabled: false,
            ).toJson(),
          }),
        ],
        organisations: orgs,
        now: later,
        overdueAlerts: false,
      );
      expect(plan.map((p) => p.when.day), [9, 10]);
      expect(plan.any((p) => p.itemId == 'done'), isFalse);
    });

    test('keeps titles off the lock screen when asked', () {
      final plan = planReminders(
        items: [due(1)],
        organisations: orgs,
        now: now,
        showDetails: false,
      );
      expect(plan.first.title, 'DueDesk reminder');
      expect(plan.first.body, isNot(contains('GST')));
      expect(plan.first.body, contains('due tomorrow'));
    });

    test('IDs are stable and the soonest reminders fit the iOS limit', () {
      final a = planReminders(items: [due(3)], organisations: orgs, now: now);
      final b = planReminders(items: [due(3)], organisations: orgs, now: now);
      expect(a.map((p) => p.id), b.map((p) => p.id));
      expect(a.map((p) => p.id).toSet(), hasLength(a.length));
      expect(a.every((p) => p.id > 0), isTrue);
      final many = planReminders(
        items: [for (var d = 1; d < 40; d++) due(d)],
        organisations: orgs,
        now: now,
      );
      expect(many, hasLength(60));
      for (var i = 1; i < many.length; i++) {
        expect(many[i].when.isBefore(many[i - 1].when), isFalse);
      }
    });
  });

  group('Reminder scheduler', () {
    late ProviderContainer c;
    late FakeSystemNotifications phone;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({'demoUser': 'management'});
      final prefs = await SharedPreferences.getInstance();
      final store = MemoryLocalStore();
      await store.write(demoSeed());
      phone = FakeSystemNotifications();
      c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
          systemNotificationsProvider.overrideWithValue(phone),
        ],
      );
      await c.read(authProvider.future);
      await c.read(workspaceProvider.future);
    });
    tearDown(() => c.dispose());

    test(
      'schedules on start, asks permission once, clears on sign-out',
      () async {
        final scheduler = c.read(reminderSchedulerProvider);
        await scheduler.start();
        expect(phone.scheduled, isNotEmpty);
        expect(phone.permissionRequests, 1);
        await scheduler.schedule();
        expect(phone.permissionRequests, 1);

        await c.read(settingsProvider.notifier).toggle('push', false);
        await scheduler.schedule();
        expect(phone.scheduled, isEmpty);
        await c.read(settingsProvider.notifier).toggle('push', true);
        await scheduler.schedule();
        expect(phone.scheduled, isNotEmpty);

        await c.read(authProvider.notifier).logout();
        await scheduler.schedule();
        expect(phone.scheduled, isEmpty);
      },
    );

    test('a tapped or launching notification opens its obligation', () async {
      final opened = <String>[];
      c.read(notificationServiceProvider).dueItemLinks.listen(opened.add);
      phone.launchedBy = 'gst';
      await c.read(reminderSchedulerProvider).start();
      phone.tap!('fire');
      await Future<void>.delayed(Duration.zero);
      expect(opened, ['gst', 'fire']);
    });
  });
}
