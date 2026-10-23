import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/security/secure_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/permissions.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/illustrations.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/due_widgets.dart';
import '../../due_items/presentation/due_detail_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return WorkspaceBody(
      child: PageBody(
        children: [
          const ScreenHeading(
            title: 'Your workspace',
            subtitle: 'A place for the details that matter.',
          ),
          GlassCard(
            onTap: () => context.push('/profile'),
            child: Row(
              children: [
                UserAvatar(name: user.name, image: user.avatarUrl, radius: 27),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        user.email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SectionHeader(title: 'Organisation'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _Entry('Company', Icons.business_outlined, '/company'),
                _Entry('Team', Icons.people_outline_rounded, '/team'),
                _Entry('Categories', Icons.category_outlined, '/categories'),
                _Entry('Activity', Icons.history_rounded, '/activity'),
              ],
            ),
          ),
          const SectionHeader(title: 'Preferences'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _Entry('Profile', Icons.person_outline_rounded, '/profile'),
                _Entry(
                  'Notification settings',
                  Icons.notifications_none_rounded,
                  '/settings/notifications',
                ),
                _Entry(
                  'Appearance',
                  Icons.palette_outlined,
                  '/settings/appearance',
                ),
                _Entry(
                  'Security',
                  Icons.lock_outline_rounded,
                  '/settings/security',
                ),
                _Entry('Storage', Icons.storage_rounded, '/settings/storage'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _Entry('About DueDesk', Icons.info_outline_rounded, '/about'),
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Sign out',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    if (await confirmAction(
                          context,
                          'Sign out?',
                          ref.read(storageProvider).isDevice
                              ? 'Your data and history stay saved on this device.'
                              : 'Your data stays on your server. Sign in again to see it.',
                          confirm: 'Sign out',
                        ) &&
                        context.mounted) {
                      await runAction(
                        context,
                        () => ref.read(authProvider.notifier).logout(),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'DueDesk 1.0.0\nNever miss what is due.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final String label, path;
  final IconData icon;
  const _Entry(this.label, this.icon, this.path);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: IllustratedIcon(icon: icon, size: 38),
    title: Text(
      label,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: AppSizes.iconMd),
    onTap: () => context.push(path),
  );
}

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeProvider);
    return DueDeskScaffold(
      title: 'Appearance',
      child: PageBody(
        children: [
          const Text('A clear view, in any light.'),
          const SizedBox(height: 24),
          for (final mode in ThemeMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GlassCard(
                onTap: () => ref.read(themeProvider.notifier).set(mode),
                child: Row(
                  children: [
                    Icon(
                      mode == ThemeMode.dark
                          ? Icons.dark_mode_outlined
                          : mode == ThemeMode.light
                          ? Icons.light_mode_outlined
                          : Icons.brightness_auto_outlined,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${mode.name[0].toUpperCase()}${mode.name.substring(1)}',
                      ),
                    ),
                    if (mode == selected)
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ),
          const SectionHeader(title: 'Preview'),
          const GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clarity looks good on you.',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                Text(
                  'Readable surfaces. Calm accents. Your deadlines, in focus.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return DueDeskScaffold(
      title: 'Notification settings',
      child: PageBody(
        children: [
          if (ref.watch(storageProvider).isDevice)
            const GlassCard(
              child: Text(
                'Preferences are saved on this device. With device storage, reminders arrive in the in-app inbox; push and email need a DueDesk server.',
              ),
            ),
          const SectionHeader(title: 'Keep me informed'),
          GlassCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (final (key, label, description) in [
                  (
                    'banner',
                    'Live notification bar',
                    'New reminders slide in at the top while you work',
                  ),
                  ('push', 'Push notifications', 'Alerts on your device'),
                  ('email', 'Email reminders', 'A reminder in your inbox'),
                  (
                    'assignment',
                    'Assignment notifications',
                    'When ownership changes',
                  ),
                  (
                    'overdue',
                    'Overdue alerts',
                    'When deadlines need attention',
                  ),
                  (
                    'completion',
                    'Completion notifications',
                    'When obligations are completed',
                  ),
                ])
                  SwitchListTile(
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      description,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: settings[key]!,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).toggle(key, v),
                  ),
              ],
            ),
          ),
          const SectionHeader(title: 'Default reminder timing'),
          GlassCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in [30, 15, 7, 3, 1, 0])
                  FilterChip(
                    label: Text(day == 0 ? 'On due date' : '$day days before'),
                    selected: settings['reminder$day']!,
                    onSelected: (v) => ref
                        .read(settingsProvider.notifier)
                        .toggle('reminder$day', v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Used for newly created DueItems. Existing reminder schedules stay with each obligation.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricAuthProvider).available(),
);

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override
  ConsumerState<SecurityScreen> createState() => _SecurityState();
}

class _SecurityState extends ConsumerState<SecurityScreen> {
  bool busy = false;
  bool get device => ref.read(storageProvider).isDevice;

  static String timeoutLabel(Duration d) =>
      d == Duration.zero ? 'Immediately' : '${d.inMinutes} min';

  Future<void> toggleLock(bool on) async {
    final notifier = ref.read(appLockProvider.notifier);
    if (on) {
      await context.push('/settings/security/passcode');
      return;
    }
    if (await confirmAction(
          context,
          'Turn off app lock?',
          'Anyone with this unlocked device will be able to open your workspace.',
          confirm: 'Turn off',
        ) &&
        mounted) {
      await runAction(context, notifier.disable, success: 'App lock is off');
    }
  }

  Future<void> toggleBiometrics(bool on) async {
    final notifier = ref.read(appLockProvider.notifier);
    if (!on) {
      await notifier.setBiometrics(false);
      return;
    }
    // Confirm it works before relying on it.
    final ok = await ref
        .read(biometricAuthProvider)
        .authenticate('Use Face ID or Touch ID to unlock DueDesk');
    if (!mounted) return;
    if (ok) {
      await notifier.setBiometrics(true);
      if (mounted) feedback(context, 'Face ID / Touch ID unlock is on');
    } else {
      feedback(context, 'Face ID / Touch ID was not confirmed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final biometrics = ref.watch(biometricsAvailableProvider).value ?? false;
    final scheme = Theme.of(context).colorScheme;
    final checks = [
      (lock.enabled, 'App lock'),
      (lock.enabled && lock.biometrics, 'Face ID / Touch ID'),
      (lock.privacyShield, 'App switcher privacy'),
      (true, device ? 'Encrypted on this device' : 'Encrypted offline copy'),
      (true, device ? 'Salted password hashes' : 'Keychain-held session'),
    ];
    final score = checks.where((c) => c.$1).length;
    return DueDeskScaffold(
      title: 'Security',
      child: PageBody(
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DeskIllustration(kind: DeskArt.security, size: 72),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            score >= 4 ? 'Well protected' : 'Add another layer',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '$score of ${checks.length} protections on',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (on, label) in checks)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (on ? AppColors.success : scheme.outline)
                              .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusSm,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              on
                                  ? Icons.check_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 14,
                              color: on
                                  ? AppColors.success
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(label, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'App lock'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.pin_outlined),
                  title: const Text(
                    'Require passcode',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'A six-digit code whenever DueDesk opens',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: lock.enabled,
                  onChanged: lock.ready ? toggleLock : null,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.face_retouching_natural_rounded),
                  title: const Text(
                    'Unlock with Face ID / Touch ID',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    biometrics
                        ? 'Your passcode is still the fallback'
                        : 'Not set up on this device',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: lock.enabled && lock.biometrics,
                  onChanged: lock.enabled && biometrics
                      ? toggleBiometrics
                      : null,
                ),
                if (lock.enabled) ...[
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text(
                      'Require after leaving the app',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in AppLockController.timeouts)
                            ChoiceChip(
                              label: Text(timeoutLabel(t)),
                              selected: lock.timeout == t,
                              onSelected: (_) => ref
                                  .read(appLockProvider.notifier)
                                  .setTimeout(t),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text(
                      'Change passcode',
                      style: TextStyle(fontSize: 14),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: AppSizes.iconMd,
                    ),
                    onTap: () => context.push('/settings/security/passcode'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_clock_outlined),
                    title: const Text(
                      'Lock now',
                      style: TextStyle(fontSize: 14),
                    ),
                    onTap: () => ref.read(appLockProvider.notifier).lock(),
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'DueDesk also locks after 5 minutes without a touch. After 10 wrong passcodes you are signed out and need your password again.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SectionHeader(title: 'Privacy'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text(
                    'Hide content in the app switcher',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Covers the screen when you leave DueDesk',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: lock.privacyShield,
                  onChanged: (v) =>
                      ref.read(appLockProvider.notifier).setPrivacyShield(v),
                ),
                if (SecureScreen.supported)
                  SwitchListTile(
                    secondary: const Icon(Icons.screenshot_monitor_outlined),
                    title: const Text(
                      'Block screenshots',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Also blocks screen recording and app previews',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: lock.blockCapture,
                    onChanged: (v) =>
                        ref.read(appLockProvider.notifier).setBlockCapture(v),
                  ),
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: const Text(
                    'Encrypted storage',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    device
                        ? 'Records and evidence on this device are encrypted with AES-256. The key stays in the device’s secure keystore.'
                        : 'The offline copy of your server data is encrypted with AES-256. The key stays in the device’s secure keystore.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Sign-in'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device ? 'Device session' : 'Protected session',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  device
                      ? 'Your workspace and uploaded evidence are saved on this device. Passwords are stored only as salted hashes and never leave it.'
                      : 'Authentication tokens are kept in the device Keychain, available only on this device. Your organisation controls access through roles.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Repeated failed sign-ins are slowed down automatically.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Request password reset',
                  loading: busy,
                  onPressed: () async {
                    setState(() => busy = true);
                    await runAction(
                      context,
                      () => ref
                          .read(authRepositoryProvider)
                          .forgotPassword(ref.read(currentUserProvider).email),
                      success: device
                          ? 'Accounts on this device are not reset by email. Demo password: demo123'
                          : 'If your account is eligible, reset instructions will be sent.',
                    );
                    if (mounted) setState(() => busy = false);
                  },
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Your access'),
          GlassCard(
            child: Text(
              'Role: ${ref.watch(currentUserProvider).roleIn(ref.watch(organisationProvider).id)?.label ?? 'None'}\nOrganisation: ${ref.watch(organisationProvider).name}',
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organisationProvider);
    final events =
        ref
            .watch(workspaceProvider)
            .value
            ?.activities
            .where((e) => e.organisationId == org.id)
            .toList() ??
        [];
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return DueDeskScaffold(
      title: 'Activity & history',
      child: WorkspaceBody(
        child: PageBody(
          children: [
            if (!Permissions.manage(ref.watch(currentUserProvider), org.id))
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Activity for your assigned obligations.'),
              ),
            if (events.isEmpty)
              const EmptyState(
                title: 'A fresh start.',
                message: 'Your team’s activity will appear here.',
              ),
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  onTap: () => context.push('/due/${e.dueItemId}'),
                  child: ActivityTile(event: e),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => DueDeskScaffold(
    title: 'About DueDesk',
    child: PageBody(
      children: [
        const SizedBox(height: 24),
        const Center(child: BrandMark(size: 72)),
        const SizedBox(height: 24),
        Text(
          'DueDesk',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text('Never miss what is due.', textAlign: TextAlign.center),
        const SizedBox(height: 32),
        const GlassCard(
          child: Text(
            'A focused home for business obligations. Track what is due, when it is due, who owns it, and the evidence behind it.\n\nCreate → Assign → Monitor → Act → Record → Complete → History',
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Version 1.0.0 · V1\n\nDueDesk records and organises obligations. Filing submissions, reminder delivery, and official acknowledgements remain with their respective services.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'DueDesk',
            applicationVersion: '1.0.0',
          ),
          child: const Text('Open-source licences'),
        ),
      ],
    ),
  );
}
