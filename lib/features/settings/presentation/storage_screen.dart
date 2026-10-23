import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/storage/storage_settings.dart';
import '../../../core/widgets/glass.dart';

String storageLabel(StorageSettings s) => s.isDevice
    ? 'This device'
    : (Uri.tryParse(s.serverUrl)?.host.isNotEmpty ?? false)
    ? Uri.parse(s.serverUrl).host
    : 'Self-hosted server';

IconData storageIcon(StorageMode mode) =>
    mode == StorageMode.device ? Icons.smartphone_rounded : Icons.dns_outlined;

/// Lets people choose between keeping data on this device's drive and
/// connecting to their own DueDesk server. Pops with `true` once switched.
class StorageSheet extends ConsumerStatefulWidget {
  const StorageSheet({super.key});
  @override
  ConsumerState<StorageSheet> createState() => _StorageSheetState();
}

class _StorageSheetState extends ConsumerState<StorageSheet> {
  final form = GlobalKey<FormState>();
  late final current = ref.read(storageProvider);
  late StorageMode mode = current.mode;
  late final url = TextEditingController(text: current.serverUrl);
  bool busy = false;

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (mode == StorageMode.server && !form.currentState!.validate()) return;
    final serverUrl = mode == StorageMode.server
        ? parseServerUrl(url.text).url!
        : null;
    final unchanged =
        mode == current.mode &&
        (mode == StorageMode.device || serverUrl == current.serverUrl);
    if (unchanged) {
      Navigator.pop(context, false);
      return;
    }
    if (ref.read(authProvider).value != null &&
        !await confirmAction(
          context,
          'Switch storage?',
          'You will be signed out. Nothing is copied or deleted: data already '
              'saved in ${storageLabel(current)} stays there.',
          confirm: 'Switch and sign out',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    final ok = await runAction(
      context,
      () => ref
          .read(authProvider.notifier)
          .switchStorage(mode, serverUrl: serverUrl),
      success: mode == StorageMode.device
          ? 'Saving to this device'
          : 'Connected to ${Uri.parse(serverUrl!).host}',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Where should DueDesk keep your data?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 14),
        _ModeOption(
          icon: storageIcon(StorageMode.device),
          title: 'This device',
          subtitle:
              'Saved as files on this device’s storage. Works offline, no server needed.',
          selected: mode == StorageMode.device,
          onTap: busy ? null : () => setState(() => mode = StorageMode.device),
        ),
        const SizedBox(height: 8),
        _ModeOption(
          icon: storageIcon(StorageMode.server),
          title: 'Self-hosted server',
          subtitle:
              'Your organisation’s own DueDesk server, shared with your team.',
          selected: mode == StorageMode.server,
          onTap: busy ? null : () => setState(() => mode = StorageMode.server),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: mode == StorageMode.server
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: GlassTextField(
                    controller: url,
                    label: 'Server address',
                    hint: 'https://due.example.com',
                    keyboardType: TextInputType.url,
                    validator: (v) => parseServerUrl(v ?? '').error,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: mode == StorageMode.device
              ? 'Use this device'
              : 'Connect to server',
          loading: busy,
          onPressed: save,
        ),
      ],
    ),
  );
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .08)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line summary of where data is kept, with a way to change it.
class StorageChip extends ConsumerWidget {
  const StorageChip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageProvider);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: () => glassSheet<bool>(context, const StorageSheet()),
        icon: Icon(storageIcon(storage.mode), size: 16),
        label: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Data on ',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              TextSpan(text: storageLabel(storage)),
              TextSpan(
                text: ' · Change',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageProvider);
    final store = ref.watch(localStoreProvider);
    final scheme = Theme.of(context).colorScheme;
    return DueDeskScaffold(
      title: 'Storage',
      child: PageBody(
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(storageIcon(storage.mode), color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        storage.isDevice
                            ? 'Stored on this device'
                            : 'Stored on your server',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _InfoRow(
                  storage.isDevice ? 'Folder' : 'Server',
                  storage.isDevice ? store.location : storage.serverUrl,
                  copyable: true,
                ),
                FutureBuilder<int>(
                  future: store.sizeInBytes(),
                  builder: (context, size) => _InfoRow(
                    storage.isDevice ? 'Size' : 'Offline copy',
                    size.hasData ? formatBytes(size.data!) : '…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            storage.isDevice
                ? 'Your records are kept in workspace.json and attachments in the files folder. Nothing is sent to a server. Back up this folder to keep a copy.'
                : 'Your records live on your server and are shared with your team. A copy is kept on this device so you can read it offline.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SecondaryButton(
            label: 'Change storage',
            icon: Icons.swap_horiz_rounded,
            onPressed: () => glassSheet<bool>(context, const StorageSheet()),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final bool copyable;
  const _InfoRow(this.label, this.value, {this.copyable = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        if (copyable)
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              feedback(context, 'Copied');
            },
            icon: const Icon(Icons.copy_rounded),
          ),
      ],
    ),
  );
}
