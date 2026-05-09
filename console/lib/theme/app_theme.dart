import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF5B21B6);
  static const Color primaryDark = Color(0xFF7C3AED);
  static const Color ink = Color(0xFF0F172A);
  static const Color mist = Color(0xFFF8FAFC);
  static const Color outline = Color(0xFFDDE3EC);

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
      scaffoldBackgroundColor: scheme.brightness == Brightness.dark
          ? const Color(0xFF020617)
          : mist,
    );

    final textTheme = GoogleFonts.openSansTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.montserrat(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      displayMedium: GoogleFonts.montserrat(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      headlineMedium: GoogleFonts.montserrat(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: GoogleFonts.montserrat(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: GoogleFonts.montserrat(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: GoogleFonts.openSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      bodyMedium: GoogleFonts.openSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface.withValues(alpha: 0.88),
      ),
      labelLarge: GoogleFonts.openSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
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
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.55),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}
