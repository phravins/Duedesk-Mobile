import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/due_dates.dart';
import '../../../core/widgets/glass.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/due_widgets.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  const CalendarScreen({super.key, this.initialDate});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarState();
}

class _CalendarState extends ConsumerState<CalendarScreen> {
  late DateTime month, selected;
  bool agenda = false;
  @override
  void initState() {
    super.initState();
    selected = DueDates.date(widget.initialDate ?? ref.read(todayProvider));
    month = DateTime.utc(selected.year, selected.month);
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != null &&
        widget.initialDate != oldWidget.initialDate) {
      selected = DueDates.date(widget.initialDate!);
      month = DateTime.utc(selected.year, selected.month);
      agenda = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref
            .watch(dueItemsProvider)
            .where((i) => i.status != DueStatus.archived)
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final today = ref.watch(todayProvider);
    final dayItems = items
        .where((i) => DueDates.date(i.dueDate) == selected)
        .toList();
    final offset = (month.weekday - 1) % 7;
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    return WorkspaceBody(
      child: PageBody(
        children: [
          const ScreenHeading(
            title: 'Calendar',
            subtitle: 'A little perspective on what’s ahead.',
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Month'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Agenda'),
                icon: Icon(Icons.view_agenda_outlined),
              ),
            ],
            selected: {agenda},
            onSelectionChanged: (v) => setState(() => agenda = v.first),
          ),
          const SizedBox(height: 24),
          if (!agenda) ...[
            GlassCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(month),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => setState(
                          () =>
                              month = DateTime.utc(month.year, month.month - 1),
                        ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => setState(
                          () =>
                              month = DateTime.utc(month.year, month.month + 1),
                        ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, c) => Wrap(
                      children: [
                        for (
                          int n = 0;
                          n < ((days + offset) / 7).ceil() * 7;
                          n++
                        )
                          SizedBox(
                            width: c.maxWidth / 7,
                            height: MediaQuery.textScalerOf(
                              context,
                            ).scale(48).clamp(48, 80),
                            child: n < offset || n >= offset + days
                                ? null
                                : Builder(
                                    builder: (context) {
                                      final date = DateTime.utc(
                                        month.year,
                                        month.month,
                                        n - offset + 1,
                                      );
                                      final count = items
                                          .where(
                                            (i) =>
                                                DueDates.date(i.dueDate) ==
                                                date,
                                          )
                                          .length;
                                      final active = selected == date;
                                      return Semantics(
                                        label:
                                            '${DueDates.format(date, year: true)}, $count obligations',
                                        selected: active,
                                        button: true,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: () =>
                                              setState(() => selected = date),
                                          child: Container(
                                            margin: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : date == today
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: .1)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppSizes.radiusMd,
                                                  ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '${date.day}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        date == today || active
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                    color: active
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .onPrimary
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    for (
                                                      int i = 0;
                                                      i < count.clamp(0, 3);
                                                      i++
                                                    )
                                                      Container(
                                                        width: 3,
                                                        height: 3,
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: active
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onPrimary
                                                              : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SectionHeader(
              title: DateFormat('EEEE, d MMMM').format(selected),
              action: 'Today',
              onAction: () => setState(() {
                selected = today;
                month = DateTime.utc(today.year, today.month);
              }),
            ),
            if (dayItems.isEmpty)
              const EmptyState(
                title: 'A little breathing room.',
                message: 'No obligations due on this day.',
                icon: Icons.event_available_outlined,
              ),
            for (final i in dayItems) DueItemCard(item: i),
          ] else ...[
            for (final label in [
              'Overdue',
              'Today',
              'Tomorrow',
              'This Week',
              'Later',
              'Completed',
            ]) ...[_AgendaGroup(label: label, items: items, today: today)],
          ],
        ],
      ),
    );
  }
}

class _AgendaGroup extends StatelessWidget {
  final String label;
  final List<DueItem> items;
  final DateTime today;
  const _AgendaGroup({
    required this.label,
    required this.items,
    required this.today,
  });
  @override
  Widget build(BuildContext context) {
    final filtered = items.where((i) {
      final days = DueDates.daysLeft(i.dueDate, today);
      if (label == 'Completed') return i.isClosed;
      if (i.isClosed) return false;
      return switch (label) {
        'Overdue' => days < 0,
        'Today' => days == 0,
        'Tomorrow' => days == 1,
        'This Week' => days > 1 && days <= 7 - today.weekday,
        _ => days > 1 && days > 7 - today.weekday,
      };
    }).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: label),
        for (final item in filtered) DueItemCard(item: item),
      ],
    );
  }
}
