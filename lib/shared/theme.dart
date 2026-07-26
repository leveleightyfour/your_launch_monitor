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
  static const textMuted = Color(0xFF9C9C9C);
  static const textDimmed = Color(0xFF848484);
  static const errorBackground = Color(0xFF2D0A0A);
  static const errorText = Color(0xFFFCA5A5);

  // Pre-computed accent tints — use instead of AppColors.accent.withAlpha(n)
  static const accentGhost = Color(0x142DD4B0); // accent withAlpha(20)
  static const accentFaint = Color(0x162DD4B0); // accent withAlpha(22)
  static const accentSubtle = Color(0x1E2DD4B0); // accent withAlpha(30)
  static const accentBorder = Color(0x3C2DD4B0); // accent withAlpha(60)
  static const accentMid = Color(0x642DD4B0); // accent withAlpha(100)
  // Overlay scrim for modal drawers / bottom sheets
  static const scrim = Color(0x78000000); // black withAlpha(120)

  // ── Course surfaces, for the 3D flight view ─────────────────────────────
  // Deliberately independent of the accent. The accent means "your shot" —
  // landing marks, roll path, read-outs — so the world those land in must not
  // recolour with it, or a Lime accent hides the pin against the green and an
  // Orange one loses the target line in the rough.
  // Turf sat at roughly a twentieth of the luminance of the photoreal views
  // these are measured against, which is why the mowing never read: the light
  // and dark bands were in the right *ratio* (1.39x against a reference 1.45x)
  // but 1.39x of near-black is a difference of half a percent of white, and
  // the eye cannot find it. Lifting the whole surface is what makes the bands
  // appear; the ratio never needed touching.
  //
  // Brightening turf does not cost the shot its prominence. The reference's
  // trace is *darker* than the fairway it crosses — it dominates on chroma and
  // hue distance, not luminance. Every accent stays 44+ dE from every surface
  // here, so the shot still reads as the only vivid thing in the scene.
  //
  // Hue moves with it: turf was 140-145 degrees, a blue-green that belongs to
  // the app's cool greys rather than to grass. Real mown fairway sits nearer
  // 100-130. The far field is pulled back toward the horizon by the haze pass
  // rather than by being painted dark, so depth survives the lift.
  static const turfGround = Color(0xFF161C18);
  static const turfFairway = Color(0xFF2C4732);

  /// Every other mown band. Still a whisper in ratio terms, but now a visible
  /// one — 0.021 of separation where it used to be 0.005.
  static const turfFairwayStripe = Color(0xFF35543A);

  /// Off the fairway: drier and more olive than the mown surface, so missing
  /// the short grass is legible at a glance rather than only by position.
  static const turfRough = Color(0xFF2B2F23);

  /// Clumps scattered over the rough. Two tones either side of the base so the
  /// surface breaks up without turning into noise.
  static const turfRoughClump = Color(0xFF343A29);
  static const turfRoughClumpDark = Color(0xFF23271D);

  /// Putting surface — lighter and yellower than fairway, the way a tighter
  /// cut actually looks.
  static const turfGreen = Color(0xFF3E6B45);

  /// The collar: the fringe ring between green and its surround. The single
  /// clearest "this is a green" cue at a glance.
  static const turfGreenCollar = Color(0xFF50805A);
  static const turfGreenEdge = Color(0xFF6DA878);
  static const turfGrid = Color(0xFF3A5148);

  // ── Built terrain ────────────────────────────────────────────────────────
  // Hazards have to be identifiable at a glance from a moving camera, so each
  // sits in its own hue family rather than being a shade of the turf.
  static const turfBunker = Color(0xFFB9A77A);
  static const turfBunkerEdge = Color(0xFF8C7C55);
  static const turfWater = Color(0xFF2B5A7A);
  static const turfWaterEdge = Color(0xFF4E8CB0);

  /// Ground beneath the trees — rough, shaded by what is standing on it.
  static const turfTrees = Color(0xFF232B22);
  static const treeCanopy = Color(0xFF3D6B3A);
  static const treeCanopyLit = Color(0xFF4F8449);
  static const treeTrunk = Color(0xFF3A2E22);

  /// Out of bounds. Deliberately drab — it is the one surface that means the
  /// shot is over, and it should look like nothing worth aiming at.
  static const turfOob = Color(0xFF2A2622);
  static const turfOobStake = Color(0xFFD8D2C4);

  /// Distance haze. The far field fades to this instead of being painted dark,
  /// which is what keeps depth once the near turf is bright.
  static const turfHaze = Color(0xFF16221F);

  /// Horizon tone the backdrop fades to.
  static const skyLow = Color(0xFF0E1418);

  /// Flagstick red — fixed, so it reads against the green at any accent.
  static const pinFlag = Color(0xFFD9483B);

  /// The line to the target. Scenery, not data, so neutral.
  static const targetLine = Color(0xFFC8D2D0);

  AppColors._();
}

/// 8pt-grid spacing tokens — use these instead of raw numbers.
/// §5.5: spaceXS=8, spaceS=16, spaceM=24, spaceL=32, spaceXL=48, spaceXXL=80
class AppSpacing {
  static const double xs = 8;
  static const double s = 16;
  static const double m = 24;
  static const double l = 32;
  static const double xl = 48;
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
  static TextStyle heading({Color color = Colors.white}) => GoogleFonts.dmSans(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.3,
  );

  /// H4 sub-heading — 20pt, bold
  static TextStyle subHeading({Color color = Colors.white}) =>
      GoogleFonts.dmSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.35,
      );

  /// Body — 16pt, regular
  static TextStyle body({Color color = Colors.white}) => GoogleFonts.dmSans(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.5,
  );

  /// Small body / label — 14pt, regular
  static TextStyle label({Color color = Colors.white}) => GoogleFonts.dmSans(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.45,
  );

  /// Caption / metadata — 12pt, regular
  static TextStyle caption({Color color = Colors.white}) => GoogleFonts.dmSans(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.4,
  );

  // --- legacy flexible helpers (still valid for dense data views) ---
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
  }) => GoogleFonts.dmMono(fontSize: size, fontWeight: weight, color: color);

  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
  }) => GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color);

  AppTextStyles._();
}

class AppTheme {
  static ThemeData dark({Color accent = AppColors.accent}) {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.dark(
        surface: AppColors.background,
        primary: accent,
        onPrimary: Colors.black,
        secondary: accent,
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
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.black,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(
        base.textTheme,
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
    );
  }

  AppTheme._();
}

// ── Accent colour extension ───────────────────────────────────────────────────

/// Read the current accent colour from the nearest [Theme].
/// All widgets should use this instead of [AppColors.accent] directly.
extension AppAccent on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;

  /// Pre-computed tints — equivalent to the old AppColors.accentXxx constants.
  Color get accentGhost  => accent.withAlpha(20);
  Color get accentFaint  => accent.withAlpha(22);
  Color get accentSubtle => accent.withAlpha(30);
  Color get accentBorder => accent.withAlpha(60);
  Color get accentMid    => accent.withAlpha(100);
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
