import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/config/environment.dart';
import '../../../core/widgets/glass.dart';
import '../../settings/presentation/storage_screen.dart';
import '../domain/auth_repository.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DueDeskScaffold(
    child: Center(
      child: ref.watch(authProvider).hasError
          ? ErrorState(
              error: ref.watch(authProvider).error!,
              onRetry: () => ref.invalidate(authProvider),
            )
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: .7, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.scale(scale: value, child: child),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DueDesk',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text('Never miss what is due.'),
                  SizedBox(height: 32),
                  SizedBox(width: 100, child: LinearProgressIndicator()),
                ],
              ),
            ),
    ),
  );
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<WelcomeScreen> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => DueDeskScaffold(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DueDesk',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 62),
              GlassCard(
                blur: true,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const Spacer(),
                        const Text(
                          'ALL UNDER CONTROL',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'A little clarity.\nA lot of peace of mind.',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 22),
                    for (final text in [
                      'Deadlines, in one place',
                      'Clear ownership, every time',
                      'Evidence that stays with the work',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 38),
              Text(
                'Never miss\nwhat is due.',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 38, height: 1.15),
              ),
              const SizedBox(height: 14),
              Text(
                'Your business obligations. Organised, assigned, and always one step ahead.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Log in',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => context.push('/login'),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Create an account',
                onPressed: () => context.push('/register'),
              ),
              if (AppConfig.isDemo && ref.watch(storageProvider).isDevice) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await runAction(
                            context,
                            () => ref.read(authProvider.notifier).demo(),
                          );
                          if (mounted) setState(() => busy = false);
                        },
                  child: Text(
                    busy ? 'Opening your workspace…' : 'Continue in demo mode',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const StorageChip(),
              const SizedBox(height: 4),
              Text(
                'Built for businesses that stay ahead.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Log in, sign up and password reset, laid out like the DueDesk web app.
class AuthFormScreen extends ConsumerStatefulWidget {
  final String mode;
  const AuthFormScreen({super.key, required this.mode});
  @override
  ConsumerState<AuthFormScreen> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthFormScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      mobile = TextEditingController(),
      password = TextEditingController();
  bool hidden = true, remember = false, busy = false, sent = false;

  bool get register => widget.mode == 'register';
  bool get forgot => widget.mode == 'forgot';

  @override
  void dispose() {
    for (final c in [name, email, mobile, password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    await runAction(context, () async {
      final auth = ref.read(authProvider.notifier);
      if (register) {
        await auth.register(
          name.text.trim(),
          email.text.trim(),
          password.text,
          normaliseIndianMobile(mobile.text)!,
        );
        TextInput.finishAutofillContext();
        if (mounted) context.go('/onboarding');
      } else if (forgot) {
        await ref
            .read(authRepositoryProvider)
            .forgotPassword(email.text.trim());
        if (mounted) setState(() => sent = true);
      } else {
        await auth.login(email.text.trim(), password.text, remember);
        TextInput.finishAutofillContext();
      }
    });
    if (mounted) setState(() => busy = false);
  }

  void backToLogin() => context.canPop() ? context.pop() : context.go('/login');

  @override
  Widget build(BuildContext context) {
    final (prompt, action, target) = register
        ? ('Already have an account?', 'Log in', '/login')
        : forgot
        ? ('Remembered it?', 'Log in', '/login')
        : ('New to DueDesk?', 'Sign up', '/register');
    return _AuthLayout(
      prompt: prompt,
      action: action,
      onAction: () => context.go(target),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: sent ? sentView() : formView(context),
      ),
    );
  }

  Widget sentView() => Column(
    key: const ValueKey('sent'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AuthHeading(
        title: 'Check your inbox.',
        tagline: 'Your link is on its way.',
        message: ref.read(storageProvider).isDevice
            ? 'Accounts saved on this device are not reset by email. Demo access: demo@duedesk.app and demo123.'
            : 'If that email is registered, you will receive password reset instructions shortly.',
      ),
      PrimaryButton(label: 'Back to log in', onPressed: backToLogin),
    ],
  );

  Widget formView(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _AuthLayout.wideWidth;
    final login = !register && !forgot;
    final storage = ref.watch(storageProvider);
    return Form(
      key: form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (register)
              const _AuthHeading(
                title: 'Never miss a renewal.',
                tagline: 'Create your DueDesk account.',
              )
            else if (forgot)
              const _AuthHeading(
                title: 'Forgot your password?',
                tagline: 'We’ll email you a link.',
                message:
                    'Enter the email you use for DueDesk and we will send you a link to choose a new one.',
              )
            else
              const _AuthHeading(
                title: 'Know what is due.',
                tagline: 'Log in to DueDesk.',
              ),
            if (!forgot)
              _DemoNote(
                storage.isDevice
                    ? register
                          ? 'Saved on this device · Your account stays on this device and no email is sent.'
                          : 'Saved on this device · Demo access: demo@duedesk.app and demo123.'
                    : '${register ? 'Creating an account on' : 'Logging in to'} ${storageLabel(storage)}.',
                icon: storageIcon(storage.mode),
              ),
            if (register)
              _AuthField(
                controller: name,
                label: 'Full name',
                hint: 'Asha Sharma',
                autofocus: wide,
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v?.trim().isEmpty ?? true)
                    ? 'Enter your full name.'
                    : null,
              ),
            _AuthField(
              controller: email,
              label: register ? 'Work email' : 'Email',
              hint: 'name@company.in',
              autofocus: wide && !register,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onSubmitted: forgot ? submit : null,
              validator: (v) =>
                  RegExp(
                    r'^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$',
                  ).hasMatch(v?.trim() ?? '')
                  ? null
                  : 'Enter a valid email address.',
            ),
            if (register)
              _AuthField(
                controller: mobile,
                label: 'Mobile number',
                hint: '98765 43210',
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
                ],
                validator: (v) => normaliseIndianMobile(v ?? '') == null
                    ? 'Enter a 10-digit Indian mobile number.'
                    : null,
              ),
            if (!forgot)
              _AuthField(
                controller: password,
                label: 'Password',
                hint: register ? 'At least 10 characters' : 'Enter password',
                obscure: hidden,
                autofillHints: [
                  register ? AutofillHints.newPassword : AutofillHints.password,
                ],
                onSubmitted: submit,
                suffix: IconButton(
                  tooltip: hidden ? 'Show password' : 'Hide password',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      key: ValueKey(hidden),
                    ),
                  ),
                ),
                validator: (v) {
                  final length = v?.length ?? 0;
                  if (!register) {
                    return length == 0 ? 'Enter your password.' : null;
                  }
                  if (length < 10) return 'Use at least 10 characters.';
                  if (length > 72) return 'Use 72 characters or fewer.';
                  return null;
                },
              ),
            if (register) _PasswordStrength(controller: password),
            if (login)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _RememberToggle(
                      value: remember,
                      onChanged: (v) => setState(() => remember = v),
                    ),
                    _LinkButton(
                      label: 'Forgot password?',
                      onPressed: () => context.push('/forgot-password'),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 6),
            PrimaryButton(
              label: register
                  ? 'Create account'
                  : forgot
                  ? 'Send reset link'
                  : 'Continue',
              onPressed: submit,
              loading: busy,
            ),
            if (!register) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: forgot ? 'Back to log in' : 'Create an account',
                onPressed: forgot ? backToLogin : () => context.go('/register'),
              ),
            ],
            if (!forgot)
              _LegalConsent(
                onDevice: storage.isDevice,
                action: register ? 'By creating an account' : 'By continuing',
              ),
          ],
        ),
      ),
    );
  }
}

/// Wordmark and account link on top, a narrow centred column below.
/// Phones get tighter gutters; wide windows get more air, as on the web.
class _AuthLayout extends StatelessWidget {
  static const wideWidth = 640.0;
  final String prompt, action;
  final VoidCallback onAction;
  final Widget child;
  const _AuthLayout({
    required this.prompt,
    required this.action,
    required this.onAction,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    // The primary action is ink-coloured on auth pages, matching the web app.
    final inkButtons = FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: .4),
        disabledForegroundColor: scheme.surface,
      ).merge(theme.filledButtonTheme.style),
    );
    return DueDeskBackground(
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= wideWidth;
              final gutter = wide ? 40.0 : 20.0;
              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: wide ? 80 : 64),
                      child: Row(
                        children: [
                          const _Wordmark(),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  prompt,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                _LinkButton(
                                  label: action,
                                  fontSize: 14,
                                  onPressed: onAction,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        wide ? 72 : 24,
                        gutter,
                        48,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: FilledButtonTheme(
                            data: inkButtons,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'DueDesk home',
    excludeSemantics: true,
    child: InkWell(
      onTap: () => context.go('/welcome'),
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Text(
          'DueDesk',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
      ),
    ),
  );
}

class _AuthHeading extends StatelessWidget {
  final String title, tagline;
  final String? message;
  const _AuthHeading({
    required this.title,
    required this.tagline,
    this.message,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$title\n'),
                  TextSpan(
                    text: tagline,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: .7),
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: -.44,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label above the input, with the example shown as placeholder text.
class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool obscure, autofocus;
  final Widget? suffix;
  final VoidCallback? onSubmitted;
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    this.keyboardType,
    this.autofillHints,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.autofocus = false,
    this.suffix,
    this.onSubmitted,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            enableSuggestions: !obscure,
            autocorrect: false,
            autofocus: autofocus,
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            textCapitalization: textCapitalization,
            textInputAction: onSubmitted == null
                ? TextInputAction.next
                : TextInputAction.done,
            onFieldSubmitted: onSubmitted == null
                ? null
                : (_) => onSubmitted!(),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: validator,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              suffixIcon: suffix,
            ),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ],
      ),
    ),
  );
}

/// 0–4: length, mixed case, digits and symbols each add strength.
int passwordStrength(String value) {
  if (value.length < 10) return value.isEmpty ? 0 : 1;
  var score = 1;
  if (value.length >= 14) score++;
  if (RegExp('[a-z]').hasMatch(value) && RegExp('[A-Z]').hasMatch(value)) {
    score++;
  }
  if (RegExp(r'\d').hasMatch(value)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
  return score.clamp(1, 4);
}

class _PasswordStrength extends StatelessWidget {
  final TextEditingController controller;
  const _PasswordStrength({required this.controller});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final score = passwordStrength(value.text);
      if (score == 0) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final (label, color) = switch (score) {
        1 => ('Too weak', scheme.error),
        2 => ('Fair', const Color(0xFFD97706)),
        3 => ('Good', const Color(0xFF2563EB)),
        _ => ('Strong', const Color(0xFF16A34A)),
      };
      return Padding(
        padding: const EdgeInsets.only(top: 0, bottom: 14),
        child: Semantics(
          label: 'Password strength: $label',
          excludeSemantics: true,
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < score ? color : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _RememberToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RememberToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Keep me logged in',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final double fontSize;
  const _LinkButton({
    required this.label,
    required this.onPressed,
    this.fontSize = 13,
  });
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );
}

class _DemoNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const _DemoNote(this.text, {this.icon = Icons.info_outline});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalConsent extends StatefulWidget {
  final String action;
  final bool onDevice;
  const _LegalConsent({required this.action, required this.onDevice});
  @override
  State<_LegalConsent> createState() => _LegalConsentState();
}

class _LegalConsentState extends State<_LegalConsent> {
  late final terms = TapGestureRecognizer()
    ..onTap = () => show(
      'Terms of service',
      widget.onDevice
          ? 'With device storage, DueDesk keeps sample and entered data on this device. It does not submit filings, send reminders or invitations, or provide legal or tax advice. Use non-sensitive test information.'
          : 'The DueDesk terms of service are supplied by your service operator.',
    );
  late final privacy = TapGestureRecognizer()
    ..onTap = () => show(
      'Privacy policy',
      widget.onDevice
          ? 'With device storage, everything you enter stays on this device and is never sent to a server.'
          : 'The DueDesk privacy policy is supplied by your service operator.',
    );

  @override
  void dispose() {
    terms.dispose();
    privacy.dispose();
    super.dispose();
  }

  void show(String title, String body) => glassSheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        Text(body),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final link = TextStyle(
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
      decoration: TextDecoration.underline,
      decorationColor: scheme.onSurface.withValues(alpha: .4),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${widget.action}, you agree to the DueDesk '),
            TextSpan(text: 'terms of service', recognizer: terms, style: link),
            const TextSpan(text: ' and '),
            TextSpan(text: 'privacy policy', recognizer: privacy, style: link),
            const TextSpan(text: '.'),
          ],
        ),
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
