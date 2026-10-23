import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';
import '../../app/providers.dart';
import '../errors/failures.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import 'illustrations.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Also blur what is behind the card. Cards inside long lists leave this
  /// off: the translucent fill over the ambient backdrop already reads as
  /// glass, and scrolling stays smooth.
  final bool blur;
  final VoidCallback? onTap;
  final Color? tint;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = AppSizes.radiusLg,
    this.blur = false,
    this.onTap,
    this.tint,
  });
  @override
  Widget build(BuildContext context) {
    final glass = GlassTokens.of(context);
    final shape = BorderRadius.circular(radius);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        gradient: tint == null ? glass.sheen() : null,
        borderRadius: shape,
        border: Border.all(color: glass.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (blur) {
      surface = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
          child: surface,
        ),
      );
    }
    // No drop shadow: it would show through the translucent fill. The bright
    // hairline edge separates the card from the backdrop instead.
    return surface;
  }
}

/// Frosted chrome: blurs whatever scrolls behind it. Used for the tab bar,
/// the navigation rail, banners and sheets.
class FrostedPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color? color;
  final bool shadow;
  const FrostedPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.color,
    this.shadow = true,
  });
  @override
  Widget build(BuildContext context) {
    final glass = GlassTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow ? glass.shadows : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? glass.chrome,
              borderRadius: borderRadius,
              border: Border.all(color: glass.border),
            ),
            // Ink from list tiles and buttons paints on the glass itself.
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// A soft, static colour field behind every page so translucent surfaces
/// have something to frost. Painted once and cached by a repaint boundary.
class DueDeskBackground extends StatelessWidget {
  final Widget child;
  const DueDeskBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(painter: _AmbientPainter(GlassTokens.of(context))),
        ),
      ),
      child,
    ],
  );
}

class _AmbientPainter extends CustomPainter {
  final GlassTokens glass;
  const _AmbientPainter(this.glass);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = glass.base);
    final span = size.shortestSide;
    final spots = [
      (Offset(size.width * .05, size.height * .02), span * .95),
      (Offset(size.width * 1.0, size.height * .32), span * .85),
      (Offset(size.width * .2, size.height * .95), span * .9),
    ];
    for (final (i, (center, radius)) in spots.indexed) {
      final color = glass.glows[i % glass.glows.length];
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.glass != glass;
}

class DueDeskScaffold extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool back;
  const DueDeskScaffold({
    super.key,
    this.title,
    required this.child,
    this.actions,
    this.bottom,
    this.back = true,
  });
  @override
  Widget build(BuildContext context) => DueDeskBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              automaticallyImplyLeading: back,
              flexibleSpace: FrostedPanel(
                shadow: false,
                color: GlassTokens.of(context).fill,
                child: const SizedBox.expand(),
              ),
              leading: back
                  ? IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      iconSize: AppSizes.iconMd,
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/home'),
                    )
                  : null,
              actions: actions,
            ),
      body: SafeArea(
        top: title == null,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: bottom,
    ),
  );
}

/// Phones keep the bottom bar in every orientation; only tablets and
/// desktops get the side rail.
bool useNavigationRail(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.shortestSide >= AppSizes.railBreakpoint &&
      size.width >= AppSizes.railBreakpoint;
}

class GlassBottomNavigation extends StatelessWidget {
  final String location;
  const GlassBottomNavigation({super.key, required this.location});
  static const entries = [
    (
      '/home',
      'Home',
      Icons.space_dashboard_outlined,
      Icons.space_dashboard_rounded,
    ),
    ('/due', 'Due', Icons.task_alt_rounded, Icons.check_circle_rounded),
    (
      '/calendar',
      'Calendar',
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
    ),
    ('/documents', 'Docs', Icons.folder_outlined, Icons.folder_rounded),
    ('/more', 'More', Icons.grid_view_outlined, Icons.grid_view_rounded),
  ];
  static int indexOf(String location) =>
      entries.indexWhere((e) => location.startsWith(e.$1)).clamp(0, 4);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = entries.indexWhere((e) => location.startsWith(e.$1));
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // A floating, frosted tab bar in the iOS style; pages scroll beneath it.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        bottomInset > 0 ? bottomInset : 12,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FrostedPanel(
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  for (final (i, (path, label, icon, activeIcon))
                      in entries.indexed)
                    Expanded(
                      child: Semantics(
                        selected: i == selected,
                        button: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () {
                            if (i != selected) DueHaptics.selection();
                            context.go(path);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: i == selected
                                  ? scheme.primary.withValues(alpha: .13)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedScale(
                                  scale: i == selected ? 1.08 : 1,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    i == selected ? activeIcon : icon,
                                    size: AppSizes.iconMd + 2,
                                    color: i == selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: i == selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline =
        ref
            .watch(connectivityProvider)
            .value
            ?.contains(ConnectivityResult.none) ??
        false;
    final rail = useNavigationRail(context);
    final scheme = Theme.of(context).colorScheme;
    return DueDeskBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Content runs under the floating tab bar; scroll views add the
        // bar's height to their bottom padding.
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: offline
                    ? Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusMd,
                          ),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: .35),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: AppSizes.iconXs,
                              color: scheme.onSurface,
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                "You're offline. Showing the latest available data.",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              Expanded(
                child: !rail
                    ? child
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final extended =
                              constraints.maxWidth >=
                              AppSizes.extendedRailBreakpoint;
                          return Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  0,
                                  12,
                                ),
                                child: FrostedPanel(
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusXl,
                                  ),
                                  child: NavigationRail(
                                    extended: extended,
                                    minExtendedWidth: 220,
                                    groupAlignment: -1,
                                    indicatorColor: scheme.primary.withValues(
                                      alpha: .14,
                                    ),
                                    selectedIconTheme: IconThemeData(
                                      color: scheme.primary,
                                    ),
                                    leading: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        12,
                                        0,
                                        20,
                                      ),
                                      child: extended
                                          ? Row(
                                              children: [
                                                const BrandMark(size: 32),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'DueDesk',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleLarge,
                                                ),
                                              ],
                                            )
                                          : const BrandMark(size: 32),
                                    ),
                                    labelType: extended
                                        ? NavigationRailLabelType.none
                                        : NavigationRailLabelType.all,
                                    selectedIndex:
                                        GlassBottomNavigation.indexOf(location),
                                    onDestinationSelected: (i) => context.go(
                                      GlassBottomNavigation.entries[i].$1,
                                    ),
                                    destinations: [
                                      for (final e
                                          in GlassBottomNavigation.entries)
                                        NavigationRailDestination(
                                          icon: Icon(e.$3),
                                          selectedIcon: Icon(e.$4),
                                          label: Text(e.$2),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(child: child),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: rail
            ? null
            : GlassBottomNavigation(location: location),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'DueDesk',
    image: true,
    child: SvgPicture.asset(
      'assets/branding/duedesk_mark.svg',
      height: size,
      width: size,
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: loading ? null : onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: Builder(
              builder: (context) => CircularProgressIndicator(
                strokeWidth: 2,
                color: IconTheme.of(context).color,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: AppSizes.iconMd),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: loading ? null : onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: AppSizes.iconMd),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool required, obscure;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;
  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.required = false,
    this.obscure = false,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: '$label${required ? ' *' : ''}',
        hintText: hint,
        suffixIcon: suffix,
      ),
      validator:
          validator ??
          (required
              ? (value) => value == null || value.trim().isEmpty
                    ? 'Enter ${label.toLowerCase()}.'
                    : null
              : null),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    ),
  );
}

class GlassDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final Map<T, String> options;
  final ValueChanged<T?>? onChanged;
  final bool required;
  const GlassDropdown({
    super.key,
    required this.label,
    required this.options,
    this.value,
    this.onChanged,
    this.required = false,
  });
  String get fieldLabel => '$label${required ? ' *' : ''}';
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FormField<T>(
      key: ValueKey('$label-$value-${options.length}'),
      initialValue: options.containsKey(value) ? value : null,
      validator: required
          ? (v) => v == null ? 'Select ${label.toLowerCase()}.' : null
          : null,
      builder: (field) {
        final selected = options.containsKey(field.value)
            ? options[field.value]
            : null;
        final enabled = onChanged != null;
        return Semantics(
          button: true,
          enabled: enabled,
          label: fieldLabel,
          value: selected,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            onTap: enabled
                ? () async {
                    final choice = await _choose(context, field.value);
                    if (choice == null) return;
                    field.didChange(choice.$1);
                    onChanged!(choice.$1);
                  }
                : null,
            child: InputDecorator(
              isEmpty: selected == null,
              decoration: InputDecoration(
                labelText: fieldLabel,
                enabled: enabled,
                errorText: field.errorText,
                suffixIcon: const Icon(Icons.unfold_more_rounded, size: 20),
              ),
              child: Text(
                selected ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    ),
  );

  /// Phones get a bottom sheet that is easy to reach with a thumb; wider
  /// screens get a menu anchored under the field. A record wraps the result
  /// so choosing a `null` option ("Any status") differs from dismissing.
  Future<(T,)?> _choose(BuildContext context, T? current) {
    final box = context.findRenderObject() as RenderBox?;
    if (MediaQuery.sizeOf(context).width >= AppSizes.railBreakpoint &&
        box != null &&
        box.hasSize) {
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()
              as RenderBox;
      final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      return showMenu<(T,)>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(rect.left, rect.bottom + 4, rect.width, 0),
          Offset.zero & overlay.size,
        ),
        constraints: BoxConstraints(
          minWidth: rect.width,
          maxWidth: rect.width,
          maxHeight: 360,
        ),
        items: [
          for (final e in options.entries)
            PopupMenuItem(
              value: (e.key,),
              height: 42,
              child: _PickerRow(label: e.value, selected: e.key == current),
            ),
        ],
      );
    }
    return glassSheet<(T,)>(
      context,
      _PickerSheet<T>(title: label, options: options, current: current),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final String label;
  final bool selected;
  const _PickerRow({required this.label, required this.selected});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: selected ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Icon(Icons.check_rounded, size: 18, color: scheme.primary),
        ),
      ],
    );
  }
}

class _PickerSheet<T> extends StatefulWidget {
  final String title;
  final Map<T, String> options;
  final T? current;
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.current,
  });
  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final searchable = widget.options.length > 8;
    final visible = widget.options.entries
        .where((e) => e.value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (searchable) ...[
          TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
            onChanged: (v) => setState(() => query = v.trim()),
          ),
          const SizedBox(height: 6),
        ],
        for (final e in visible)
          InkWell(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            onTap: () => Navigator.pop(context, (e.key,)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: _PickerRow(
                label: e.value,
                selected: e.key == widget.current,
              ),
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No matches.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(action!),
          ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    this.title = "You're all clear.",
    this.message = 'Nothing to show here yet.',
    this.icon = Icons.check_circle_outline_rounded,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DeskIllustration(
          kind: icon == Icons.cloud_off_outlined
              ? DeskArt.connection
              : message.toLowerCase().contains('document')
              ? DeskArt.documents
              : message.toLowerCase().contains('search')
              ? DeskArt.search
              : DeskArt.clear,
          size: 88,
          monochrome: true,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 20),
          PrimaryButton(label: action!, onPressed: onAction),
        ],
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
    title: 'Something went wrong.',
    message: friendlyError(error),
    icon: Icons.cloud_off_outlined,
    action: 'Try again',
    onAction: onRetry,
  );
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    highlightColor: Theme.of(context).colorScheme.surface,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (int i = 0; i < 6; i++)
          Container(
            height: i == 0 ? 96 : 72,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            ),
          ),
      ],
    ),
  );
}

class WorkspaceBody extends ConsumerWidget {
  final Widget child;
  const WorkspaceBody({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(workspaceProvider)
      .when(
        data: (_) => child,
        loading: () => const LoadingSkeleton(),
        error: (e, st) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(workspaceProvider),
        ),
      );
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final bool eager;
  const PageBody({
    super.key,
    required this.children,
    this.onRefresh,
    this.eager = false,
  });
  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, c) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          c.maxWidth >= 1000 ? 32 : (c.maxWidth > 700 ? 24 : 16),
          14,
          c.maxWidth >= 1000 ? 32 : (c.maxWidth > 700 ? 24 : 16),
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: eager
            ? [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ]
            : children,
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: onRefresh == null
            ? body
            : RefreshIndicator(
                onRefresh: () async {
                  await runAction(context, onRefresh!);
                },
                child: body,
              ),
      ),
    );
  }
}

Future<T?> glassSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      barrierColor: Colors.black.withValues(alpha: .28),
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final glass = GlassTokens.of(context);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: FrostedPanel(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSizes.radiusXl + 8),
            ),
            color: Color.alphaBlend(
              glass.chrome,
              scheme.surface.withValues(alpha: .55),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        4,
                        20,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
void feedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) feedback(context, success);
    return true;
  } catch (e) {
    if (context.mounted) feedback(context, friendlyError(e));
    return false;
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message, {
  String confirm = 'Confirm',
}) async =>
    await glassSheet<bool>(
      context,
      Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 24),
            PrimaryButton(
              label: confirm,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ) ??
    false;
