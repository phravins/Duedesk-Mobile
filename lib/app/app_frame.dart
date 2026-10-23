import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/security/app_lock.dart';
import '../core/widgets/illustrations.dart';
import '../core/widgets/glass.dart';
import '../features/notifications/presentation/live_banner.dart';
import '../features/security/presentation/lock_screen.dart';
import 'providers.dart';

/// Layers above every route: the live notification bar, the app lock and
/// the privacy shield shown in the app switcher.
class AppFrame extends ConsumerWidget {
  final Widget child;
  const AppFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final signedIn = ref.watch(authProvider).value != null;
    final locked = signedIn && lock.enabled && lock.locked;
    // Until the Keychain has been read, nothing of the workspace is shown.
    final checking = signedIn && !lock.ready;
    final obscured =
        signedIn && lock.privacyShield && ref.watch(appObscuredProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => ref.read(appLockProvider.notifier).activity(),
          child: ExcludeSemantics(
            excluding: locked || checking,
            child: TickerMode(enabled: !locked, child: child),
          ),
        ),
        if (signedIn) const LiveNotificationBanner(),
        if (locked)
          const LockScreen()
        else if (checking)
          const DueDeskBackground(child: SizedBox.expand()),
        if (obscured) const PrivacyShield(),
      ],
    );
  }
}

/// Covers the screen while DueDesk is in the app switcher, so obligations
/// and evidence never appear in the snapshot. It is fully opaque: a blur can
/// still reveal the shape of what is underneath.
class PrivacyShield extends StatelessWidget {
  const PrivacyShield({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'DueDesk content hidden',
    child: DueDeskBackground(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DeskIllustration(kind: DeskArt.security, size: 150),
            const SizedBox(height: 12),
            Text('DueDesk', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    ),
  );
}
