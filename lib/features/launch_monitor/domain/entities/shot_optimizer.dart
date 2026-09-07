import 'dart:math' as math;

import 'shot_context.dart';
import 'shot_trajectory.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

// ── Severity ─────────────────────────────────────────────────────────────────

/// Ordered most → least severe so [Severity.index] doubles as a sort rank.
enum Severity { critical, high, medium, low }

// ── Diagnostic ───────────────────────────────────────────────────────────────

class Diagnostic {
  final String metric;
  final double measured;
  final double minOptimal;
  final double maxOptimal;
  final Severity severity;
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
  final bool assessed;
  final List<String> limitations;

  const ShotAnalysis({
    required this.shot,
    required this.diagnostics,
    required this.recommendations,
    required this.summary,
    this.optimalCarry,
    this.carryGap,
    this.assessed = true,
    this.limitations = const [],
  });

  List<Diagnostic> get criticalIssues =>
      diagnostics.where((d) => d.severity == Severity.critical).toList();

  List<Diagnostic> get outOfRangeMetrics =>
      diagnostics.where((d) => d.isOutOfRange).toList();
}

// Broad starting references, not individual fitting prescriptions. The
// independent validation fixtures and calibration policy live in docs.
class OptimalRanges {
  static (double, double) getRange(
    ClubType clubType,
    String metric, {
    double? clubSpeed,
    String? clubId,
  }) {
    final number = int.tryParse(
      RegExp(r'^\d+').stringMatch(clubId ?? '') ?? '',
    );
    if (clubId == 'dr' || clubType == ClubType.miniDriver) {
      final t = (((clubSpeed ?? 95) - 75) / 40).clamp(0.0, 1.0);
      return switch (metric) {
        'launchAngle' => (13 - 4 * t, 20 - 4 * t),
        'spinRate' => (2400 - 600 * t, 4000 - 800 * t),
        'smashFactor' => (1.40, 1.53),
        _ => (0, 1000),
      };
    }
    if (clubType == ClubType.iron) {
      final n = (number ?? 7).clamp(1, 9);
      final launch = 9.0 + math.max(0, n - 2) * 1.8;
      final spin = 4500.0 + math.max(0, n - 3) * 700;
      final smash = 1.47 - (n - 3).clamp(0, 6) * .027;
      return switch (metric) {
        'launchAngle' => (launch - 4, launch + 5),
        'spinRate' => (spin * .72, spin * 1.22),
        'smashFactor' => (smash - .09, smash + .07),
        _ => (0, 1000),
      };
    }
    if (clubType == ClubType.wedge) {
      final loft = (clubId?.endsWith('deg') ?? false)
          ? (number ?? 54).toDouble()
          : switch (clubId) {
              'pw' => 46.0,
              'gw' => 50.0,
              'sw' => 56.0,
              'lw' => 60.0,
              _ => 54.0,
            };
      final smash = 1.25 - (loft - 46) * .012;
      // Stock shots only. Partial wedges never use these windows.
      return switch (metric) {
        'launchAngle' => (loft * .5 - 5, loft * .5 + 9),
        'spinRate' => (6500.0, 12000.0),
        'smashFactor' => (smash - .12, smash + .12),
        _ => (0, 1000),
      };
    }
    final n = (number ?? 3).clamp(1, 11);
    final isWood = clubType == ClubType.wood;
    final spin = (isWood ? 3300.0 : 4000.0) + (n - 3) * 350;
    return switch (metric) {
      'launchAngle' => (7.0 + n * .5, 17.0 + n * .9),
      'spinRate' => (spin * .72, spin * 1.3),
      'smashFactor' => (isWood ? 1.34 : 1.25, 1.55),
      _ => (0, 1000),
    };
  }
}

class ShotOptimizer {
  // Each immutable shot is evaluated once per resolved club context, including
  // in the session summary. Weak keys don't retain discarded sessions.
  final _cache = Expando<Map<String, ShotAnalysis>>('optimizer');

  ShotAnalysis analyze(ShotData shot, ClubType clubType, {String? clubId}) {
    final id = clubId ?? shot.clubId;
    final key = '${clubType.name}:$id';
    final entries = _cache[shot] ??= {};
    return entries.putIfAbsent(key, () => _analyze(shot, clubType, id));
  }

  ShotAnalysis _analyze(ShotData shot, ClubType type, String? id) {
    ShotAnalysis unavailable(String reason) => ShotAnalysis(
      shot: shot,
      diagnostics: const [],
      recommendations: const [],
      summary: reason,
      assessed: false,
    );
    if (type == ClubType.putter) {
      return unavailable('Putting is outside this optimiser.');
    }
    if (!shot.hasUsableLaunch) {
      return unavailable(
        'Launch measurements are unavailable or unverified. No efficiency assessment.',
      );
    }
    if (shot.trajectory.failure != null) {
      return unavailable(
        'The flight model could not resolve this shot. No distance assessment.',
      );
    }

    final limitations = <String>[
      'Carry, landing and potential gains are modelled; reference windows are provisional.',
      if (!shot.hasMeasuredClubSpeed)
        'Club speed is not verified: contact efficiency is not assessed.',
      if (shot.context.ballSource == MeasurementSource.simulated)
        'Simulated shot: excluded from fitting evidence.',
      if (id == null)
        'No club selected: club-specific feedback is unavailable.',
      if (shot.context.intent == ShotIntent.unknown)
        'Shot intent is unknown: stock-shot targets are not applied.',
    ];
    final diagnostics = <Diagnostic>[];
    final recommendations = <Recommendation>[];
    void add(
      String metric,
      double value,
      double lo,
      double hi,
      Severity severity,
      String cause,
      String action,
      String advice, {
      int priority = 2,
    }) {
      diagnostics.add(
        Diagnostic(
          metric: metric,
          measured: value,
          minOptimal: lo,
          maxOptimal: hi,
          severity: severity,
          possibleRootCauses: [cause],
        ),
      );
      recommendations.add(
        Recommendation(
          action: action,
          description: advice,
          affectedMetrics: [metric],
          priority: priority,
        ),
      );
    }

    bool valid(double? v) => v != null && v.isFinite;
    final stock = id != null && shot.context.intent == ShotIntent.stock;
    final driver = id == 'dr' || type == ClubType.miniDriver;
    final speed = shot.hasMeasuredClubSpeed ? shot.clubSpeed : null;
    (double, double) range(String metric) =>
        OptimalRanges.getRange(type, metric, clubId: id, clubSpeed: speed);

    final impact = valid(shot.horizontalImpact) && valid(shot.verticalImpact)
        ? math.sqrt(
            math.pow(shot.horizontalImpact!, 2) +
                math.pow(shot.verticalImpact!, 2),
          )
        : null;
    final (smashMin, smashMax) = range('smashFactor');
    final smash = shot.smashFactor;
    final lowSmash =
        stock &&
        shot.hasMeasuredClubSpeed &&
        smash.isFinite &&
        smash > 0 &&
        smash < smashMin;
    // One contact action: impact and smash are evidence of the same possible
    // loss, not two additive distance penalties.
    if (lowSmash || (impact != null && impact > 15)) {
      final deficit = lowSmash ? (smashMin - smash) / smashMin : 0.0;
      add(
        lowSmash ? 'smashFactor' : 'impactLocation',
        lowSmash ? smash : impact! / 25.4,
        lowSmash ? smashMin : 0,
        lowSmash ? smashMax : 15 / 25.4,
        deficit > .2
            ? Severity.critical
            : deficit > .1
            ? Severity.high
            : Severity.medium,
        impact != null && impact > 15
            ? 'measured_off_center_contact'
            : 'contact_or_delivered_loft',
        'check_contact',
        impact != null && impact > 15
            ? 'Impact was away from face centre. Check the strike pattern across several shots before changing equipment.'
            : 'Ball speed is below the stock-shot reference for this club speed. Check contact and delivered loft; low smash alone does not prove a mishit.',
        priority: deficit > .1 ? 1 : 2,
      );
    } else if (stock && shot.hasMeasuredClubSpeed && smash > smashMax) {
      add(
        'smashFactor',
        smash,
        smashMin,
        smashMax,
        Severity.low,
        'check_speed_measurement',
        'verify_speed',
        'The speed ratio is unusually high. Verify the club-speed reading before making fitting decisions.',
        priority: 3,
      );
    }

    // Independent launch/spin penalties are intentionally absent for drivers.
    // Compare joint changes at unchanged ball speed, direction and spin axis.
    double? optimalCarry;
    double? carryGap;
    if (stock &&
        driver &&
        shot.context.goal == FittingGoal.carry &&
        shot.ballSpeed >= 70) {
      final best = _searchDriver(shot);
      final gain = best.$1 - shot.carry;
      optimalCarry = best.$1;
      if (gain >= 3) {
        carryGap = gain;
        add(
          'launchConditions',
          shot.carry,
          best.$1 - 3,
          best.$1,
          gain / math.max(shot.carry, 1) > .12
              ? Severity.high
              : Severity.medium,
          'launch_and_spin_combination',
          'test_launch_spin',
          'At unchanged ball speed, the model favours approximately ${best.$2.toStringAsFixed(1)}° launch and ${best.$3.toStringAsFixed(0)} rpm. Test nearby combinations and retain direction and strike quality. This is an estimate, not a prescribed equipment change.',
        );
      }
    } else if (stock) {
      final (launchMin, launchMax) = range('launchAngle');
      final (spinMin, spinMax) = range('spinRate');
      if (shot.launchAngle < launchMin || shot.launchAngle > launchMax) {
        add(
          'launchAngle',
          shot.launchAngle,
          launchMin,
          launchMax,
          Severity.medium,
          'trajectory_outside_reference',
          'review_trajectory',
          'Launch is outside the broad stock-shot reference. Check carry, landing angle and your intended trajectory before changing delivered loft.',
        );
      }
      if (shot.spinRate < spinMin * .9 || shot.spinRate > spinMax * 1.1) {
        final high = shot.spinRate > spinMax;
        final lowFace = valid(shot.verticalImpact) && shot.verticalImpact! < -5;
        add(
          'spinRate',
          shot.spinRate,
          spinMin,
          spinMax,
          Severity.medium,
          driver && high && lowFace
              ? 'low_face_contact_can_add_spin'
              : 'spin_loft_friction_or_contact',
          'review_spin',
          driver && high
              ? 'High spin can accompany low-face contact. Check measured strike location first; striking lower can add spin. Compare launch and carry together.'
              : 'Spin is outside the stock-shot reference. Check face condition, speed, strike and landing behaviour before trying to change spin.',
        );
      }
    }

    // No spin-loft-to-rpm diagnosis: the previous formula ignored speed and
    // friction. Displaying an uncalibrated residual as a swing fault is unsafe.
    // AoA is supporting context only; do not prescribe a swing change from it.
    if (stock &&
        driver &&
        carryGap != null &&
        valid(shot.angleOfAttack) &&
        shot.angleOfAttack! < -3) {
      add(
        'attackAngle',
        shot.angleOfAttack!,
        -3,
        6,
        Severity.low,
        'descending_tee_delivery',
        'review_tee_delivery',
        'If this was teed, compare a more upward delivery with your current swing. Keep the change only if launch, contact and dispersion improve.',
        priority: 3,
      );
    }

    final tolerance =
        shot.context.offlineTolerance.isFinite &&
            shot.context.offlineTolerance > 0
        ? shot.context.offlineTolerance
        : 20.0;
    final startLimit =
        math.atan(tolerance / math.max(shot.carry, 20)) * 180 / math.pi;
    if (shot.launchDirection.abs() > startLimit) {
      add(
        'launchDirection',
        shot.launchDirection,
        -startLimit,
        startLimit,
        Severity.medium,
        'start_line_outside_target_window',
        'review_start_line',
        'The ball started ${shot.launchDirection > 0 ? 'right' : 'left'} of the target window. Check alignment and face direction; allow for an intentional shot shape.',
      );
    }
    if (shot.lateralOffset.abs() > tolerance) {
      add(
        'lateralOffset',
        shot.lateralOffset,
        -tolerance,
        tolerance,
        Severity.high,
        'modelled_target_miss',
        'review_direction',
        'The modelled landing point is ${shot.lateralOffset > 0 ? 'right' : 'left'} of your target corridor. Compare start line and curvature across several shots.',
        priority: 1,
      );
      if (valid(shot.swingPath) && valid(shot.faceAngle)) {
        final signed = ((shot.faceAngle! - shot.swingPath! + 180) % 360) - 180;
        if (signed.abs() > 5) {
          add(
            'pathFaceAngleAlignment',
            signed,
            -5,
            5,
            Severity.medium,
            'face_to_path_with_target_miss',
            'review_face_path',
            'Face-to-path is ${signed.toStringAsFixed(1)}°. Compare it with measured spin axis and strike before attributing the miss to delivery.',
          );
        }
      }
    }
    if (shot.context.goal == FittingGoal.approach) {
      final target = shot.context.targetCarry;
      if (target != null && target.isFinite && target > 0) {
        final band = math.max(3.0, target * .05);
        if ((shot.carry - target).abs() > band) {
          add(
            'carryDistance',
            shot.carry,
            target - band,
            target + band,
            Severity.medium,
            'modelled_distance_error',
            'review_distance_control',
            'Carry is outside your target window. Compare distance control using the same club and shot intent.',
          );
        }
      }
      final minimum = shot.context.minimumDescent;
      if (minimum.isFinite && minimum > 0 && shot.descentAngle < minimum) {
        add(
          'descentAngle',
          shot.descentAngle,
          minimum,
          90,
          Severity.medium,
          'shallow_modelled_landing',
          'review_stopping',
          'The modelled landing angle is below your chosen minimum. Consider landing speed, spin and the actual green; extra carry alone may not help.',
        );
      }
    }
    diagnostics.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    recommendations.sort((a, b) {
      final order = a.priority.compareTo(b.priority);
      return order != 0 ? order : a.action.compareTo(b.action);
    });
    return ShotAnalysis(
      shot: shot,
      diagnostics: diagnostics,
      recommendations: recommendations,
      optimalCarry: optimalCarry,
      carryGap: carryGap,
      limitations: limitations,
      summary: diagnostics.isEmpty
          ? 'No concerns found in the available checks. This is not a complete fitting assessment.'
          : '${diagnostics.length} ${diagnostics.length == 1 ? 'finding' : 'findings'} to review against your shot intent.',
    );
  }

  /// Bounded, cached search (at most 65 flights). Never change ball speed or
  /// remove curvature to manufacture a gain. The bounds are provisional and
  /// this result is not used as independent fitting evidence.
  (double, double, double) _searchDriver(ShotData shot) {
    var best = (shot.carry, shot.launchAngle, shot.spinRate);
    void check(double launch, double spin) {
      if (launch < 8 || launch > 22 || spin < 1800 || spin > 4200) return;
      final flight = BallFlightModel.standard.simulate(
        ballSpeedMph: shot.ballSpeed,
        launchAngleDeg: launch,
        launchDirectionDeg: shot.launchDirection,
        spinRpm: spin,
        spinAxisDeg: shot.spinAxis,
      );
      if (flight.failure == null && flight.carry > best.$1) {
        best = (flight.carry, launch, spin);
      }
    }

    for (double launch = 8; launch <= 22; launch += 2) {
      for (double spin = 1800; spin <= 4200; spin += 400) {
        check(launch, spin);
      }
    }
    final coarse = best;
    for (final dl in [-1.0, 0.0, 1.0]) {
      for (final ds in [-200.0, 0.0, 200.0]) {
        check(coarse.$2 + dl, coarse.$3 + ds);
      }
    }
    return best;
  }
}
