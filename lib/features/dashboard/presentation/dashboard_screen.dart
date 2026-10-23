import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/due_dates.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/widgets/glass.dart';
import '../../../shared/widgets/due_widgets.dart';
import '../../../shared/models/models.dart';
import '../domain/dashboard_summary.dart';

final dashboardProvider = Provider<DashboardSummary>(
  (ref) => DashboardSummary.fromItems(
    ref.watch(dueItemsProvider),
    ref.watch(todayProvider),
  ),
);

String greeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 17
    ? 'Good afternoon'
    : 'Good evening';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider),
        org = ref.watch(organisationProvider);
    final items = ref.watch(dueItemsProvider),
        summary = ref.watch(dashboardProvider);
    final today = ref.watch(todayProvider),
        pins = ref.watch(pinnedItemsProvider);
    final next = items.where((i) => !i.isClosed).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final completed =
        items
            .where(
              (i) =>
                  [DueStatus.completed, DueStatus.renewed].contains(i.status),
            )
            .toList()
          ..sort(
            (a, b) => (b.completionDate ?? b.updatedAt).compareTo(
              a.completionDate ?? a.updatedAt,
            ),
          );
    final pinned = items
        .where((i) => pins.contains(i.id) && i.status != DueStatus.archived)
        .toList();
    final unread = ref
        .watch(notificationsProvider)
        .where((n) => !n.read)
        .length;
    final scheme = Theme.of(context).colorScheme;
    final upcoming = next.isEmpty
        ? <Widget>[
            const EmptyState(
              message: 'No open obligations. Enjoy the clarity.',
            ),
          ]
        : [
            LayoutBuilder(
              builder: (context, c) => Wrap(
                spacing: 12,
                children: [
                  for (final item in next.take(4))
                    SizedBox(
                      width: c.maxWidth > 700
                          ? (c.maxWidth - 12) / 2
                          : c.maxWidth,
                      child: DueItemCard(item: item),
                    ),
                ],
              ),
            ),
          ];
    final upcomingSection = [
      SectionHeader(
        title: 'Upcoming deadlines',
        action: 'View all',
        onAction: () => context.go('/due'),
      ),
      ...upcoming,
    ];
    final pinnedSection = [
      if (pinned.isNotEmpty) ...[
        SectionHeader(
          title: 'Pinned obligations',
          action: 'View all',
          onAction: () => context.go('/due?filter=Pinned'),
        ),
        for (final item in pinned.take(2)) DueItemCard(item: item),
      ],
    ];
    final weekSection = [
      SectionHeader(
        title: 'Your next 7 days',
        action: 'Calendar',
        onAction: () => context.go('/calendar'),
      ),
      GlassCard(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            for (var n = 0; n < 7; n++)
              Expanded(
                child: _WeekDay(
                  day: today.add(Duration(days: n)),
                  items: next,
                  isToday: n == 0,
                ),
              ),
          ],
        ),
      ),
    ];
    final completedSection = [
      SectionHeader(
        title: 'Recently completed',
        action: 'View history',
        onAction: () => context.go('/due?filter=Completed'),
      ),
      if (completed.isEmpty)
        const EmptyState(
          title: 'Your history starts here.',
          message: 'Completed obligations and evidence will stay on record.',
        )
      else
        for (final item in completed.take(2)) DueItemCard(item: item),
    ];
    return WorkspaceBody(
      child: PageBody(
        onRefresh: () => ref.read(workspaceProvider.notifier).refresh(),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM').format(today).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${greeting(DateTime.now())}, ${user.name.split(' ').first}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const CompanySwitcher(),
                  ],
                ),
              ),
              Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                offset: const Offset(-6, 6),
                child: IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => context.push('/notifications'),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => context.push('/profile'),
                icon: UserAvatar(
                  name: user.name,
                  image: user.avatarUrl,
                  radius: 16,
                ),
              ),
            ],
          ),
          const SectionHeader(title: 'Due overview'),
          _OverviewCard(summary: summary),
          const SizedBox(height: 10),
          Row(
            children: [
              if (Permissions.manage(user, org.id)) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => context.push('/due/new'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Due Item'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => context.push('/due/new?templates=true'),
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: const Text('Templates'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Upload document',
                  style: AppIconButtonStyles.outlined(scheme).copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(42, 42)),
                  ),
                  onPressed: () => context.push('/documents?upload=true'),
                  icon: const Icon(
                    Icons.upload_file_outlined,
                    size: AppSizes.iconMd,
                  ),
                ),
              ] else
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 42),
                    ),
                    onPressed: () => context.push('/documents?upload=true'),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload document'),
                  ),
                ),
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...pinnedSection,
                    ...upcomingSection,
                    ...weekSection,
                    ...completedSection,
                  ],
                );
              }
              // Wide screens: deadlines on the left, context on the right.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: 'Upcoming deadlines',
                          action: 'View all',
                          onAction: () => context.go('/due'),
                        ),
                        if (next.isEmpty)
                          upcoming.single
                        else
                          for (final item in next.take(4))
                            DueItemCard(item: item),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...weekSection,
                        ...pinnedSection,
                        ...completedSection,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One compact card: what needs attention first, then the four counts.
class _OverviewCard extends StatelessWidget {
  final DashboardSummary summary;
  const _OverviewCard({required this.summary});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = summary.overdue > 0
        ? statusTextColor(context, DueStatus.overdue)
        : scheme.primary;
    final metrics = [
      ('Overdue', summary.overdue, statusTextColor(context, DueStatus.overdue)),
      ('Today', summary.today, statusTextColor(context, DueStatus.dueToday)),
      ('This Week', summary.thisWeek, scheme.primary),
      ('Upcoming', summary.upcoming, scheme.onSurface),
    ];
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: summary.attention == 0 ? scheme.outline : accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.attention == 0
                            ? 'You’re all caught up.'
                            : '${summary.attention} items need your attention',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${summary.overdue} overdue · ${summary.today} today · ${summary.dueSoon} soon',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (summary.attention > 0)
                  TextButton(
                    onPressed: () => context.go('/due?filter=Attention'),
                    child: const Text('Review now'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          IntrinsicHeight(
            child: Row(
              children: [
                for (final (i, (label, count, color)) in metrics.indexed) ...[
                  if (i > 0) const VerticalDivider(width: 1),
                  Expanded(
                    child: InkWell(
                      onTap: () => context.go(
                        '/due?filter=${Uri.encodeComponent(label)}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: count == 0
                                    ? scheme.onSurfaceVariant
                                    : color,
                              ),
                            ),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  final DateTime day;
  final List<DueItem> items;
  final bool isToday;
  const _WeekDay({
    required this.day,
    required this.items,
    this.isToday = false,
  });
  @override
  Widget build(BuildContext context) {
    final count = items
        .where((i) => DueDates.daysLeft(i.dueDate, day) == 0)
        .length;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${DateFormat('EEEE d MMMM').format(day)}, $count obligations',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => context.go(
          '/calendar?date=${DateFormat('yyyy-MM-dd').format(day)}',
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isToday ? scheme.onSurface : null,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Column(
            children: [
              Text(
                DateFormat('EEEEE').format(day),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isToday
                      ? scheme.surface.withValues(alpha: .75)
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isToday ? scheme.surface : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: count > 0
                      ? (isToday ? scheme.surface : scheme.primary)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
