import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/due_dates.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/illustrations.dart';
import '../../../shared/models/models.dart';
import '../domain/compliance_calendar.dart';

/// Preference that hides the dashboard suggestion for an organisation.
String complianceSuggestionKey(String organisationId) =>
    'complianceSuggestionDismissed:$organisationId';

/// One-tap setup of common Indian statutory deadlines as recurring
/// obligations, with owner, dates and reminders filled in.
class ComplianceSetupScreen extends ConsumerStatefulWidget {
  const ComplianceSetupScreen({super.key});
  @override
  ConsumerState<ComplianceSetupScreen> createState() => _ComplianceSetupState();
}

class _ComplianceSetupState extends ConsumerState<ComplianceSetupScreen> {
  final selected = <String>{'gst', 'tds'};
  String? ownerId;
  bool busy = false;

  List<int> get reminderDays {
    final settings = ref.read(settingsProvider);
    final days = [
      for (final d in [30, 15, 7, 3, 1, 0])
        if (settings['reminder$d'] == true) d,
    ];
    return days.isEmpty ? const [7, 3, 1, 0] : days;
  }

  List<DueItem> plan(User owner) => ComplianceCalendar.plan(
    packIds: selected,
    organisation: ref.read(organisationProvider),
    categories: ref.read(categoriesProvider),
    existing: ref.read(dueItemsProvider),
    owner: owner,
    creator: ref.read(currentUserProvider),
    today: ref.read(todayProvider),
    reminderDays: reminderDays,
  );

  Future<void> create(User owner) async {
    setState(() => busy = true);
    final org = ref.read(organisationProvider);
    var added = 0;
    final ok = await runAction(context, () async {
      final workspace = ref.read(workspaceProvider.notifier);
      final missing = ComplianceCalendar.missingCategories(
        selected,
        org.id,
        ref.read(categoriesProvider),
      );
      if (missing.isNotEmpty) {
        await workspace.act((r, a) async {
          for (final name in missing) {
            await r.saveCategory(
              a,
              DueCategory(id: newId(), organisationId: org.id, name: name),
            );
          }
        });
      }
      final items = plan(owner);
      await workspace.act((r, a) async {
        for (final item in items) {
          await r.createDueItem(a, item);
          added++;
        }
      });
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      await ref
          .read(preferencesProvider)
          .setBool(complianceSuggestionKey(org.id), true);
      if (!mounted) return;
      DueHaptics.confirm();
      feedback(
        context,
        added == 0
            ? 'Everything selected is already in your workspace.'
            : 'Added $added obligations to your compliance calendar.',
      );
      context.go('/due');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final org = ref.watch(organisationProvider);
    final team = ref
        .watch(teamProvider)
        .where((u) => u.roleIn(org.id) != null)
        .toList();
    final owner =
        team.where((u) => u.id == ownerId).firstOrNull ??
        team.where((u) => u.id == user.id).firstOrNull ??
        team.firstOrNull;
    final today = ref.watch(todayProvider);
    final existing = [
      for (final i in ref.watch(dueItemsProvider))
        if (!i.isClosed) i.title,
    ];
    final items = owner == null ? <DueItem>[] : plan(owner);
    final scheme = Theme.of(context).colorScheme;
    return DueDeskScaffold(
      title: 'Compliance calendar',
      child: WorkspaceBody(
        child: !Permissions.manage(user, org.id)
            ? const EmptyState(
                title: 'Access restricted',
                message:
                    'An owner or admin can set up the compliance calendar.',
              )
            : PageBody(
                children: [
                  GlassCard(
                    child: Row(
                      children: [
                        const DeskIllustration(
                          kind: DeskArt.calendar,
                          size: 76,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Set up ${org.name} in one go',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose what applies. Each deadline becomes a recurring obligation with its owner and reminders set.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader(title: 'What applies to you'),
                  for (final pack in ComplianceCalendar.packs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              value: selected.contains(pack.id),
                              onChanged: (v) => setState(
                                () => v == true
                                    ? selected.add(pack.id)
                                    : selected.remove(pack.id),
                              ),
                              title: Text(
                                pack.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                pack.subtitle,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            if (selected.contains(pack.id))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  10,
                                ),
                                child: Column(
                                  children: [
                                    for (final rule in pack.rules)
                                      _RuleRow(
                                        rule: rule,
                                        next: rule.nextDue(today),
                                        already: existing.any(rule.matches),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SectionHeader(title: 'Who looks after these'),
                  GlassDropdown<String>(
                    label: 'Owner',
                    value: owner?.id,
                    options: {for (final u in team) u.id: u.name},
                    onChanged: (v) => setState(() => ownerId = v),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'These are the usual statutory dates. Deadlines are often extended, and some depend on your state or filing scheme, so check them with your accountant. You can edit any obligation afterwards.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: items.isEmpty
                        ? 'Nothing new to add'
                        : 'Add ${items.length} obligations',
                    icon: Icons.event_available_outlined,
                    loading: busy,
                    onPressed: items.isEmpty || owner == null
                        ? null
                        : () => create(owner),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final ComplianceRule rule;
  final DateTime next;
  final bool already;
  const _RuleRow({
    required this.rule,
    required this.next,
    required this.already,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repeat = rule.frequency == Frequency.monthly ? 'Monthly' : 'Yearly';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            already ? Icons.check_circle_rounded : Icons.event_outlined,
            size: 16,
            color: already ? AppColors.success : scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rule.title,
              style: TextStyle(
                fontSize: 13.5,
                color: already ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            already
                ? 'Already added'
                : '$repeat · ${DueDates.format(next, year: true)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
