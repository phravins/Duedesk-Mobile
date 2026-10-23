import 'dart:ui' show lerpDouble;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF6C63FF),
      secondary = Color(0xFF40C4FF),
      success = Color(0xFF22C55E),
      warning = Color(0xFFF59E0B),
      danger = Color(0xFFEF4444);
}

/// Shared size tokens so icons, corners and touch targets stay consistent.
abstract final class AppSizes {
  static const iconXs = 16.0, iconSm = 18.0, iconMd = 20.0, iconLg = 24.0;
  static const radiusSm = 8.0, radiusMd = 12.0, radiusLg = 14.0;
  static const radiusXl = 20.0;

  /// Width at which the bottom bar gives way to a navigation rail. Phones
  /// (shortest side under this) keep the bottom bar even in landscape.
  static const railBreakpoint = 600.0;

  /// Width at which the rail shows labels beside the icons.
  static const extendedRailBreakpoint = 1200.0;
}

/// Square-ish 44px icon buttons used beside headings and search fields.
abstract final class AppIconButtonStyles {
  static ButtonStyle filled() => IconButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    minimumSize: const Size(44, 44),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
    ),
  );
  static ButtonStyle outlined(ColorScheme scheme) => IconButton.styleFrom(
    minimumSize: const Size(44, 44),
    backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: .7),
    foregroundColor: scheme.onSurface,
    side: BorderSide(color: scheme.outlineVariant),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
    ),
  );
}

/// Frosted-glass surface tokens, in the spirit of iOS materials.
///
/// Cards are translucent over an ambient backdrop; navigation chrome, sheets
/// and banners also blur what scrolls behind them.
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  /// Card and panel fill.
  final Color fill;

  /// Thicker fill for chrome that floats above content (tab bar, banners).
  final Color chrome;

  /// Hairline edge that catches the light.
  final Color border;

  /// Subtle top-left sheen laid over [fill].
  final Color highlight;
  final Color shadow;

  /// Page backdrop: a base wash and the soft colour glows behind the glass.
  final Color base;
  final List<Color> glows;
  final double blur;
  const GlassTokens({
    required this.fill,
    required this.chrome,
    required this.border,
    required this.highlight,
    required this.shadow,
    required this.base,
    required this.glows,
    this.blur = 24,
  });

  static const light = GlassTokens(
    fill: Color(0xA8FFFFFF),
    chrome: Color(0xC7FFFFFF),
    border: Color(0xB3FFFFFF),
    highlight: Color(0x66FFFFFF),
    shadow: Color(0x141B1F3B),
    base: Color(0xFFF1F2F8),
    glows: [Color(0x4D7C74FF), Color(0x4040C4FF), Color(0x33FF9EC4)],
  );
  static const dark = GlassTokens(
    fill: Color(0x1AFFFFFF),
    chrome: Color(0xB8202230),
    border: Color(0x24FFFFFF),
    highlight: Color(0x0FFFFFFF),
    shadow: Color(0x52000000),
    base: Color(0xFF0D0E15),
    glows: [Color(0x596C63FF), Color(0x3329B6F6), Color(0x2EC86BFA)],
  );

  static GlassTokens of(BuildContext context) =>
      Theme.of(context).extension<GlassTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  List<BoxShadow> get shadows => [
    BoxShadow(color: shadow, blurRadius: 28, offset: const Offset(0, 10)),
  ];

  /// The sheen fades out across the card, so text stays on an even fill.
  Gradient sheen() => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color.alphaBlend(highlight, fill), fill],
    stops: const [0, .6],
  );

  @override
  GlassTokens copyWith({
    Color? fill,
    Color? chrome,
    Color? border,
    Color? highlight,
    Color? shadow,
    Color? base,
    List<Color>? glows,
    double? blur,
  }) => GlassTokens(
    fill: fill ?? this.fill,
    chrome: chrome ?? this.chrome,
    border: border ?? this.border,
    highlight: highlight ?? this.highlight,
    shadow: shadow ?? this.shadow,
    base: base ?? this.base,
    glows: glows ?? this.glows,
    blur: blur ?? this.blur,
  );

  @override
  GlassTokens lerp(GlassTokens? other, double t) {
    if (other == null) return this;
    return GlassTokens(
      fill: Color.lerp(fill, other.fill, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      border: Color.lerp(border, other.border, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      base: Color.lerp(base, other.base, t)!,
      glows: [
        for (var i = 0; i < glows.length; i++)
          Color.lerp(glows[i], other.glows[i % other.glows.length], t)!,
      ],
      blur: lerpDouble(blur, other.blur, t)!,
    );
  }
}

/// Translucent glass over an ambient backdrop, with a single accent colour.
abstract final class AppTheme {
  static const serif = 'NotoSerif';

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFA9A3FF) : const Color(0xFF5C52DE),
          // Page background.
          surface: dark ? const Color(0xFF12131A) : const Color(0xFFF4F5FA),
          // Cards, inputs, sheets.
          surfaceContainerLowest: dark
              ? const Color(0xFF1C1E28)
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: dark
              ? const Color(0xFF20222D)
              : const Color(0xFFF6F6FB),
          surfaceContainer: dark
              ? const Color(0xFF262834)
              : const Color(0xFFEEEFF6),
          surfaceContainerHigh: dark
              ? const Color(0xFF2E303D)
              : const Color(0xFFE6E7F1),
          surfaceContainerHighest: dark
              ? const Color(0xFF373A48)
              : const Color(0xFFDDDFEB),
          onSurface: dark ? const Color(0xFFF3F4FA) : const Color(0xFF181A26),
          onSurfaceVariant: dark
              ? const Color(0xFFA3A6B8)
              : const Color(0xFF5D6074),
          outline: dark ? const Color(0xFF555869) : const Color(0xFFB3B6C6),
          // Hairline borders and dividers.
          outlineVariant: dark
              ? const Color(0xFF2C2E3B)
              : const Color(0xFFE1E3EE),
        );
    final glass = dark ? GlassTokens.dark : GlassTokens.light;
    final base = ThemeData(
      useMaterial3: true,
      extensions: [glass],
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
    TextStyle? serifStyle(TextStyle? style, double size) => style?.copyWith(
      fontFamily: serif,
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: -.4,
      height: 1.2,
      color: scheme.onSurface,
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: serifStyle(base.textTheme.headlineLarge, 25),
        headlineMedium: serifStyle(base.textTheme.headlineMedium, 22),
        headlineSmall: serifStyle(base.textTheme.headlineSmall, 20),
        titleLarge: serifStyle(base.textTheme.titleLarge, 18),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -.1,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: IconThemeData(
        size: AppSizes.iconLg,
        color: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: true,
        fillColor: dark ? const Color(0x14FFFFFF) : const Color(0xB3FFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: border(scheme.outlineVariant),
        enabledBorder: border(scheme.outlineVariant),
        focusedBorder: border(scheme.primary, 1.5),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: dark ? const Color(0xFF1C1B1A) : Colors.white,
          minimumSize: const Size(44, 46),
          iconSize: AppSizes.iconMd,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          backgroundColor: glass.fill,
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          iconSize: AppSizes.iconMd,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          iconSize: AppSizes.iconLg,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        minLeadingWidth: 24,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.surfaceContainerHigh,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(
          color: scheme.onSurface,
          size: AppSizes.iconLg,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: AppSizes.iconLg,
        ),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: scheme.onInverseSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF2B2E3C)
            : const Color(0xF0181A26),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13.5,
          color: Colors.white,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSizes.radiusXl),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -.2,
          color: scheme.onSurface,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: glass.fill,
        selectedColor: scheme.onSurface,
        secondarySelectedColor: scheme.onSurface,
        checkmarkColor: scheme.surface,
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? scheme.surface
                : scheme.onSurface,
          ),
        ),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(scheme.outlineVariant),
      ),
    );
  }
}
