import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

/// How a [TileMetric] turns into the strings a tile shows.
///
/// These live outside the widget that draws them because the tiles are no
/// longer the only surface rendering a metric: the rethink session screen's
/// rail reads them, and the Apple Watch bridge ships the very same strings to
/// the watch. One formatter means the watch can never disagree with the phone
/// about what a shot carried.

/// Returns the display unit label for [m] respecting [prefs].
String tileUnit(TileMetric m, UnitPrefs prefs) => switch (m) {
  TileMetric.ballSpeed || TileMetric.clubSpeed => prefs.speedLabel,
  TileMetric.apex ||
  TileMetric.carry ||
  TileMetric.run ||
  TileMetric.totalDistance ||
  TileMetric.offline => prefs.distLabel,
  TileMetric.horizontalImpact || TileMetric.verticalImpact => 'mm',
  _ => m.unit,
};

String metricValue(TileMetric m, ShotData? s, UnitPrefs prefs) {
  if (s == null) return '--';
  return switch (m) {
    TileMetric.ballSpeed => prefs.spd(s.ballSpeed).toStringAsFixed(1),
    TileMetric.launchDirection => '${s.launchDirection.toStringAsFixed(1)}°',
    TileMetric.launchAngle => '${s.launchAngle.toStringAsFixed(1)}°',
    TileMetric.spinRate => s.spinRate.toStringAsFixed(0),
    TileMetric.spinAxis => '${s.spinAxis.toStringAsFixed(1)}°',
    TileMetric.apex =>
      s.apex != null ? prefs.dist(s.apex!).toStringAsFixed(1) : '--',
    TileMetric.carry => prefs.dist(s.carry).toStringAsFixed(1),
    TileMetric.run =>
      s.run != null ? prefs.dist(s.run!).toStringAsFixed(1) : '--',
    TileMetric.totalDistance => prefs.dist(s.totalDistance).toStringAsFixed(1),
    TileMetric.clubSpeed => prefs.spd(s.clubSpeed).toStringAsFixed(1),
    TileMetric.swingPath =>
      s.swingPath != null
          ? '${s.swingPath!.abs().toStringAsFixed(1)}° ${s.swingPath! >= 0 ? 'R' : 'L'}'
          : '--',
    TileMetric.faceAngle =>
      s.faceAngle != null
          ? '${s.faceAngle!.abs().toStringAsFixed(1)}° ${s.faceAngle! >= 0 ? 'R' : 'L'}'
          : '--',
    TileMetric.angleOfAttack =>
      s.angleOfAttack != null
          ? '${s.angleOfAttack!.toStringAsFixed(1)}°'
          : '--',
    TileMetric.smashFactor => s.smashFactor.toStringAsFixed(2),
    TileMetric.dynamicLoft =>
      s.dynamicLoft != null ? '${s.dynamicLoft!.toStringAsFixed(1)}°' : '--',
    // Combined display handled directly in the tile widget; return horizontal
    // only here so avg / diff calculations still work.
    TileMetric.impactLocation =>
      s.horizontalImpact != null
          ? '${s.horizontalImpact!.abs().toStringAsFixed(1)} '
                '${s.horizontalImpact! >= 0 ? 'T' : 'H'}'
          : '--',
    TileMetric.horizontalImpact => fmtImpactH(s.horizontalImpact),
    TileMetric.verticalImpact => fmtImpactV(s.verticalImpact),
    TileMetric.offline => () {
      final v = prefs.dist(s.lateralOffset);
      return '${v.abs().toStringAsFixed(1)} ${s.lateralOffset > 0
          ? 'R'
          : s.lateralOffset < 0
          ? 'L'
          : ''}';
    }(),
  };
}

double? metricRaw(TileMetric m, ShotData? s, UnitPrefs prefs) {
  if (s == null) return null;
  return switch (m) {
    TileMetric.ballSpeed => prefs.spd(s.ballSpeed),
    TileMetric.launchDirection => s.launchDirection,
    TileMetric.launchAngle => s.launchAngle,
    TileMetric.spinRate => s.spinRate,
    TileMetric.spinAxis => s.spinAxis,
    TileMetric.apex => s.apex != null ? prefs.dist(s.apex!) : null,
    TileMetric.carry => prefs.dist(s.carry),
    TileMetric.run => s.run != null ? prefs.dist(s.run!) : null,
    TileMetric.totalDistance => prefs.dist(s.totalDistance),
    TileMetric.clubSpeed => prefs.spd(s.clubSpeed),
    TileMetric.swingPath => s.swingPath,
    TileMetric.faceAngle => s.faceAngle,
    TileMetric.angleOfAttack => s.angleOfAttack,
    TileMetric.smashFactor => s.smashFactor,
    TileMetric.dynamicLoft => s.dynamicLoft,
    TileMetric.impactLocation => s.horizontalImpact,
    TileMetric.horizontalImpact => s.horizontalImpact,
    TileMetric.verticalImpact => s.verticalImpact,
    TileMetric.offline => prefs.dist(s.lateralOffset),
  };
}

/// Splits a formatted metric into the number and any trailing direction
/// letter — R/L, T/H — so the digits can render full size with the letter set
/// smaller beside them. A letter scaled with the digits was quietly shrinking
/// every directional metric: '1.1° R' drew its digits far smaller than a
/// bare '5500'.
///
/// The degree sign stays with the number: at full size the glyph is already
/// small and sits at the top of the line, which is exactly where it belongs —
/// shrunk and baseline-aligned like a letter it drops to mid-height.
(String, String) splitValueSuffix(String value) {
  final match = RegExp(r'^[-\d.]+°?').firstMatch(value);
  if (match == null) return (value, '');
  return (match.group(0)!, value.substring(match.end).trim());
}

String fmtImpactH(double? v) {
  if (v == null) return '--';
  return '${v.abs().toStringAsFixed(1)} ${v >= 0 ? 'T' : 'H'}';
}

String fmtImpactV(double? v) {
  if (v == null) return '--';
  return '${v.abs().toStringAsFixed(1)} ${v >= 0 ? 'H' : 'L'}';
}
