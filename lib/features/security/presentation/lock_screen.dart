import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/illustrations.dart';

/// Six dots that fill as digits are entered and shake on a wrong passcode.
class PasscodeDots extends StatelessWidget {
  final int filled;
  final Animation<double> shake;
  const PasscodeDots({super.key, required this.filled, required this.shake});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: shake,
      builder: (context, child) => Transform.translate(
        offset: Offset(12 * (1 - shake.value) * _wave(shake.value), 0),
        child: child,
      ),
      child: Semantics(
        label: '$filled of ${AppLockController.passcodeLength} digits entered',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < AppLockController.passcodeLength; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i < filled ? scheme.primary : Colors.transparent,
                  border: Border.all(
                    color: i < filled ? scheme.primary : scheme.outline,
                    width: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double _wave(double t) {
    final phase = (t * 4) % 1;
    return phase < .5 ? phase * 4 - 1 : 3 - phase * 4;
  }
}

/// A plain number pad: squared keys with a hairline border.
class PasscodeKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final Widget? extra;
  final bool enabled;
  const PasscodeKeypad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.extra,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String digit) => _Key(
      label: digit,
      onTap: enabled ? () => onDigit(digit) : null,
      color: scheme.surfaceContainerLowest,
      border: scheme.outlineVariant,
      child: Text(
        digit,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
      ),
    );
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: key(d),
                  ),
              ],
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(width: 84, height: 60, child: extra),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: key('0'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _Key(
                label: 'Delete',
                onTap: enabled ? onDelete : null,
                child: Icon(
                  Icons.backspace_outlined,
                  color: scheme.onSurface,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final Color? color, border;
  const _Key({
    required this.label,
    required this.onTap,
    required this.child,
    this.color,
    this.border,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: Ink(
        width: 84,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          color: color,
          border: border == null ? null : Border.all(color: border!),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          onTap: onTap == null
              ? null
              : () {
                  DueHaptics.light();
                  onTap!();
                },
          child: Center(child: child),
        ),
      ),
    ),
  );
}

/// Shared entry logic: collects digits, then hands a full passcode over.
mixin PasscodeEntry<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  String entered = '';
  bool checking = false;
  late final shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  Future<void> complete(String passcode);

  void digit(String d) {
    if (checking || entered.length >= AppLockController.passcodeLength) return;
    setState(() => entered += d);
    if (entered.length == AppLockController.passcodeLength) {
      final passcode = entered;
      checking = true;
      unawaited(
        complete(passcode).whenComplete(() {
          if (mounted) setState(() => checking = false);
        }),
      );
    }
  }

  void delete() {
    if (checking || entered.isEmpty) return;
    setState(() => entered = entered.substring(0, entered.length - 1));
  }

  void reject() {
    DueHaptics.warning();
    shake.forward(from: 0);
    setState(() => entered = '');
  }

  /// Hardware keyboards and the simulator can type digits too.
  KeyEventResult onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final char = event.character;
    if (char != null && RegExp(r'^\d$').hasMatch(char)) {
      digit(char);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      delete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }
}

/// Covers the whole app until the passcode or Face ID / Touch ID is given.
/// It sits above the navigator, so it uses no tooltips or overlays.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin, PasscodeEntry {
  String? message;
  Timer? _ticker;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final until = ref.read(appLockProvider).blockedUntil;
      if (until != null && mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    final lock = ref.read(appLockProvider);
    if (!lock.biometrics) return;
    final available = await ref.read(biometricAuthProvider).available();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) {
      await ref.read(appLockProvider.notifier).unlockWithBiometrics();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Future<void> complete(String passcode) async {
    final result = await ref.read(appLockProvider.notifier).unlock(passcode);
    if (!mounted) return;
    switch (result) {
      case UnlockResult.unlocked:
        DueHaptics.confirm();
        setState(() => message = null);
      case UnlockResult.signedOut:
        setState(() => message = null);
      case UnlockResult.blocked:
        reject();
      case UnlockResult.wrong:
        reject();
        final left =
            AppLockController.maxAttempts - ref.read(appLockProvider).failures;
        setState(
          () => message = left <= 3
              ? 'Wrong passcode. $left ${left == 1 ? 'attempt' : 'attempts'} left before you are signed out.'
              : 'Wrong passcode. Try again.',
        );
    }
  }

  Future<void> _forgot() async {
    await ref.read(appLockProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider);
    final until = lock.blockedUntil;
    final wait = until?.difference(DateTime.now());
    final blocked = wait != null && wait > Duration.zero;
    return Focus(
      autofocus: true,
      onKeyEvent: onKey,
      child: DueDeskBackground(
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            const SizedBox(height: 12),
                            const DeskIllustration(
                              kind: DeskArt.security,
                              size: 110,
                            ),
                            const SizedBox(height: 16),
                            Semantics(
                              header: true,
                              child: Text(
                                'DueDesk is locked',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user.name.isEmpty
                                  ? 'Enter your passcode'
                                  : 'Enter the passcode for ${user.name.split(' ').first}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 26),
                            PasscodeDots(filled: entered.length, shake: shake),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 40,
                              child: Text(
                                blocked
                                    ? 'Too many attempts. Try again in ${describeWait(wait)}.'
                                    : message ?? '',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        PasscodeKeypad(
                          enabled: !blocked && !checking,
                          onDigit: digit,
                          onDelete: delete,
                          extra: lock.biometrics && _biometricAvailable
                              ? Semantics(
                                  button: true,
                                  label: 'Unlock with Face ID or Touch ID',
                                  excludeSemantics: true,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      AppSizes.radiusLg,
                                    ),
                                    onTap: () => ref
                                        .read(appLockProvider.notifier)
                                        .unlockWithBiometrics(),
                                    child: Icon(
                                      Icons.face_retouching_natural_rounded,
                                      size: 30,
                                      color: scheme.primary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _forgot,
                          child: const Text('Forgot passcode? Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Choose, then confirm, a new six-digit passcode.
class PasscodeSetupScreen extends ConsumerStatefulWidget {
  const PasscodeSetupScreen({super.key});
  @override
  ConsumerState<PasscodeSetupScreen> createState() => _SetupState();
}

class _SetupState extends ConsumerState<PasscodeSetupScreen>
    with SingleTickerProviderStateMixin, PasscodeEntry {
  String? first;
  String? message;

  static bool weak(String code) =>
      RegExp(r'^(\d)\1+$').hasMatch(code) ||
      '0123456789'.contains(code) ||
      '9876543210'.contains(code);

  @override
  Future<void> complete(String passcode) async {
    if (first == null) {
      if (weak(passcode)) {
        reject();
        setState(() => message = 'Choose a passcode that is harder to guess.');
        return;
      }
      setState(() {
        first = passcode;
        entered = '';
        message = null;
      });
      return;
    }
    if (passcode != first) {
      reject();
      setState(() {
        first = null;
        message = 'Passcodes did not match. Start again.';
      });
      return;
    }
    await ref.read(appLockProvider.notifier).setPasscode(passcode);
    if (!mounted) return;
    DueHaptics.confirm();
    feedback(context, 'App lock is on');
    context.canPop() ? context.pop(true) : context.go('/settings/security');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DueDeskScaffold(
      title: 'Set passcode',
      child: Focus(
        autofocus: true,
        onKeyEvent: onKey,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const DeskIllustration(
                          kind: DeskArt.security,
                          size: 96,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          first == null
                              ? 'Enter a new passcode'
                              : 'Confirm your passcode',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Six digits, asked for when DueDesk opens.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 26),
                        PasscodeDots(filled: entered.length, shake: shake),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 36,
                          child: Text(
                            message ?? '',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    PasscodeKeypad(
                      enabled: !checking,
                      onDigit: digit,
                      onDelete: delete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
