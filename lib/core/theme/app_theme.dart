import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Warm, paper-like palette with a single clay accent.
abstract final class AppColors {
  static const primary = Color(0xFFC6613F),
      primaryDark = Color(0xFFD97757),
      secondary = Color(0xFF6A9BCC),
      success = Color(0xFF3F8F5F),
      warning = Color(0xFFC98A2B),
      danger = Color(0xFFB53333),
      ink = Color(0xFF141413),
      ivory = Color(0xFFFAF9F5),
      clayLight = Color(0xFFF2DDD3);
}

/// Shared size tokens so icons, corners and touch targets stay consistent.
/// Corners are deliberately modest: crisp, paper-like edges rather than
/// pill shapes.
abstract final class AppSizes {
  static const iconXs = 16.0, iconSm = 18.0, iconMd = 20.0, iconLg = 24.0;
  static const radiusSm = 6.0, radiusMd = 8.0, radiusLg = 10.0;
  static const radiusXl = 12.0;

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
    backgroundColor: scheme.surfaceContainerLowest,
    foregroundColor: scheme.onSurface,
    side: BorderSide(color: scheme.outlineVariant),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
    ),
  );
}

/// Calm, flat, warm-neutral surfaces with hairline borders, serif headings
/// and a single clay accent, in the manner of a well-made notebook.
abstract final class AppTheme {
  static const serif = 'NotoSerif';

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: dark ? AppColors.primaryDark : AppColors.primary,
          onPrimary: dark ? AppColors.ink : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF4A2E24)
              : AppColors.clayLight,
          onPrimaryContainer: dark
              ? const Color(0xFFF2DDD3)
              : const Color(0xFF5C2A18),
          error: dark ? const Color(0xFFE58A80) : AppColors.danger,
          // Page background.
          surface: dark ? const Color(0xFF262624) : AppColors.ivory,
          // Cards, inputs, sheets.
          surfaceContainerLowest: dark
              ? const Color(0xFF30302E)
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: dark
              ? const Color(0xFF2B2B29)
              : const Color(0xFFF5F4EE),
          surfaceContainer: dark
              ? const Color(0xFF343432)
              : const Color(0xFFF0EEE6),
          surfaceContainerHigh: dark
              ? const Color(0xFF3B3B38)
              : const Color(0xFFE8E6DC),
          surfaceContainerHighest: dark
              ? const Color(0xFF44433F)
              : const Color(0xFFDEDCD1),
          onSurface: dark ? AppColors.ivory : AppColors.ink,
          onSurfaceVariant: dark
              ? const Color(0xFFA6A39A)
              : const Color(0xFF6B6A63),
          outline: dark ? const Color(0xFF5F5E59) : const Color(0xFFB7B5AA),
          // Hairline borders and dividers.
          outlineVariant: dark
              ? const Color(0xFF3E3D3A)
              : const Color(0xFFE5E3D8),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,
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
        fillColor: scheme.surfaceContainerLowest,
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
          foregroundColor: scheme.onPrimary,
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
          backgroundColor: scheme.surfaceContainerLowest,
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
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
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
        backgroundColor: dark ? const Color(0xFF3B3B38) : AppColors.ink,
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
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(36, 4),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSizes.radiusXl),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: serif,
          fontSize: 19,
          fontWeight: FontWeight.w500,
          letterSpacing: -.3,
          color: scheme.onSurface,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLowest,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(scheme.outlineVariant),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.white : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHigh,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.onSurface,
          selectedBackgroundColor: scheme.onSurface,
          selectedForegroundColor: scheme.surface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
