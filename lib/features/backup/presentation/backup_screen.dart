import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/illustrations.dart';
import '../../../shared/models/models.dart';
import '../application/backup_service.dart';
import '../domain/backup_codec.dart';
import '../domain/exports.dart';

/// Reports for accountants, a calendar file, and encrypted backups.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String? busy;

  String _stamp() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get _slug => ref.read(organisationProvider).slug;

  /// Builds and saves a file; returns whether it was saved.
  Future<bool> _export(
    String task,
    String fileName,
    Future<Uint8List> Function() build,
  ) async {
    setState(() => busy = task);
    var saved = false;
    await runAction(context, () async {
      saved = await ref
          .read(fileExporterProvider)
          .save(fileName, await build());
    });
    if (!mounted) return saved;
    setState(() => busy = null);
    if (saved) {
      DueHaptics.confirm();
      feedback(context, 'Saved $fileName');
    }
    return saved;
  }

  Future<bool> _report() => _export(
    'pdf',
    'DueDesk-$_slug-report-${_stamp()}.pdf',
    () async => Exports.pdf(
      items: ref.read(dueItemsProvider),
      organisation: ref.read(organisationProvider),
      today: ref.read(todayProvider),
      preparedBy: ref.read(currentUserProvider).name,
      bodyFont: await rootBundle.load('assets/fonts/Inter.ttf'),
      headingFont: await rootBundle.load('assets/fonts/NotoSerif-Medium.ttf'),
    ),
  );

  Future<bool> _csv() => _export(
    'csv',
    'DueDesk-$_slug-obligations-${_stamp()}.csv',
    () async => Uint8List.fromList(
      utf8.encode(
        // A byte-order mark lets Excel read ₹ and non-English text.
        '﻿${Exports.csv(ref.read(dueItemsProvider), ref.read(todayProvider))}',
      ),
    ),
  );

  Future<bool> _calendar() => _export(
    'ics',
    'DueDesk-$_slug-calendar.ics',
    () async => Uint8List.fromList(
      utf8.encode(
        Exports.ics(ref.read(dueItemsProvider), ref.read(organisationProvider)),
      ),
    ),
  );

  Future<void> _backup() async {
    final password = await _askPassword(context, confirm: true);
    if (password == null || !mounted) return;
    final service = ref.read(backupServiceProvider);
    final saved = await _export(
      'backup',
      'DueDesk-backup-${_stamp()}.${BackupCodec.extension}',
      () async => BackupCodec.create(await service.collect(), password),
    );
    if (saved) await service.markBackedUp();
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    final exporter = ref.read(fileExporterProvider);
    final service = ref.read(backupServiceProvider);
    final bytes = await exporter.pick();
    if (bytes == null || !mounted) return;
    final password = await _askPassword(context, confirm: false);
    if (password == null || !mounted) return;
    setState(() => busy = 'restore');
    BackupContents? contents;
    await runAction(
      context,
      () async => contents = await BackupCodec.open(bytes, password),
    );
    if (!mounted) return;
    setState(() => busy = null);
    final found = contents;
    if (found == null) return;
    final people = found.workspace.users.length;
    final items = found.workspace.items.length;
    if (!await confirmAction(
          context,
          'Replace everything on this device?',
          'This backup from ${DateFormat('d MMM yyyy, h:mm a').format(found.createdAt.toLocal())} has $items obligations, ${found.files.length} files and $people people. Everything currently on this device will be replaced, and you will sign in again.',
          confirm: 'Restore and sign out',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = 'restore');
    await runAction(
      context,
      () => service.restore(found),
      success: 'Backup restored. Sign in to continue.',
    );
    if (mounted) setState(() => busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(storageProvider).isDevice;
    final user = ref.watch(currentUserProvider);
    final org = ref.watch(organisationProvider);
    final owner = user.roleIn(org.id) == Role.owner;
    final last = ref.read(backupServiceProvider).lastBackup;
    final scheme = Theme.of(context).colorScheme;
    Widget tile(
      String task,
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) => ListTile(
      leading: IllustratedIcon(icon: icon, size: 38),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: busy == task
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right_rounded, size: AppSizes.iconMd),
      onTap: busy == null ? onTap : null,
    );
    return DueDeskScaffold(
      title: 'Backup & export',
      child: WorkspaceBody(
        child: PageBody(
          children: [
            GlassCard(
              child: Row(
                children: [
                  const DeskIllustration(kind: DeskArt.documents, size: 76),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Share a clean record with your accountant, put deadlines in your calendar, and keep an encrypted copy somewhere safe.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader(title: 'For your accountant'),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  tile(
                    'pdf',
                    Icons.picture_as_pdf_outlined,
                    'Compliance report (PDF)',
                    'Overdue, upcoming and completed obligations for ${org.name}',
                    _report,
                  ),
                  tile(
                    'csv',
                    Icons.table_chart_outlined,
                    'Obligations spreadsheet (CSV)',
                    'Opens in Excel, Numbers or Google Sheets',
                    _csv,
                  ),
                ],
              ),
            ),
            const SectionHeader(title: 'Your calendar'),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: tile(
                'ics',
                Icons.event_outlined,
                'Add deadlines to your calendar (.ics)',
                'Open the saved file in Google Calendar or Apple Calendar. Export again after changes.',
                _calendar,
              ),
            ),
            const SectionHeader(title: 'Encrypted backup'),
            if (!device)
              const GlassCard(
                child: Text(
                  'Your records live on your DueDesk server, which keeps its own backups. Ask your administrator about them.',
                ),
              )
            else if (!owner)
              const GlassCard(
                child: Text('An owner can back up and restore this device.'),
              )
            else ...[
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    tile(
                      'backup',
                      Icons.lock_outline_rounded,
                      'Create a backup',
                      last == null
                          ? 'Not backed up yet'
                          : 'Last backup ${DateFormat('d MMM yyyy, h:mm a').format(last)}',
                      _backup,
                    ),
                    tile(
                      'restore',
                      Icons.settings_backup_restore_rounded,
                      'Restore from a backup',
                      'Replaces everything on this device',
                      _restore,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(
                  'Backups hold every record, document and account on this device, encrypted with a password you choose. Save them to Files, iCloud Drive or Google Drive. Without the password a backup cannot be opened, so keep it somewhere safe.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for a backup password, twice when creating one.
Future<String?> _askPassword(BuildContext context, {required bool confirm}) =>
    glassSheet<String>(context, _PasswordSheet(confirm: confirm));

class _PasswordSheet extends StatefulWidget {
  final bool confirm;
  const _PasswordSheet({required this.confirm});
  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController(), again = TextEditingController();
  bool hidden = true;

  @override
  void dispose() {
    password.dispose();
    again.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.confirm
              ? 'Choose a backup password'
              : 'Enter the backup password',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          widget.confirm
              ? 'You will need it to restore. DueDesk cannot recover it.'
              : 'The password chosen when this backup was made.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        GlassTextField(
          controller: password,
          label: 'Backup password',
          obscure: hidden,
          validator: (v) => (v?.length ?? 0) < BackupCodec.minPasswordLength
              ? 'Use at least ${BackupCodec.minPasswordLength} characters.'
              : null,
          suffix: IconButton(
            tooltip: hidden ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => hidden = !hidden),
            icon: Icon(
              hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
          ),
        ),
        if (widget.confirm)
          GlassTextField(
            controller: again,
            label: 'Repeat password',
            obscure: hidden,
            validator: (v) =>
                v != password.text ? 'The passwords do not match.' : null,
          ),
        const SizedBox(height: 6),
        PrimaryButton(
          label: widget.confirm ? 'Create backup' : 'Open backup',
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, password.text);
            }
          },
        ),
      ],
    ),
  );
}
