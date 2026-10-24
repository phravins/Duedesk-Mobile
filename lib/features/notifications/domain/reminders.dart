import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/utils/due_dates.dart';
import '../../../shared/models/models.dart';

/// Notification types raised by the reminder schedule, as opposed to the
/// activity of people working on an obligation.
const reminderTypes = {'overdue', 'dueToday', 'dueSoon'};

/// Works out which reminders are owed today.
///
/// Each open obligation raises at most one reminder per threshold in its
/// reminder schedule (for example 7, 3, 1 and 0 days before), plus one when
/// it becomes overdue. If the app was closed when a threshold passed, the
/// most recent missed threshold is delivered instead of all of them. A
/// reminder is never repeated, including after a restart, because its ID is
/// derived from the obligation, the threshold and the due date.
List<DueNotification> remindersDue(
  Iterable<DueItem> items,
  Iterable<DueNotification> existing,
  DateTime today, {
  bool overdueAlerts = true,
  DateTime? now,
}) {
  final ids = existing.map((n) => n.id).toSet();
  final sentToday = {
    for (final n in existing)
      if (DueDates.date(n.timestamp) == DueDates.date(today))
        '${n.dueItemId}:${n.type}',
  };
  final stamp = now ?? DateTime.now();
  final result = <DueNotification>[];
  for (final item in items) {
    if (item.isClosed || item.status == DueStatus.archived) continue;
    final days = DueDates.daysLeft(item.dueDate, today);
    final String type;
    final int threshold;
    if (days < 0) {
      if (!overdueAlerts) continue;
      type = 'overdue';
      threshold = -1;
    } else {
      final config = item.reminderConfiguration;
      if (!config.enabled) continue;
      final owed = config.daysBefore.where((d) => d >= days).toList();
      if (owed.isEmpty) continue;
      threshold = owed.reduce((a, b) => a < b ? a : b);
      type = days == 0 ? 'dueToday' : 'dueSoon';
    }
    final id =
        'reminder:${item.id}:$threshold:${DateFormat('yyyy-MM-dd').format(item.dueDate)}';
    if (ids.contains(id) || sentToday.contains('${item.id}:$type')) continue;
    result.add(
      DueNotification(
        id: id,
        organisationId: item.organisationId,
        dueItemId: item.id,
        type: type,
        message:
            '${item.title}: ${DueDates.relative(item.dueDate, today).toLowerCase()}.',
        timestamp: stamp,
      ),
    );
  }
  return result;
}

/// A reminder to hand to the phone, so it arrives even when DueDesk is
/// closed.
class PlannedReminder {
  /// Stable for the same obligation, threshold and due date, so planning
  /// again replaces rather than duplicates.
  final int id;
  final String itemId, type, title, body;
  final tz.TZDateTime when;
  const PlannedReminder({
    required this.id,
    required this.itemId,
    required this.type,
    required this.title,
    required this.body,
    required this.when,
  });
}

/// A positive 31-bit FNV-1a hash: the same text always gives the same ID.
int stableNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Plans the phone notifications for every open obligation.
///
/// Each threshold in an obligation's reminder schedule becomes one
/// notification at [hour] o'clock in its organisation's time zone, and one
/// more arrives the morning after it becomes overdue. Only future moments
/// are planned, soonest first, up to [limit] (iOS keeps at most 64).
///
/// With [showDetails] off, titles stay off the lock screen: the text says
/// only that something is due.
List<PlannedReminder> planReminders({
  required Iterable<DueItem> items,
  required Map<String, Organisation> organisations,
  required DateTime now,
  int hour = 9,
  bool overdueAlerts = true,
  bool showDetails = true,
  int limit = 60,
}) {
  final plans = <PlannedReminder>[];
  final many = organisations.length > 1;
  for (final item in items) {
    if (item.isClosed || item.status == DueStatus.archived) continue;
    final org = organisations[item.organisationId];
    tz.Location location;
    try {
      location = tz.getLocation(org?.timezone ?? 'UTC');
    } catch (_) {
      location = tz.UTC;
    }
    final due = DueDates.date(item.dueDate);
    final key = DateFormat('yyyy-MM-dd').format(due);
    void add(int daysBefore, String type, String label) {
      final day = due.subtract(Duration(days: daysBefore));
      final when = tz.TZDateTime(location, day.year, day.month, day.day, hour);
      if (!when.isAfter(now)) return;
      final where = many && org != null ? ' · ${org.name}' : '';
      plans.add(
        PlannedReminder(
          id: stableNotificationId('${item.id}:$daysBefore:$key'),
          itemId: item.id,
          type: type,
          title: showDetails ? item.title : 'DueDesk reminder',
          body: showDetails
              ? '$label · ${DueDates.format(due)}$where'
              : 'An obligation is ${label.toLowerCase()}. Open DueDesk to see it.',
          when: when,
        ),
      );
    }

    final config = item.reminderConfiguration;
    if (config.enabled) {
      for (final days in config.daysBefore.toSet()) {
        if (days < 0) continue;
        add(days, days == 0 ? 'dueToday' : 'dueSoon', switch (days) {
          0 => 'Due today',
          1 => 'Due tomorrow',
          _ => 'Due in $days days',
        });
      }
    }
    if (overdueAlerts) add(-1, 'overdue', 'Overdue');
  }
  plans.sort((a, b) => a.when.compareTo(b.when));
  return plans.take(limit).toList();
}
