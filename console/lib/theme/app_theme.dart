import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF7C3AED);
  static const Color ink = Color(0xFF0F172A);
  static const Color mist = Color(0xFFF8FAFC);
  static const Color outline = Color(0xFFDDE3EC);
  static const String codeFontFamily = 'monospace';

  // ── Font ──────────────────────────────────────────────────────────────────
  // To switch the app font: change 'montserrat' to any GoogleFonts name.
  static TextStyle _font(double size, FontWeight weight, {Color? color}) =>
      GoogleFonts.montserrat(fontSize: size, fontWeight: weight, color: color);

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: Color(0xFF475569),
      onSecondary: Colors.white,
      error: Color(0xFFB42318),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: ink,
      tertiary: Color(0xFFEDE9FE),
      onTertiary: ink,
      outline: outline,
      outlineVariant: Color(0xFFEBEEF5),
      shadow: Color(0x140F172A),
      scrim: Color(0x660F172A),
      inverseSurface: ink,
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFFC4B5FD),
      surfaceTint: primary,
    );

    return _buildTheme(scheme);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primaryDark,
      onPrimary: Colors.white,
      secondary: Color(0xFFCBD5E1),
      onSecondary: ink,
      error: Color(0xFFF97066),
      onError: ink,
      surface: Color(0xFF0B1120),
      onSurface: Color(0xFFF8FAFC),
      tertiary: Color(0xFF1E1B4B),
      onTertiary: Color(0xFFF8FAFC),
      outline: Color(0xFF263247),
      outlineVariant: Color(0xFF182235),
      shadow: Color(0x66000000),
      scrim: Color(0x99000000),
      inverseSurface: Color(0xFFF8FAFC),
      onInverseSurface: ink,
      inversePrimary: primary,
      surfaceTint: primaryDark,
    );

    return _buildTheme(scheme);
  }

  static ThemeData _buildTheme(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Derived from _font so non-explicit text styles also pick up the font.
      fontFamily: _font(14, FontWeight.w400).fontFamily,
      scaffoldBackgroundColor: scheme.brightness == Brightness.dark
          ? const Color(0xFF020617)
          : mist,
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: _font(48, FontWeight.w700, color: scheme.onSurface),
      displayMedium: _font(40, FontWeight.w700, color: scheme.onSurface),
      headlineMedium: _font(28, FontWeight.w700, color: scheme.onSurface),
      titleLarge: _font(20, FontWeight.w700, color: scheme.onSurface),
      titleMedium: _font(16, FontWeight.w600, color: scheme.onSurface),
      bodyLarge: _font(15, FontWeight.w500, color: scheme.onSurface),
      bodyMedium: _font(14, FontWeight.w500,
          color: scheme.onSurface.withValues(alpha: 0.88)),
      bodySmall: _font(12, FontWeight.w500,
          color: scheme.onSurface.withValues(alpha: 0.78)),
      labelLarge: _font(14, FontWeight.w700, color: scheme.onSurface),
      labelMedium: _font(12, FontWeight.w600, color: scheme.onSurface),
      labelSmall: _font(11, FontWeight.w600, color: scheme.onSurface),
    );

    // Button text style: w500 from the same _font() so the correct variant
    // is loaded (not a copyWith over a variant-specific fontFamily string).
    final buttonTextStyle = WidgetStatePropertyAll(
      _font(14, FontWeight.w500),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: const IconThemeData(size: 22),
        unselectedIconTheme: IconThemeData(
          size: 20,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: textTheme.bodyMedium,
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: scheme.primary,
        secondarySelectedColor: scheme.primary,
        checkmarkColor: scheme.onPrimary,
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
        ),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dialogTheme: DialogThemeData(
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.68),
        ),
        leadingAndTrailingTextStyle: textTheme.labelMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        ),
        iconColor: scheme.onSurface.withValues(alpha: 0.78),
        mouseCursor: WidgetStateMouseCursor.clickable,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: textTheme.bodySmall?.copyWith(color: scheme.surface),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.surface),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: const ButtonStyle(
          mouseCursor: WidgetStatePropertyAll(WidgetStateMouseCursor.clickable),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          textStyle: buttonTextStyle,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          mouseCursor: const WidgetStatePropertyAll(
            WidgetStateMouseCursor.clickable,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          textStyle: buttonTextStyle,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          mouseCursor: const WidgetStatePropertyAll(
            WidgetStateMouseCursor.clickable,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          textStyle: buttonTextStyle,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          mouseCursor: const WidgetStatePropertyAll(
            WidgetStateMouseCursor.clickable,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            _font(12, FontWeight.w500),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          mouseCursor: const WidgetStatePropertyAll(
            WidgetStateMouseCursor.clickable,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.68),
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.55),
        ),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
        counterStyle: textTheme.bodySmall,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}
