import 'dart:math' as math;

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

// ── Diagnostic ───────────────────────────────────────────────────────────────

class Diagnostic {
  final String metric;
  final double measured;
  final double minOptimal;
  final double maxOptimal;
  final String severity; // 'critical', 'high', 'medium', 'low'
  final List<String> possibleRootCauses;
  /// Estimated yards lost due to this inefficiency.
  final double? estimatedYardsLost;

  const Diagnostic({
    required this.metric,
    required this.measured,
    required this.minOptimal,
    required this.maxOptimal,
    required this.severity,
    required this.possibleRootCauses,
    this.estimatedYardsLost,
  });

  bool get isOutOfRange => measured < minOptimal || measured > maxOptimal;
}

// ── Recommendation ───────────────────────────────────────────────────────────

class Recommendation {
  final String action;
  final String description;
  final List<String> affectedMetrics;
  final int priority; // 1 = highest
  /// Estimated carry gain if this fix is applied.
  final double? expectedGainYards;

  const Recommendation({
    required this.action,
    required this.description,
    required this.affectedMetrics,
    required this.priority,
    this.expectedGainYards,
  });
}

// ── ShotAnalysis ─────────────────────────────────────────────────────────────

class ShotAnalysis {
  final ShotData shot;
  final List<Diagnostic> diagnostics;
  final List<Recommendation> recommendations;
  final String summary;
  /// Estimated optimal carry for this swing speed and club.
  final double? optimalCarry;
  /// Gap between actual and optimal carry.
  final double? carryGap;

  const ShotAnalysis({
    required this.shot,
    required this.diagnostics,
    required this.recommendations,
    required this.summary,
    this.optimalCarry,
    this.carryGap,
  });

  List<Diagnostic> get criticalIssues =>
      diagnostics.where((d) => d.severity == 'critical').toList();

  List<Diagnostic> get outOfRangeMetrics =>
      diagnostics.where((d) => d.isOutOfRange).toList();
}

// ── Speed band ───────────────────────────────────────────────────────────────

enum _SpeedBand { slow, moderate, fast }

_SpeedBand _driverSpeedBand(double clubSpeed) {
  if (clubSpeed < 90) return _SpeedBand.slow;
  if (clubSpeed < 105) return _SpeedBand.moderate;
  return _SpeedBand.fast;
}

// ── Optimal ranges ───────────────────────────────────────────────────────────

class OptimalRanges {
  // ── Driver: speed-aware windows ──
  static const _driverBySpeed = {
    _SpeedBand.slow: {
      'launchAngle': (11.0, 15.0),
      'spinRate': (2500.0, 3200.0),
      'smashFactor': (1.45, 1.65),
    },
    _SpeedBand.moderate: {
      'launchAngle': (10.0, 14.0),
      'spinRate': (2200.0, 2800.0),
      'smashFactor': (1.45, 1.65),
    },
    _SpeedBand.fast: {
      'launchAngle': (9.0, 13.0),
      'spinRate': (2000.0, 2600.0),
      'smashFactor': (1.45, 1.65),
    },
  };

  // ── Flat ranges for non-driver clubs ──
  static const Map<ClubType, Map<String, (double, double)>> _flat = {
    ClubType.miniDriver: {
      'launchAngle': (10.0, 15.0),
      'spinRate': (2200.0, 3000.0),
      'smashFactor': (1.45, 1.65),
    },
    ClubType.wood: {
      'launchAngle': (14.0, 20.0),
      'spinRate': (2500.0, 3600.0),
      'smashFactor': (1.40, 1.60),
    },
    ClubType.hybrid: {
      'launchAngle': (16.0, 26.0),
      'spinRate': (3000.0, 4200.0),
      'smashFactor': (1.35, 1.55),
    },
    ClubType.iron: {
      'launchAngle': (14.0, 22.0),
      'smashFactor': (1.35, 1.50),
      // spinRate handled by _ironSpinRange()
    },
    ClubType.wedge: {
      'launchAngle': (24.0, 40.0),
      'smashFactor': (1.20, 1.45),
      // spinRate handled by _wedgeSpinRange()
    },
    ClubType.putter: {
      'launchAngle': (1.0, 6.0),
      'spinRate': (0.0, 500.0),
      'smashFactor': (1.0, 1.8),
    },
  };

  /// Returns the optimal spin rate range for an iron based on club number.
  /// Rule of thumb: ~1,000 rpm × club number (±500 rpm window).
  static (double, double) _ironSpinRange(String? clubId) {
    final number = _extractClubNumber(clubId);
    if (number == null) return (5000.0, 7500.0); // safe fallback
    final target = number * 1000.0;
    return (target - 500, target + 500);
  }

  /// Returns the optimal spin rate range for wedges.
  /// PW ~10,000, GW/SW/LW higher. Degree wedges scale with loft.
  static (double, double) _wedgeSpinRange(String? clubId) {
    if (clubId == null) return (8500.0, 11000.0);
    return switch (clubId) {
      'pw' => (8500.0, 10500.0),
      'gw' => (9000.0, 11000.0),
      'sw' => (9500.0, 11500.0),
      'lw' => (10000.0, 12000.0),
      _ => (8500.0, 11000.0), // degree wedges
    };
  }

  /// Main lookup — returns the optimal range for a metric given club context.
  static (double, double) getRange(
    ClubType clubType,
    String metric, {
    double? clubSpeed,
    String? clubId,
  }) {
    // Driver uses speed-aware windows.
    if (clubId == 'dr' || (clubType == ClubType.wood && clubId == 'dr')) {
      final band = _driverSpeedBand(clubSpeed ?? 95.0);
      final bandRanges = _driverBySpeed[band]!;
      if (bandRanges.containsKey(metric)) return bandRanges[metric]!;
    }

    // Iron spin rate uses club-number rule.
    if (clubType == ClubType.iron && metric == 'spinRate') {
      return _ironSpinRange(clubId);
    }

    // Wedge spin rate.
    if (clubType == ClubType.wedge && metric == 'spinRate') {
      return _wedgeSpinRange(clubId);
    }

    final clubRanges = _flat[clubType] ?? _flat[ClubType.iron]!;
    return clubRanges[metric] ?? (0.0, 1000.0);
  }

  /// Extracts the numeric prefix from a club id (e.g. '7i' → 7, '3w' → 3).
  static int? _extractClubNumber(String? clubId) {
    if (clubId == null) return null;
    final match = RegExp(r'^(\d+)').firstMatch(clubId);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

// ── Engine ────────────────────────────────────────────────────────────────────

class ShotOptimizer {
  ShotAnalysis analyze(ShotData shot, ClubType clubType, {String? clubId}) {
    final diagnostics = _generateDiagnostics(shot, clubType, clubId);
    final recommendations = _generateRecommendations(diagnostics, shot, clubType);

    // Estimate optimal carry and gap.
    final optimalCarry = _estimateOptimalCarry(shot, clubType);
    final carryGap =
        optimalCarry != null ? (optimalCarry - shot.carry).clamp(0.0, 999.0) : null;

    final summary = _generateSummary(diagnostics, recommendations, carryGap);
    return ShotAnalysis(
      shot: shot,
      diagnostics: diagnostics,
      recommendations: recommendations,
      summary: summary,
      optimalCarry: optimalCarry,
      carryGap: carryGap != null && carryGap > 0 ? carryGap : null,
    );
  }

  // ── Diagnostics ──────────────────────────────────────────────────────────

  List<Diagnostic> _generateDiagnostics(
    ShotData shot,
    ClubType clubType,
    String? clubId,
  ) {
    if (clubType == ClubType.putter) return []; // putts don't get optimized
    final diagnostics = <Diagnostic>[];
    final speed = shot.clubSpeed;

    // ── Tier 1: Energy transfer (smash factor) ──
    final smash = shot.smashFactor;
    final (smashMin, smashMax) = OptimalRanges.getRange(
      clubType, 'smashFactor', clubSpeed: speed, clubId: clubId,
    );
    if (smash > 0 && (smash < smashMin || smash > smashMax)) {
      final yardsLost = smash < smashMin ? (smashMin - smash) * 50.0 : 0.0;
      diagnostics.add(Diagnostic(
        metric: 'smashFactor',
        measured: smash,
        minOptimal: smashMin,
        maxOptimal: smashMax,
        severity: smash < smashMin ? 'critical' : 'low',
        estimatedYardsLost: yardsLost > 0 ? yardsLost : null,
        possibleRootCauses: smash < smashMin
            ? [
                'ball_contact_off_center',
                'dirty_club_face',
                'ball_compression_mismatch',
              ]
            : ['unusually_high_efficiency'],
      ));
    }

    // ── Tier 2: Launch conditions ──
    final (launchMin, launchMax) = OptimalRanges.getRange(
      clubType, 'launchAngle', clubSpeed: speed, clubId: clubId,
    );
    if (shot.launchAngle < launchMin || shot.launchAngle > launchMax) {
      final isLow = shot.launchAngle < launchMin;
      final deviation = isLow
          ? launchMin - shot.launchAngle
          : shot.launchAngle - launchMax;
      // Rough estimate: ~2 yards lost per degree off optimal.
      final yardsLost = deviation * 2.0;
      final severity = deviation > 5.0
          ? 'critical'
          : deviation > 3.0
              ? 'high'
              : 'medium';
      diagnostics.add(Diagnostic(
        metric: 'launchAngle',
        measured: shot.launchAngle,
        minOptimal: launchMin,
        maxOptimal: launchMax,
        severity: severity,
        estimatedYardsLost: yardsLost,
        possibleRootCauses: isLow
            ? [
                'low_dynamic_loft',
                'low_impact_point',
                'static_loft_too_low',
                'excessive_shaft_lag',
              ]
            : [
                'high_dynamic_loft',
                'high_impact_point',
                'static_loft_too_high',
              ],
      ));
    }

    // ── Tier 2: Spin rate ──
    final (spinMin, spinMax) = OptimalRanges.getRange(
      clubType, 'spinRate', clubSpeed: speed, clubId: clubId,
    );
    if (shot.spinRate < spinMin || shot.spinRate > spinMax) {
      final isLow = shot.spinRate < spinMin;
      final deviation = isLow
          ? (spinMin - shot.spinRate) / spinMin
          : (shot.spinRate - spinMax) / spinMax;
      // Only flag if deviation is > 10% outside the window.
      if (deviation > 0.10) {
        final severity = deviation > 0.25
            ? 'critical'
            : deviation > 0.15
                ? 'high'
                : 'medium';
        diagnostics.add(Diagnostic(
          metric: 'spinRate',
          measured: shot.spinRate,
          minOptimal: spinMin,
          maxOptimal: spinMax,
          severity: severity,
          possibleRootCauses: isLow
              ? [
                  'low_impact_point_gear_effect',
                  'club_face_condition',
                  'low_spin_loft',
                ]
              : [
                  'high_impact_point',
                  'excessive_spin_loft',
                  'shaft_too_flexible',
                ],
        ));
      }
    }

    // ── Tier 2: Spin loft relationship (if data available) ──
    if (shot.dynamicLoft != null && shot.angleOfAttack != null) {
      final spinLoft = shot.dynamicLoft! - shot.angleOfAttack!;
      // Predict expected spin from spin loft and speed.
      final expectedSpin = _predictSpinFromSpinLoft(spinLoft, speed, clubType);
      final spinDeviation = (shot.spinRate - expectedSpin).abs();
      if (spinDeviation > expectedSpin * 0.15) {
        diagnostics.add(Diagnostic(
          metric: 'spinLoftMismatch',
          measured: shot.spinRate,
          minOptimal: expectedSpin * 0.85,
          maxOptimal: expectedSpin * 1.15,
          severity: 'medium',
          possibleRootCauses: [
            'shaft_lag_inconsistency',
            'wrist_hinge_variation',
            'gear_effect_from_impact_location',
          ],
        ));
      }
    }

    // ── Tier 3: Delivery — path-face alignment ──
    if (shot.swingPath != null && shot.faceAngle != null) {
      final diff = (shot.swingPath! - shot.faceAngle!).abs();
      if (diff > 5.0) {
        diagnostics.add(Diagnostic(
          metric: 'pathFaceAngleAlignment',
          measured: diff,
          minOptimal: 0.0,
          maxOptimal: 5.0,
          severity: diff > 10.0 ? 'critical' : 'high',
          estimatedYardsLost: diff * 1.5,
          possibleRootCauses: [
            'poor_swing_path',
            'face_control_inconsistent',
            'alignment_issue',
          ],
        ));
      }
    }

    // ── Tier 3: Attack angle (if available) ──
    if (shot.angleOfAttack != null) {
      final aoa = shot.angleOfAttack!;
      final isDriver = clubId == 'dr';
      if (isDriver && aoa < 0) {
        diagnostics.add(Diagnostic(
          metric: 'attackAngle',
          measured: aoa,
          minOptimal: 3.0,
          maxOptimal: 5.0,
          severity: aoa < -3 ? 'high' : 'medium',
          estimatedYardsLost: aoa.abs() * 2.0,
          possibleRootCauses: [
            'hitting_down_on_driver',
            'ball_position_too_far_back',
            'excessive_forward_shaft_lean',
          ],
        ));
      } else if (clubType == ClubType.iron) {
        // Irons should be -4 to -5 (compressing). Flag extremes.
        if (aoa > -2 || aoa < -7) {
          diagnostics.add(Diagnostic(
            metric: 'attackAngle',
            measured: aoa,
            minOptimal: -5.0, // more negative = deeper
            maxOptimal: -2.0, // shallow end
            severity: 'medium',
            possibleRootCauses: aoa > -2
                ? ['picking_the_ball', 'ball_position_too_far_forward']
                : ['digging', 'ball_position_too_far_back'],
          ));
        }
      }
    }

    // ── Tier 4: Impact location ──
    if (shot.horizontalImpact != null && shot.verticalImpact != null) {
      final impactMm = math.sqrt(
        shot.horizontalImpact! * shot.horizontalImpact! +
            shot.verticalImpact! * shot.verticalImpact!,
      );
      final impactInches = impactMm / 25.4;
      // Only flag significant off-center (> 0.5"), ignore minor variance.
      if (impactInches > 0.5) {
        diagnostics.add(Diagnostic(
          metric: 'impactLocation',
          measured: impactInches,
          minOptimal: 0.0,
          maxOptimal: 0.5,
          severity: impactInches > 0.75 ? 'high' : 'medium',
          estimatedYardsLost: impactInches * 5.0,
          possibleRootCauses: [
            'inconsistent_strike_location',
            'swing_path_issue',
            'setup_misalignment',
          ],
        ));
      }
    }

    // Sort by tier: critical → high → medium → low.
    diagnostics.sort((a, b) => _severityRank(a.severity)
        .compareTo(_severityRank(b.severity)));

    return diagnostics;
  }

  static int _severityRank(String severity) => switch (severity) {
        'critical' => 0,
        'high' => 1,
        'medium' => 2,
        'low' => 3,
        _ => 4,
      };

  /// Rough spin prediction from spin loft and club speed.
  double _predictSpinFromSpinLoft(
    double spinLoft,
    double clubSpeed,
    ClubType clubType,
  ) {
    // Approximate: spin ≈ spinLoft × speedFactor.
    // For irons at ~85 mph, 19° spin loft ≈ 6,500 rpm → factor ≈ 342.
    // For driver at ~100 mph, 14° spin loft ≈ 2,600 rpm → factor ≈ 186.
    final factor = switch (clubType) {
      ClubType.wood || ClubType.miniDriver => 186.0,
      ClubType.hybrid => 250.0,
      ClubType.iron => 342.0,
      ClubType.wedge => 380.0,
      ClubType.putter => 100.0,
    };
    return spinLoft * factor;
  }

  /// Estimate optimal carry for the given swing speed and club type.
  double? _estimateOptimalCarry(ShotData shot, ClubType clubType) {
    final speed = shot.clubSpeed;
    if (speed <= 0) return null;
    // Rough multipliers derived from tour data (carry per mph of club speed).
    final yardPerMph = switch (clubType) {
      ClubType.wood || ClubType.miniDriver => 2.6, // ~100 mph → ~260 yds
      ClubType.hybrid => 2.2,
      ClubType.iron => 1.9,     // ~85 mph → ~162 yds
      ClubType.wedge => 1.4,
      ClubType.putter => 0.0,
    };
    return speed * yardPerMph;
  }

  // ── Recommendations ──────────────────────────────────────────────────────

  List<Recommendation> _generateRecommendations(
    List<Diagnostic> diagnostics,
    ShotData shot,
    ClubType clubType,
  ) {
    final recommendations = <Recommendation>[];

    for (final diag in diagnostics) {
      switch (diag.metric) {
        case 'smashFactor':
          if (diag.measured < diag.minOptimal) {
            recommendations.add(Recommendation(
              action: 'improve_center_contact',
              description:
                  'Off-center contact is reducing ball speed. Focus on center-face strikes for immediate distance gain.',
              affectedMetrics: ['ballSpeed', 'carryDistance', 'smashFactor'],
              priority: 1,
              expectedGainYards: diag.estimatedYardsLost,
            ));
          }

        case 'launchAngle':
          if (shot.launchAngle < diag.minOptimal) {
            recommendations.add(Recommendation(
              action: 'raise_dynamic_loft',
              description:
                  'Launch angle too low for your swing speed. Raise impact point on the face, or check static loft and shaft lag.',
              affectedMetrics: ['launchAngle', 'apex', 'carryDistance'],
              priority: 1,
              expectedGainYards: diag.estimatedYardsLost,
            ));
          } else if (shot.launchAngle > diag.maxOptimal) {
            recommendations.add(Recommendation(
              action: 'lower_dynamic_loft',
              description:
                  'Launch too high — losing distance to ballooning. Lower impact point or check static loft.',
              affectedMetrics: ['launchAngle', 'carryDistance'],
              priority: 1,
              expectedGainYards: diag.estimatedYardsLost,
            ));
          }

        case 'spinRate':
          if (shot.spinRate > diag.maxOptimal) {
            recommendations.add(Recommendation(
              action: 'reduce_spin',
              description: clubType == ClubType.wood || clubType == ClubType.miniDriver
                  ? 'Excessive spin killing carry distance. Strike lower on the face or consider a lower loft.'
                  : 'Spin above optimal window — check for high impact point or excessive spin loft.',
              affectedMetrics: ['spinRate', 'carryDistance'],
              priority: 2,
              expectedGainYards: diag.estimatedYardsLost,
            ));
          } else if (shot.spinRate < diag.minOptimal) {
            recommendations.add(Recommendation(
              action: 'increase_spin',
              description:
                  'Spin below optimal — reduced stopping power. Check face condition and impact location.',
              affectedMetrics: ['spinRate', 'carryDistance'],
              priority: 2,
              expectedGainYards: diag.estimatedYardsLost,
            ));
          }

        case 'pathFaceAngleAlignment':
          recommendations.add(Recommendation(
            action: 'improve_face_path_alignment',
            description:
                'Club path and face angle misaligned by ${diag.measured.toStringAsFixed(1)}°. '
                'Work on path consistency and face control.',
            affectedMetrics: ['launchDirection', 'carryDistance'],
            priority: 2,
            expectedGainYards: diag.estimatedYardsLost,
          ));

        case 'attackAngle':
          if (diag.measured < 0 && (clubType == ClubType.wood || clubType == ClubType.miniDriver)) {
            recommendations.add(Recommendation(
              action: 'hit_up_on_driver',
              description:
                  'Hitting down on the driver loses carry. Move ball position forward and tee higher.',
              affectedMetrics: ['attackAngle', 'launchAngle', 'carryDistance'],
              priority: 2,
              expectedGainYards: diag.estimatedYardsLost,
            ));
          }

        case 'impactLocation':
          recommendations.add(Recommendation(
            action: 'optimize_strike_location',
            description:
                'Off-center by ${diag.measured.toStringAsFixed(1)}" — introduces gear effect and '
                'reduces energy transfer.',
            affectedMetrics: ['ballSpeed', 'spinRate', 'carryDistance'],
            priority: 1,
            expectedGainYards: diag.estimatedYardsLost,
          ));
      }
    }

    // Deduplicate and sort by priority.
    final seen = <String>{};
    return recommendations.where((r) => seen.add(r.action)).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  // ── Summary ──────────────────────────────────────────────────────────────

  String _generateSummary(
    List<Diagnostic> diagnostics,
    List<Recommendation> recommendations,
    double? carryGap,
  ) {
    final critical = diagnostics.where((d) => d.severity == 'critical').length;
    final outOfRange = diagnostics.where((d) => d.isOutOfRange).length;

    final gapStr = carryGap != null && carryGap > 1.0
        ? ' Potential gain: ${carryGap.toStringAsFixed(0)} yards.'
        : '';

    if (critical > 0) {
      return 'Critical efficiency losses ($critical ${critical == 1 ? 'issue' : 'issues'}). '
          'Priority: ${recommendations.take(2).map((r) => _humanize(r.action)).join(', ')}.$gapStr';
    } else if (outOfRange > 0) {
      return '$outOfRange ${outOfRange == 1 ? 'metric' : 'metrics'} outside optimal window. '
          'Focus: ${recommendations.isNotEmpty ? _humanize(recommendations.first.action) : 'consistency'}.$gapStr';
    }
    return 'Shot within optimal parameters — efficient delivery.';
  }

  static String _humanize(String action) => action.replaceAll('_', ' ');
}
