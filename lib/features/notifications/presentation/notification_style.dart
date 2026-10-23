import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/due_widgets.dart';

/// Title, icon and colour for each kind of notification.
({String title, IconData icon, Color color}) notificationStyle(
  BuildContext context,
  String type,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (type) {
    'overdue' => (
      title: 'Overdue',
      icon: Icons.error_outline_rounded,
      color: statusTextColor(context, DueStatus.overdue),
    ),
    'dueToday' => (
      title: 'Due today',
      icon: Icons.today_rounded,
      color: statusTextColor(context, DueStatus.dueToday),
    ),
    'dueSoon' || 'upcoming' => (
      title: 'Coming up',
      icon: Icons.schedule_rounded,
      color: statusTextColor(context, DueStatus.dueSoon),
    ),
    'completed' || 'renewed' => (
      title: type == 'renewed' ? 'Renewed' : 'Completed',
      icon: Icons.check_circle_outline_rounded,
      color: statusTextColor(context, DueStatus.completed),
    ),
    'document_uploaded' => (
      title: 'New evidence',
      icon: Icons.attach_file_rounded,
      color: scheme.primary,
    ),
    'reassigned' => (
      title: 'Assignment',
      icon: Icons.person_outline_rounded,
      color: scheme.primary,
    ),
    _ => (
      title: 'Update',
      icon: Icons.notifications_none_rounded,
      color: AppColors.secondary,
    ),
  };
}

/// "Just now", "12 min ago", "3:05 PM" or "4 Oct".
String notificationTime(DateTime timestamp, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = timestamp.toLocal();
  final age = current.difference(local);
  if (age.inSeconds < 60 && !age.isNegative) return 'Just now';
  if (age.inMinutes < 60 && !age.isNegative) return '${age.inMinutes} min ago';
  if (DateUtils.isSameDay(local, current)) {
    return DateFormat('h:mm a').format(local);
  }
  return DateFormat('d MMM').format(local);
}

class NotificationIcon extends StatelessWidget {
  final String type;
  final double size;
  const NotificationIcon({super.key, required this.type, this.size = 38});
  @override
  Widget build(BuildContext context) {
    final style = notificationStyle(context, type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(style.icon, size: size * .52, color: style.color),
    );
  }
}
