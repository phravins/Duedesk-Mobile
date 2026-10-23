import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../app/providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/due_dates.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/widgets/glass.dart';
import '../../../shared/models/models.dart';
import '../domain/due_template.dart';
import '../../../shared/widgets/due_widgets.dart';

class DueFormScreen extends ConsumerStatefulWidget {
  final String? id;
  final bool showTemplates;
  const DueFormScreen({super.key, this.id, this.showTemplates = false});
  @override
  ConsumerState<DueFormScreen> createState() => _DueFormState();
}

class _DueFormState extends ConsumerState<DueFormScreen> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      reference = TextEditingController(),
      authority = TextEditingController(),
      amount = TextEditingController(),
      notes = TextEditingController(),
      custom = TextEditingController(text: '30');
  DateTime? due, start;
  String? category, assignee;
  Frequency frequency = Frequency.oneTime;
  Priority priority = Priority.medium;
  String currency = 'INR';
  Set<int> reminders = {7, 3, 1, 0};
  bool initialized = false, busy = false;
  DueItem? original;
  List<PlatformFile> files = [];
  @override
  void dispose() {
    for (final c in [
      title,
      description,
      reference,
      authority,
      amount,
      notes,
      custom,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void initialize() {
    if (initialized) return;
    initialized = true;
    final prefs = ref.read(settingsProvider);
    reminders = {
      for (final n in [30, 15, 7, 3, 1, 0])
        if (prefs['reminder$n'] ?? false) n,
    };
    if (widget.id == null) return;
    original = ref.read(dueItemDetailProvider(widget.id!));
    if (original == null) return;
    final i = original!;
    title.text = i.title;
    description.text = i.description;
    reference.text = i.referenceNumber;
    authority.text = i.authority;
    amount.text = i.amount?.toString() ?? '';
    notes.text = i.notes;
    custom.text = i.recurrenceRule ?? '30';
    due = i.dueDate;
    start = i.startDate;
    category = i.categoryId;
    assignee = i.assignedToUserId;
    frequency = i.frequency;
    priority = i.priority;
    currency = i.currency;
    reminders = i.reminderConfiguration.daysBefore.toSet();
  }

  void applyTemplate(DueTemplate template) {
    setState(() {
      title.text = template.title;
      description.text = template.description;
      frequency = template.frequency;
      priority = template.priority;
      category = null;
      for (final c in ref.read(categoriesProvider)) {
        if (c.active &&
            c.name.toLowerCase() == template.category.toLowerCase()) {
          category = c.id;
        }
      }
    });
    feedback(
      context,
      'Template applied. Choose the due date and responsible person.',
    );
  }

  Future<void> pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'txt'],
      );
      if (result == null) return;
      if (result.files.any((f) => f.size > 20 * 1024 * 1024)) {
        throw const ValidationFailure('Each file must be smaller than 20 MB.');
      }
      if (mounted) setState(() => files.addAll(result.files));
    } catch (e) {
      if (mounted) feedback(context, friendlyError(e));
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (due == null) {
      feedback(context, 'Choose a due date.');
      return;
    }
    final org = ref.read(organisationProvider),
        user = ref.read(currentUserProvider);
    final c = ref.read(categoriesProvider).firstWhere((c) => c.id == category);
    final u = ref.read(teamProvider).firstWhere((u) => u.id == assignee);
    final now = DateTime.now();
    final item = DueItem(
      id: original?.id ?? newId(),
      organisationId: org.id,
      title: title.text.trim(),
      description: description.text.trim(),
      categoryId: c.id,
      categoryName: c.name,
      dueDate: DueDates.date(due!),
      startDate: start == null ? null : DueDates.date(start!),
      frequency: frequency,
      recurrenceRule: frequency == Frequency.custom ? custom.text : null,
      priority: priority,
      assignedToUserId: u.id,
      assignedToName: u.name,
      createdByUserId: original?.createdByUserId ?? user.id,
      referenceNumber: reference.text.trim(),
      authority: authority.text.trim(),
      amount: double.tryParse(amount.text),
      currency: currency,
      notes: notes.text.trim(),
      reminderConfiguration: ReminderConfiguration(
        enabled: reminders.isNotEmpty,
        daysBefore: reminders.toList()..sort((a, b) => b.compareTo(a)),
      ),
      createdAt: original?.createdAt ?? now,
      updatedAt: now,
    );
    setState(() => busy = true);
    bool saved = false;
    try {
      await ref
          .read(workspaceProvider.notifier)
          .act(
            (r, a) => original == null
                ? r.createDueItem(a, item)
                : r.updateDueItem(a, item),
          );
      saved = true;
      for (final f in files) {
        if (f.bytes == null) {
          throw const ValidationFailure(
            'Could not read the selected file. Upload it from the detail screen.',
          );
        }
        await ref
            .read(workspaceProvider.notifier)
            .act((r, a) => r.uploadDocument(a, item.id, f.name, f.bytes!));
      }
      DueHaptics.light();
      if (mounted) {
        feedback(
          context,
          original == null ? 'DueItem created' : 'Changes saved',
        );
        context.go('/due/${item.id}');
      }
    } catch (e) {
      if (mounted) {
        feedback(
          context,
          saved
              ? 'DueItem saved. An attachment failed: ${friendlyError(e)}'
              : friendlyError(e),
        );
        if (saved) context.go('/due/${item.id}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(workspaceProvider).hasValue) initialize();
    final org = ref.watch(organisationProvider);
    final allowed = Permissions.manage(ref.watch(currentUserProvider), org.id);
    return DueDeskScaffold(
      title: widget.id == null ? 'New Due Item' : 'Edit Due Item',
      child: WorkspaceBody(
        child: !allowed || original?.isClosed == true
            ? const EmptyState(
                title: 'Access restricted',
                message: 'An owner or admin can manage open obligations.',
              )
            : widget.id != null && original == null
            ? const EmptyState(
                title: 'DueItem unavailable',
                message: 'This item is not in the current organisation.',
              )
            : Form(
                key: form,
                child: PageBody(
                  eager: true,
                  children: [
                    if (widget.id == null) ...[
                      Text(
                        widget.showTemplates
                            ? 'Pick a template to start'
                            : 'Start from a template',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final template in DueTemplate.all)
                            ActionChip(
                              avatar: Icon(
                                categoryIcon(template.category),
                                size: 16,
                              ),
                              label: Text(template.title),
                              tooltip: template.frequency.label,
                              onPressed: () async {
                                if (title.text.trim().isNotEmpty &&
                                    !await confirmAction(
                                      context,
                                      'Apply this template?',
                                      'This replaces the title, description, category, frequency and priority. Your dates, assignee and attachments stay the same.',
                                      confirm: 'Apply template',
                                    )) {
                                  return;
                                }
                                if (mounted) applyTemplate(template);
                              },
                            ),
                        ],
                      ),
                    ],
                    const _FormSection('Basics'),
                    GlassTextField(
                      controller: title,
                      label: 'Title',
                      required: true,
                    ),
                    GlassTextField(
                      controller: description,
                      label: 'Description',
                      maxLines: 2,
                    ),
                    _FieldPair(
                      GlassDropdown<String>(
                        label: 'Category',
                        value: category,
                        required: true,
                        options: {
                          for (final c
                              in ref
                                  .watch(categoriesProvider)
                                  .where((c) => c.active || c.id == category))
                            c.id: c.name,
                        },
                        onChanged: (v) => setState(() => category = v),
                      ),
                      GlassDropdown<String>(
                        label: 'Assign to',
                        required: true,
                        value: assignee,
                        options: {
                          for (final u
                              in ref
                                  .watch(teamProvider)
                                  .where((u) => u.roleIn(org.id) != null))
                            u.id: u.name,
                        },
                        onChanged: (v) => setState(() => assignee = v),
                      ),
                    ),
                    const _FormSection('Schedule'),
                    _FieldPair(
                      DateField(
                        label: 'Due date *',
                        value: due,
                        onChanged: (v) => setState(() => due = v),
                      ),
                      DateField(
                        label: 'Start date',
                        value: start,
                        onChanged: (v) => setState(() => start = v),
                        onClear: () => setState(() => start = null),
                      ),
                      gap: 12,
                    ),
                    const SizedBox(height: 12),
                    GlassDropdown<Frequency>(
                      label: 'Frequency',
                      value: frequency,
                      options: {for (final f in Frequency.values) f: f.label},
                      onChanged: (v) => setState(() => frequency = v!),
                    ),
                    if (frequency == Frequency.custom)
                      GlassTextField(
                        controller: custom,
                        label: 'Repeat every (days)',
                        keyboardType: TextInputType.number,
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                            ? 'Enter a positive number of days.'
                            : null,
                      ),
                    Text(
                      'Priority',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in Priority.values)
                          ChoiceChip(
                            showCheckmark: false,
                            label: Text(p.label),
                            selected: priority == p,
                            onSelected: (_) => setState(() => priority = p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const _FormSection('Reminders'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in [30, 15, 7, 3, 1, 0])
                          FilterChip(
                            label: Text(
                              d == 0
                                  ? 'On due date'
                                  : '$d ${d == 1 ? 'day' : 'days'} before',
                            ),
                            selected: reminders.contains(d),
                            onSelected: (v) => setState(
                              () => v ? reminders.add(d) : reminders.remove(d),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        initiallyExpanded:
                            reference.text.isNotEmpty ||
                            authority.text.isNotEmpty ||
                            amount.text.isNotEmpty ||
                            notes.text.isNotEmpty,
                        title: Text(
                          'More details',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        subtitle: const Text(
                          'Reference, authority, amount and notes',
                          style: TextStyle(fontSize: 12),
                        ),
                        children: [
                          _FieldPair(
                            GlassTextField(
                              controller: reference,
                              label: 'Reference number',
                            ),
                            GlassTextField(
                              controller: authority,
                              label: 'Authority',
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: GlassTextField(
                                  controller: amount,
                                  label: 'Amount',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return null;
                                    final value = double.tryParse(v);
                                    return value == null ||
                                            !value.isFinite ||
                                            value < 0
                                        ? 'Enter a valid positive amount.'
                                        : null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: GlassDropdown<String>(
                                  label: 'Currency',
                                  value: currency,
                                  options: const {
                                    'INR': 'INR',
                                    'USD': 'USD',
                                    'GBP': 'GBP',
                                    'EUR': 'EUR',
                                  },
                                  onChanged: (v) =>
                                      setState(() => currency = v!),
                                ),
                              ),
                            ],
                          ),
                          GlassTextField(
                            controller: notes,
                            label: 'Notes',
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const _FormSection('Documents'),
                    for (final f in files)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(f.name),
                        subtitle: Text(
                          '${(f.size / 1024).toStringAsFixed(1)} KB',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove selection',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => files.remove(f)),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: pick,
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: const Text('Attach documents'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDF, images, Word, or text · up to 20 MB each',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: original == null
                          ? 'Create Due Item'
                          : 'Save changes',
                      loading: busy,
                      onPressed: save,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A plain heading between groups of fields; no card around the group.
class _FormSection extends StatelessWidget {
  final String title;
  const _FormSection(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Two fields side by side on wide screens, stacked on phones.
class _FieldPair extends StatelessWidget {
  final Widget first, second;
  final double gap;
  const _FieldPair(this.first, this.second, {this.gap = 0});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= 520
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          )
        : Column(
            children: [
              first,
              SizedBox(height: gap),
              second,
            ],
          ),
  );
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onClear;
  final DateTime? lastDate;
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onClear,
    this.lastDate,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
    onTap: () async {
      final initial = value ?? DateTime.now();
      final selected = await showDatePicker(
        context: context,
        initialDate: lastDate != null && initial.isAfter(lastDate!)
            ? lastDate
            : initial,
        firstDate: DateTime(2000),
        lastDate: lastDate ?? DateTime(2100),
      );
      if (selected != null) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: onClear != null && value != null
            ? IconButton(
                tooltip: 'Clear date',
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 18),
              )
            : const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(
        value == null ? 'Select date' : DueDates.format(value!, year: true),
      ),
    ),
  );
}
