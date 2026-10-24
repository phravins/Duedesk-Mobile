import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../domain/reminders.dart';
import 'system_notifications.dart';

final systemNotificationsProvider = Provider<SystemNotifications>(
  (ref) => LocalSystemNotifications(),
);

/// The hour of day (organisation time) at which reminders arrive.
final reminderHourProvider = NotifierProvider<ReminderHourController, int>(
  ReminderHourController.new,
);

class ReminderHourController extends Notifier<int> {
  static const choices = [8, 9, 10, 18];
  @override
  int build() => ref.read(preferencesProvider).getInt('reminderHour') ?? 9;
  Future<void> set(int hour) async {
    state = hour;
    await ref.read(preferencesProvider).setInt('reminderHour', hour);
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  final scheduler = ReminderScheduler(ref);
  // Re-plan whenever what or how to remind changes, once the change that
  // triggered it (for example signing out) has finished.
  void later(_, _) => Future.microtask(scheduler.schedule);
  ref.listen(workspaceProvider, later);
  ref.listen(authProvider, later);
  ref.listen(settingsProvider, later);
  ref.listen(reminderHourProvider, later);
  return scheduler;
});

/// Keeps the phone's scheduled reminders in step with the workspace, so
/// deadlines are announced even when DueDesk is not running.
///
/// Every obligation the signed-in person can see is covered, across all of
/// their organisations. Signing out, or turning off *Push notifications*,
/// cancels them all.
class ReminderScheduler {
  final Ref ref;
  ReminderScheduler(this.ref);
  bool _started = false, _pending = false, _running = false;

  /// What was last handed to the phone, so unchanged plans are not resent
  /// on every refresh.
  String? _lastPlan;

  /// Overridable clock for tests.
  DateTime Function() now = DateTime.now;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final system = ref.read(systemNotificationsProvider);
    await system.initialize(
      (id) => ref.read(notificationServiceProvider).openDueItem(id),
    );
    final launched = await system.launchItem();
    if (launched != null) {
      ref.read(notificationServiceProvider).openDueItem(launched);
    }
    await schedule();
  }

  /// Coalesces bursts of changes into one pass.
  Future<void> schedule() async {
    if (!_started) return;
    _pending = true;
    if (_running) return;
    _running = true;
    try {
      while (_pending) {
        _pending = false;
        await _plan();
      }
    } catch (_) {
      // Retried on the next change.
    } finally {
      _running = false;
    }
  }

  Future<void> _plan() async {
    final system = ref.read(systemNotificationsProvider);
    final user = ref.read(authProvider).value;
    final settings = ref.read(settingsProvider);
    if (user == null || settings['push'] == false) {
      if (_lastPlan != '') await system.cancelAll();
      _lastPlan = '';
      return;
    }
    final data = ref.read(workspaceProvider).value;
    if (data == null) return;
    final plan = planReminders(
      items: data.items,
      organisations: {for (final o in data.organisations) o.id: o},
      now: now(),
      hour: ref.read(reminderHourProvider),
      overdueAlerts: settings['overdue'] ?? true,
      showDetails: settings['preview'] ?? true,
    );
    final prefs = ref.read(preferencesProvider);
    // Ask once, when there is first something worth announcing.
    if (plan.isNotEmpty &&
        prefs.getBool('notificationPermissionAsked') != true) {
      await prefs.setBool('notificationPermissionAsked', true);
      await system.requestPermission();
    }
    final signature = [
      for (final r in plan) '${r.id}|${r.when}|${r.title}|${r.body}',
    ].join('\n');
    if (signature == _lastPlan) return;
    await system.replaceAll(plan);
    _lastPlan = signature;
  }
}
