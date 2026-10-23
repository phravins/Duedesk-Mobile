import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/utils/due_dates.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/due_widgets.dart';

class DueListScreen extends ConsumerStatefulWidget {
  final String initialFilter;
  const DueListScreen({super.key, this.initialFilter = 'All'});
  @override
  ConsumerState<DueListScreen> createState() => _DueListState();
}

class _DueListState extends ConsumerState<DueListScreen> {
  final search = TextEditingController();
  Timer? debounce;
  String query = '', segment = 'All', sort = 'Due date';
  DueFilter filters = const DueFilter();
  @override
  void initState() {
    super.initState();
    segment = widget.initialFilter;
  }

  @override
  void didUpdateWidget(covariant DueListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      segment = widget.initialFilter;
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(organisationProvider),
        user = ref.watch(currentUserProvider);
    final f = DueFilter(
      query: query,
      segment: segment,
      status: filters.status,
      categoryId: filters.categoryId,
      assigneeId: filters.assigneeId,
      priority: filters.priority,
      from: filters.from,
      to: filters.to,
    );
    final pins = ref.watch(pinnedItemsProvider);
    final items = f.apply(
      ref.watch(dueItemsProvider),
      ref.watch(todayProvider),
      user.id,
    );
    if (segment == 'Pinned') items.removeWhere((i) => !pins.contains(i.id));
    items.sort(
      (a, b) => sort == 'Title'
          ? a.title.compareTo(b.title)
          : sort == 'Priority'
          ? b.priority.index.compareTo(a.priority.index)
          : a.dueDate.compareTo(b.dueDate),
    );
    return WorkspaceBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                ScreenHeading(
                  title: 'Due Items',
                  subtitle: 'Every obligation. Clear ownership.',
                  trailing: Permissions.manage(user, org.id)
                      ? IconButton.filled(
                          style: AppIconButtonStyles.filled(),
                          tooltip: 'Create Due Item',
                          onPressed: () => context.push('/due/new'),
                          icon: const Icon(Icons.add_rounded),
                        )
                      : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: search,
                        decoration: const InputDecoration(
                          hintText: 'Search obligations…',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (v) {
                          debounce?.cancel();
                          debounce = Timer(
                            const Duration(milliseconds: 250),
                            () {
                              if (mounted) setState(() => query = v);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: filters.active,
                      smallSize: 9,
                      child: IconButton.outlined(
                        style: AppIconButtonStyles.outlined(
                          Theme.of(context).colorScheme,
                        ),
                        tooltip: filters.active
                            ? 'Filter DueItems (filters on)'
                            : 'Filter DueItems',
                        onPressed: () async {
                          final result = await glassSheet<DueFilter>(
                            context,
                            DueFilterSheet(initial: filters),
                          );
                          if (result != null) setState(() => filters = result);
                        },
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final label in {
                        'All',
                        'My Items',
                        'Pinned',
                        'Overdue',
                        'Due Soon',
                        'Completed',
                        if (![
                          'All',
                          'My Items',
                          'Overdue',
                          'Due Soon',
                          'Completed',
                        ].contains(segment))
                          segment,
                      })
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            showCheckmark: false,
                            label: Text(label),
                            selected: segment == label,
                            onSelected: (_) => setState(() => segment = label),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${items.length} obligations',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Sort obligations',
                      initialValue: sort,
                      onSelected: (v) => setState(() => sort = v),
                      itemBuilder: (_) => [
                        for (final s in ['Due date', 'Title', 'Priority'])
                          PopupMenuItem(value: s, child: Text(s)),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.swap_vert_rounded, size: 16),
                            const SizedBox(width: 5),
                            Text(sort, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await runAction(
                  context,
                  () => ref.read(workspaceProvider.notifier).refresh(),
                );
              },
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          title: segment == 'Pinned'
                              ? 'Keep priorities close.'
                              : segment == 'Overdue'
                              ? 'Nothing overdue.'
                              : "You're all clear.",
                          message: segment == 'Pinned'
                              ? 'Pin an obligation using its bookmark icon. Your pins are personal to this workspace.'
                              : query.isNotEmpty
                              ? 'Try another search or reset your filters.'
                              : segment == 'Overdue'
                              ? "You're on track."
                              : 'Create your first DueItem to start tracking what matters.',
                          action: segment == 'Pinned'
                              ? 'Browse obligations'
                              : query.isNotEmpty
                              ? 'Clear search'
                              : Permissions.manage(user, org.id)
                              ? 'Create Due Item'
                              : null,
                          onAction: () {
                            if (segment == 'Pinned') {
                              setState(() => segment = 'All');
                            } else if (query.isNotEmpty) {
                              search.clear();
                              setState(() => query = '');
                            } else {
                              context.push('/due/new');
                            }
                          },
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth > 760 ? 2 : 1;
                        return ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            2,
                            16,
                            20 + MediaQuery.paddingOf(context).bottom,
                          ),
                          itemCount: (items.length / cols).ceil(),
                          itemBuilder: (context, index) => cols == 1
                              ? DueItemCard(item: items[index])
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: DueItemCard(
                                        item: items[index * 2],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: index * 2 + 1 < items.length
                                          ? DueItemCard(
                                              item: items[index * 2 + 1],
                                            )
                                          : const SizedBox(),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class DueFilterSheet extends ConsumerStatefulWidget {
  final DueFilter initial;
  const DueFilterSheet({super.key, required this.initial});
  @override
  ConsumerState<DueFilterSheet> createState() => _FilterState();
}

class _FilterState extends ConsumerState<DueFilterSheet> {
  DueStatus? status;
  String? category, assignee;
  Priority? priority;
  DateTime? from, to;
  String dateOption = 'Any date';
  @override
  void initState() {
    super.initState();
    status = widget.initial.status;
    category = widget.initial.categoryId;
    assignee = widget.initial.assigneeId;
    priority = widget.initial.priority;
    from = widget.initial.from;
    to = widget.initial.to;
    if (from != null || to != null) dateOption = 'Custom range';
  }

  Future<void> selectDate(String option) async {
    final today = ref.read(todayProvider);
    DateTime? start, end;
    switch (option) {
      case 'Today':
        start = today;
        end = today;
      case 'Tomorrow':
        start = today.add(const Duration(days: 1));
        end = start;
      case 'This week':
        start = today;
        end = today.add(Duration(days: 7 - today.weekday));
      case 'Next 7 days':
        start = today;
        end = today.add(const Duration(days: 7));
      case 'This month':
        start = DateTime.utc(today.year, today.month, 1);
        end = DateTime.utc(today.year, today.month + 1, 0);
      case 'Overdue':
        end = today.subtract(const Duration(days: 1));
      case 'Custom range':
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (range == null) return;
        start = range.start;
        end = range.end;
    }
    if (mounted) {
      setState(() {
        dateOption = option;
        from = start;
        to = end;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Filter obligations', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      GlassDropdown<DueStatus?>(
        label: 'Status',
        value: status,
        options: {
          null: 'Any status',
          for (final s in DueStatus.values) s: s.label,
        },
        onChanged: (v) => setState(() => status = v),
      ),
      GlassDropdown<String?>(
        label: 'Category',
        value: category,
        options: {
          null: 'All categories',
          for (final c in ref.watch(categoriesProvider)) c.id: c.name,
        },
        onChanged: (v) => setState(() => category = v),
      ),
      GlassDropdown<String?>(
        label: 'Assignee',
        value: assignee,
        options: {
          null: 'Anyone',
          for (final u in ref.watch(teamProvider)) u.id: u.name,
        },
        onChanged: (v) => setState(() => assignee = v),
      ),
      GlassDropdown<Priority?>(
        label: 'Priority',
        value: priority,
        options: {
          null: 'Any priority',
          for (final p in Priority.values) p: p.label,
        },
        onChanged: (v) => setState(() => priority = v),
      ),
      GlassDropdown<String>(
        label: 'Due date',
        value: dateOption,
        options: {
          for (final d in [
            'Any date',
            'Today',
            'Tomorrow',
            'This week',
            'Next 7 days',
            'This month',
            'Overdue',
            'Custom range',
          ])
            d: d,
        },
        onChanged: (v) => selectDate(v!),
      ),
      if (from != null || to != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '${from == null ? 'Any time' : DueDates.format(from!, year: true)} → ${to == null ? 'Any time' : DueDates.format(to!, year: true)}',
          ),
        ),
      Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: 'Reset',
              onPressed: () => setState(() {
                status = null;
                category = null;
                assignee = null;
                priority = null;
                from = null;
                to = null;
                dateOption = 'Any date';
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: 'Apply Filters',
              onPressed: () => Navigator.pop(
                context,
                DueFilter(
                  status: status,
                  categoryId: category,
                  assigneeId: assignee,
                  priority: priority,
                  from: from,
                  to: to,
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
