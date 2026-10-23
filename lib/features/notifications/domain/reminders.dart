import 'package:intl/intl.dart';
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
