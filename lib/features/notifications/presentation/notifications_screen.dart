import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../shared/models/models.dart';
import 'notification_style.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool unreadOnly = false;

  Future<bool> markRead(DueNotification n) => runAction(
    context,
    () => ref
        .read(workspaceProvider.notifier)
        .act((r, a) => r.markRead(a, n.organisationId, id: n.id)),
  );

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(notificationsProvider).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final unread = all.where((n) => !n.read).length;
    final visible = unreadOnly ? all.where((n) => !n.read).toList() : all;
    final org = ref.watch(organisationProvider);
    final now = DateTime.now();
    String group(DateTime t) {
      final day = DateUtils.dateOnly(t.toLocal());
      final today = DateUtils.dateOnly(now);
      if (day == today) return 'Today';
      if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
      return 'Earlier';
    }

    final groups = <String, List<DueNotification>>{};
    for (final n in visible) {
      groups.putIfAbsent(group(n.timestamp), () => []).add(n);
    }
    return DueDeskScaffold(
      title: 'Notifications',
      actions: [
        TextButton(
          onPressed: unread == 0
              ? null
              : () => runAction(
                  context,
                  () => ref
                      .read(workspaceProvider.notifier)
                      .act((r, a) => r.markRead(a, org.id)),
                  success: 'All notifications marked as read',
                ),
          child: const Text('Read all'),
        ),
      ],
      child: WorkspaceBody(
        child: PageBody(
          onRefresh: () => ref.read(workspaceProvider.notifier).refresh(),
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text('All (${all.length})'),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Unread ($unread)'),
                      ),
                    ],
                    selected: {unreadOnly},
                    onSelectionChanged: (v) =>
                        setState(() => unreadOnly = v.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (visible.isEmpty)
              EmptyState(
                title: unreadOnly
                    ? 'You’re all caught up.'
                    : 'Nothing new for now.',
                message: 'Reminders and updates will appear here.',
                icon: Icons.notifications_none,
              ),
            for (final entry in groups.entries) ...[
              SectionHeader(title: entry.key),
              for (final n in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: n.read
                      ? _NotificationCard(notification: n, now: now)
                      : Dismissible(
                          key: ValueKey('notification-${n.id}'),
                          direction: DismissDirection.endToStart,
                          // Swiping marks it read; the card stays listed.
                          confirmDismiss: (_) async =>
                              await markRead(n) && unreadOnly,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(
                                AppSizes.radiusLg,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.mark_email_read_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Mark read',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          child: _NotificationCard(notification: n, now: now),
                        ),
                ),
            ],
            if (unread > 0 && !unreadOnly)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Tip: swipe left on a notification to mark it read.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  final DueNotification notification;
  final DateTime now;
  const _NotificationCard({required this.notification, required this.now});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final scheme = Theme.of(context).colorScheme;
    final style = notificationStyle(context, n.type);
    return GlassCard(
      tint: n.read
          ? null
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: .06),
              scheme.surfaceContainerLowest,
            ),
      onTap: () async {
        if (!n.read) {
          final ok = await runAction(
            context,
            () => ref
                .read(workspaceProvider.notifier)
                .act((r, a) => r.markRead(a, n.organisationId, id: n.id)),
          );
          if (!ok) return;
        }
        if (context.mounted) context.push('/due/${n.dueItemId}');
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NotificationIcon(type: n.type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: style.color,
                        ),
                      ),
                    ),
                    Text(
                      notificationTime(n.timestamp, now: now),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  n.message,
                  style: TextStyle(
                    fontWeight: n.read ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!n.read)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Semantics(
                label: 'Unread',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
