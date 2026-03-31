import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0C0C10);
  static const surface = Color(0xFF12151E);
  static const card = Color(0xFF1A1A24);
  static const border = Color(0xFF1E1E28);
  static const border2 = Color(0xFF2A2A32);
  static const accent = Color(0xFF2DD4B0);
  static const textPrimary = Colors.white;
  static const textMuted = Color(0xFF888888);
  static const textDimmed = Color(0xFF444444);
  static const errorBackground = Color(0xFF2D0A0A);
  static const errorText = Color(0xFFFCA5A5);

  // Pre-computed accent tints — use instead of AppColors.accent.withAlpha(n)
  static const accentGhost  = Color(0x142DD4B0); // accent withAlpha(20)
  static const accentFaint  = Color(0x162DD4B0); // accent withAlpha(22)
  static const accentSubtle = Color(0x1E2DD4B0); // accent withAlpha(30)
  static const accentBorder = Color(0x3C2DD4B0); // accent withAlpha(60)
  static const accentMid    = Color(0x642DD4B0); // accent withAlpha(100)
  // Overlay scrim for modal drawers / bottom sheets
  static const scrim        = Color(0x78000000); // black withAlpha(120)

  AppColors._();
}

/// 8pt-grid spacing tokens — use these instead of raw numbers.
/// §5.5: spaceXS=8, spaceS=16, spaceM=24, spaceL=32, spaceXL=48, spaceXXL=80
class AppSpacing {
  static const double xs  =  8;
  static const double s   = 16;
  static const double m   = 24;
  static const double l   = 32;
  static const double xl  = 48;
  static const double xxl = 80;

  AppSpacing._();
}

/// Type-scale tokens (Minor Third, ratio ≈ 1.2).
/// Prefer these named getters over AppTextStyles.sans(size:) with raw numbers.
/// §4.4: only w400 (regular) and w600 (app bold) are used.
/// §4.7: line height varies by size — headings tighter, body looser.
class AppTextStyles {
  // --- named scale ---
  /// H3 heading — 24pt, bold
  static TextStyle heading  ({Color color = Colors.white}) => GoogleFonts.dmSans(fontSize: 24, fontWeight: FontWeight.w600, color: color, height: 1.3);
  /// H4 sub-heading — 20pt, bold
  static TextStyle subHeading({Color color = Colors.white}) => GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w600, color: color, height: 1.35);
  /// Body — 16pt, regular
  static TextStyle body     ({Color color = Colors.white}) => GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w400, color: color, height: 1.5);
  /// Small body / label — 14pt, regular
  static TextStyle label    ({Color color = Colors.white}) => GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w400, color: color, height: 1.45);
  /// Caption / metadata — 12pt, regular
  static TextStyle caption  ({Color color = Colors.white}) => GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w400, color: color, height: 1.4);

  // --- legacy flexible helpers (still valid for dense data views) ---
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
  }) =>
      GoogleFonts.dmMono(fontSize: size, fontWeight: weight, color: color);

  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
  }) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color);

  AppTextStyles._();
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.accent,
        onPrimary: Colors.black,
        secondary: AppColors.accent,
        onSurface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  AppTheme._();
}

/// Returns true when the device's shortest side is ≥ 600dp (iPad / large tablet).
bool isTablet(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide >= 600;

/// Returns true on ultra-wide displays (21:9 and wider).
/// Requires shortestSide ≥ 600 to exclude phones in landscape,
/// which share a similar aspect ratio (~19.5:9 ≈ 2.17).
bool isUltraWide(BuildContext context) {
  final size = MediaQuery.of(context).size;
  return size.shortestSide >= 600 && size.width / size.height >= 1.9;
}
