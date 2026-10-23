import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/security/app_lock.dart';
import '../core/theme/app_theme.dart';
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
        ExcludeSemantics(
          excluding: locked || checking,
          child: TickerMode(enabled: !locked, child: child),
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

/// Frosts the screen while DueDesk is in the app switcher, so obligations
/// and evidence are not visible in the snapshot.
class PrivacyShield extends StatelessWidget {
  const PrivacyShield({super.key});
  @override
  Widget build(BuildContext context) {
    final glass = GlassTokens.of(context);
    return Semantics(
      label: 'DueDesk content hidden',
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: ColoredBox(
            color: glass.chrome,
            child: const Center(child: BrandMark(size: 64)),
          ),
        ),
      ),
    );
  }
}
