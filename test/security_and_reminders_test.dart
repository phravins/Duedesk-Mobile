import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:duedesk/app/providers.dart';
import 'package:duedesk/core/errors/failures.dart';
import 'package:duedesk/core/security/app_lock.dart';
import 'package:duedesk/core/storage/local_store.dart';
import 'package:duedesk/features/auth/presentation/auth_screens.dart';
import 'package:duedesk/features/due_items/data/demo_seed.dart';
import 'package:duedesk/features/due_items/data/mock_repository.dart';
import 'package:duedesk/features/notifications/domain/reminders.dart';
import 'package:duedesk/shared/models/models.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  final today = DateTime.utc(2026, 10, 7);
  final base = demoSeed(now: today).items.firstWhere((i) => !i.isClosed);
  DueItem due(int days, {List<int> reminders = const [7, 3, 1, 0]}) =>
      base.patch({
        'dueDate': today.add(Duration(days: days)).toIso8601String(),
        'status': DueStatus.upcoming.name,
        'reminderConfiguration': ReminderConfiguration(
          daysBefore: reminders,
        ).toJson(),
      });

  group('Reminder schedule', () {
    test('raises the most recent threshold that has passed', () {
      final first = remindersDue([due(5)], const [], today);
      expect(first.single.type, 'dueSoon');
      expect(first.single.id, contains(':7:'));
      expect(first.single.message, endsWith('5 days left.'));
      // Same day, same threshold: never repeated.
      expect(remindersDue([due(5)], first, today), isEmpty);
      // Two days later the 3-day threshold is owed.
      final later = today.add(const Duration(days: 2));
      final next = remindersDue([due(5)], first, later);
      expect(next.single.id, contains(':3:'));
    });

    test('marks due today and overdue, honouring the overdue setting', () {
      expect(remindersDue([due(0)], const [], today).single.type, 'dueToday');
      expect(remindersDue([due(-2)], const [], today).single.type, 'overdue');
      expect(
        remindersDue([due(-2)], const [], today, overdueAlerts: false),
        isEmpty,
      );
    });

    test('skips closed items, disabled reminders and far deadlines', () {
      final closed = due(1).patch({'status': DueStatus.completed.name});
      final quiet = due(1).patch({
        'reminderConfiguration': const ReminderConfiguration(
          enabled: false,
        ).toJson(),
      });
      expect(remindersDue([closed, quiet, due(20)], const [], today), isEmpty);
    });

    test('does not repeat a reminder already in the inbox today', () {
      final existing = DueNotification(
        id: 'notification-${base.id}',
        organisationId: base.organisationId,
        dueItemId: base.id,
        type: 'dueSoon',
        message: 'seeded',
        timestamp: today.add(const Duration(hours: 8)),
      );
      expect(remindersDue([due(3)], [existing], today), isEmpty);
    });

    test('device repository stores reminders for visible items only', () async {
      final store = MemoryLocalStore();
      final seed = demoSeed(now: today);
      await store.write(seed.copyWith(notifications: const []));
      final repo = MockDueItemRepository(store);
      final owner = seed.users.firstWhere((u) => u.id == 'management');
      final added = await repo.syncReminders(owner, 'realoffice', today);
      expect(added, greaterThan(0));
      expect(await repo.syncReminders(owner, 'realoffice', today), 0);
      final data = await repo.load(owner);
      expect(
        data.notifications.where((n) => n.id.startsWith('reminder:')).length,
        added,
      );
    });
  });

  test('Password strength rewards length and variety', () {
    expect(passwordStrength(''), 0);
    expect(passwordStrength('short1'), 1);
    expect(passwordStrength('longenough'), 1);
    expect(passwordStrength('local-password-1'), 4);
    expect(passwordStrength('Correct-Horse-9'), 4);
  });

  group('Sign-in throttle', () {
    test('backs off after five failures and resets on success', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var clock = DateTime(2026, 10, 7, 9);
      final throttle = LoginThrottle(
        prefs.getString,
        prefs.setString,
        prefs.remove,
        now: () => clock,
      );
      for (var i = 0; i < 4; i++) {
        await throttle.failed('A@x.in');
      }
      expect(throttle.wait('a@x.in'), isNull);
      await throttle.failed('a@x.in');
      expect(throttle.wait('a@x.in'), const Duration(seconds: 30));
      clock = clock.add(const Duration(seconds: 31));
      expect(throttle.wait('a@x.in'), isNull);
      await throttle.failed('a@x.in');
      expect(throttle.wait('a@x.in'), const Duration(seconds: 60));
      await throttle.succeeded('a@x.in');
      expect(throttle.wait('a@x.in'), isNull);
    });

    test('demo login is refused while throttled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = MemoryLocalStore();
      await store.write(demoSeed());
      final c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authProvider.future);
      final auth = c.read(authProvider.notifier);
      for (var i = 0; i < 5; i++) {
        await expectLater(
          auth.login('demo@duedesk.app', 'wrong', false),
          throwsA(isA<AuthenticationFailure>()),
        );
      }
      await expectLater(
        auth.login('demo@duedesk.app', 'demo123', false),
        throwsA(
          isA<ValidationFailure>().having(
            (e) => e.message,
            'message',
            contains('Too many attempts'),
          ),
        ),
      );
    });
  });

  group('App lock', () {
    late ProviderContainer c;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({'demoUser': 'management'});
      final prefs = await SharedPreferences.getInstance();
      final store = MemoryLocalStore();
      await store.write(demoSeed());
      c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          localStoreProvider.overrideWithValue(store),
          passcodeHasherProvider.overrideWithValue(
            const PasscodeHasher(iterations: 1000),
          ),
        ],
      );
      await c.read(authProvider.future);
      c.listen(appLockProvider, (_, _) {});
      while (!c.read(appLockProvider).ready) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    tearDown(() => c.dispose());

    test('passcode is stored only as a verifier', () async {
      await c.read(appLockProvider.notifier).setPasscode('482913');
      final stored = await secureStorage.readAll();
      expect(stored.values.join(), isNot(contains('482913')));
      expect(
        await const PasscodeHasher(
          iterations: 1000,
        ).verify('482913', stored['app_lock_passcode']!),
        isTrue,
      );
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('locks after the timeout and unlocks with the right code', () async {
      final lock = c.read(appLockProvider.notifier);
      var clock = DateTime(2026, 10, 7, 9);
      lock.now = () => clock;
      await lock.setPasscode('482913');
      await lock.setTimeout(const Duration(minutes: 1));
      lock.backgrounded();
      clock = clock.add(const Duration(seconds: 30));
      lock.foregrounded();
      expect(c.read(appLockProvider).locked, isFalse);
      lock.backgrounded();
      clock = clock.add(const Duration(minutes: 2));
      lock.foregrounded();
      expect(c.read(appLockProvider).locked, isTrue);
      expect(await lock.unlock('000000'), UnlockResult.wrong);
      expect(await lock.unlock('482913'), UnlockResult.unlocked);
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('wrong guesses back off, then sign the account out', () async {
      final lock = c.read(appLockProvider.notifier);
      var clock = DateTime(2026, 10, 7, 9);
      lock.now = () => clock;
      await lock.setPasscode('482913');
      lock.lock();
      for (var i = 0; i < 5; i++) {
        expect(await lock.unlock('111111'), UnlockResult.wrong);
      }
      expect(await lock.unlock('482913'), UnlockResult.blocked);
      for (var i = 5; i < 9; i++) {
        clock = clock.add(const Duration(hours: 1));
        expect(await lock.unlock('111111'), UnlockResult.wrong);
      }
      clock = clock.add(const Duration(hours: 1));
      expect(await lock.unlock('111111'), UnlockResult.signedOut);
      expect(c.read(authProvider).value, isNull);
      expect(c.read(appLockProvider).enabled, isFalse);
      expect(await secureStorage.read(key: 'app_lock_passcode'), isNull);
    });

    test('signing out, or in with a password, removes the passcode', () async {
      final lock = c.read(appLockProvider.notifier);
      await lock.setPasscode('482913');
      await c.read(authProvider.notifier).logout();
      expect(c.read(appLockProvider).enabled, isFalse);
      await lock.setPasscode('482913');
      lock.lock();
      await c
          .read(authProvider.notifier)
          .login('demo@duedesk.app', 'demo123', true);
      expect(c.read(appLockProvider).enabled, isFalse);
      expect(c.read(appLockProvider).locked, isFalse);
    });
  });
}
