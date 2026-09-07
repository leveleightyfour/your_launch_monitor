import 'dart:math' as math;

import 'shot_context.dart';
import 'shot_data.dart';

class FittingStats {
  final int count;
  final double carry;
  final double carrySd;
  final double absoluteOffline;
  final double descent;
  final double landingSpeed;
  final double landingSpin;
  final double objectiveLoss;
  final double objectiveVariance;
  final double offlineVariance;
  final double carryVariance;
  final double stoppingFraction;
  const FittingStats({
    required this.count,
    required this.carry,
    required this.carrySd,
    required this.absoluteOffline,
    required this.descent,
    required this.landingSpeed,
    required this.landingSpin,
    required this.objectiveLoss,
    required this.objectiveVariance,
    required this.offlineVariance,
    required this.carryVariance,
    required this.stoppingFraction,
  });

  factory FittingStats.fromShots(List<ShotData> shots, ShotContext context) {
    final carries = shots.map((s) => s.carry).toList();
    final offline = shots.map((s) => s.lateralOffset.abs()).toList();
    final losses = shots
        .map(
          (s) => switch (context.goal) {
            FittingGoal.carry => -s.carry,
            FittingGoal.accuracy => s.lateralOffset.abs(),
            FittingGoal.approach => math.sqrt(
              math.pow(s.carry - context.targetCarry!, 2) +
                  math.pow(s.lateralOffset, 2),
            ),
          },
        )
        .toList();
    return FittingStats(
      count: shots.length,
      carry: _mean(carries),
      carrySd: math.sqrt(_variance(carries)),
      absoluteOffline: _mean(offline),
      descent: _mean(shots.map((s) => s.descentAngle).toList()),
      landingSpeed: _mean(shots.map((s) => s.trajectory.landingSpeed).toList()),
      landingSpin: _mean(shots.map((s) => s.trajectory.landingSpin).toList()),
      objectiveLoss: _mean(losses),
      objectiveVariance: _variance(losses),
      offlineVariance: _variance(offline),
      carryVariance: _variance(carries),
      stoppingFraction:
          shots.where((s) => s.descentAngle >= context.minimumDescent).length /
          shots.length,
    );
  }
}

double _mean(List<double> x) => x.reduce((a, b) => a + b) / x.length;
double _variance(List<double> x) {
  if (x.length < 2) return 0;
  final mean = _mean(x);
  return x.fold(0.0, (s, v) => s + math.pow(v - mean, 2)) / (x.length - 1);
}

class FittingRound {
  final FittingStats? baseline;
  final FittingStats? candidate;
  final int excluded;
  final int switches;
  final double? improvement;
  final double? margin;
  final bool enoughEvidence;
  final bool favourable;
  final String message;
  const FittingRound({
    this.baseline,
    this.candidate,
    required this.excluded,
    required this.switches,
    this.improvement,
    this.margin,
    this.enoughEvidence = false,
    this.favourable = false,
    required this.message,
  });
}

class FittingComparison {
  final ShotContext? context;
  final EquipmentSetup? baselineSetup;
  final EquipmentSetup? candidateSetup;
  final FittingRound comparison;
  final FittingRound confirmation;
  final String? incompatibility;
  const FittingComparison({
    this.context,
    this.baselineSetup,
    this.candidateSetup,
    required this.comparison,
    required this.confirmation,
    this.incompatibility,
  });
  String get verdict {
    if (incompatibility != null) return incompatibility!;
    if (!comparison.enoughEvidence) return comparison.message;
    if (!comparison.favourable) return comparison.message;
    if (!confirmation.enoughEvidence) {
      return 'Promising comparison. Collect a separate confirmation round with both setups.';
    }
    if (!confirmation.favourable) {
      return 'The advantage was not confirmed. Keep both setups under consideration.';
    }
    return 'Candidate advantage repeated in both rounds under these test conditions. Confirm actual flight, turf performance and feel before choosing the fit.';
  }
}

/// Compares actual tested setups, never infers an untested shaft or head.
/// Input can be chronological or reverse chronological (session lists use
/// both); alternation counts are unchanged by reversal.
FittingComparison compareFitting(List<ShotData> allShots, String trialId) {
  final shots = allShots.where((s) => s.context.trialId == trialId).toList();
  const empty = FittingRound(
    excluded: 0,
    switches: 0,
    message: 'Collect shots with both setups.',
  );
  if (shots.isEmpty) {
    return const FittingComparison(comparison: empty, confirmation: empty);
  }
  final context = shots.first.context;
  String protocol(ShotData s) =>
      '${s.clubId}|${s.context.intent.name}|${s.context.goal.name}|'
      '${s.context.targetCarry}|${s.context.offlineTolerance}|${s.context.minimumDescent}|${s.context.conditions}';
  final setups = <bool, EquipmentSetup>{};
  String? incompatibility;
  for (final s in shots) {
    if (protocol(s) != protocol(shots.first) ||
        s.clubId == null ||
        s.clubId == 'pt' ||
        s.context.intent == ShotIntent.unknown ||
        s.context.equipment == null) {
      incompatibility =
          'Shots have incompatible clubs, intent or test conditions. Start a new comparison.';
      break;
    }
    final previous = setups[s.context.candidate];
    if (previous != null &&
        previous.toJson().toString() !=
            s.context.equipment!.toJson().toString()) {
      incompatibility =
          'Equipment changed within a setup. Start a new comparison for the changed specifications.';
      break;
    }
    setups[s.context.candidate] = s.context.equipment!;
  }
  if (!context.offlineTolerance.isFinite ||
      context.offlineTolerance <= 0 ||
      !context.minimumDescent.isFinite ||
      context.minimumDescent <= 0 ||
      context.minimumDescent >= 90 ||
      (context.goal == FittingGoal.approach &&
          (context.targetCarry == null ||
              !context.targetCarry!.isFinite ||
              context.targetCarry! <= 0))) {
    incompatibility = 'Set a valid target and tolerances before comparing.';
  }
  if (incompatibility != null) {
    return FittingComparison(
      context: context,
      comparison: empty,
      confirmation: empty,
      incompatibility: incompatibility,
    );
  }

  FittingRound round(FittingPhase phase) {
    final phaseShots = shots.where((s) => s.context.phase == phase).toList();
    final valid = phaseShots
        .where(
          (s) =>
              s.context.ballSource == MeasurementSource.measured &&
              s.hasUsableLaunch &&
              s.trajectory.failure == null,
        )
        .toList();
    final a = valid.where((s) => !s.context.candidate).toList();
    final b = valid.where((s) => s.context.candidate).toList();
    final baseline = a.isEmpty ? null : FittingStats.fromShots(a, context);
    final candidate = b.isEmpty ? null : FittingStats.fromShots(b, context);
    var switches = 0;
    for (var i = 1; i < valid.length; i++) {
      if (valid[i].context.candidate != valid[i - 1].context.candidate) {
        switches++;
      }
    }
    FittingRound result(
      String message, {
      double? improvement,
      double? margin,
      bool enough = false,
      bool favourable = false,
    }) => FittingRound(
      baseline: baseline,
      candidate: candidate,
      switches: switches,
      excluded: phaseShots.length - valid.length,
      improvement: improvement,
      margin: margin,
      enoughEvidence: enough,
      favourable: favourable,
      message: message,
    );
    if (a.length < 10 || b.length < 10) {
      return result(
        'Collect at least 10 measured shots per setup in this round; retain normal mishits.',
      );
    }
    if (switches < 3) {
      return result(
        'Alternate setups in short blocks (at least three switches) to reduce warm-up and fatigue bias.',
      );
    }
    final aa = baseline!, bb = candidate!;
    // Conservative small-sample interval (2.3 >= t(.975, 9)). This measures
    // shot sampling uncertainty, not device or flight-model accuracy.
    double margin(double va, double vb) =>
        2.3 * math.sqrt(va / a.length + vb / b.length);
    final delta = aa.objectiveLoss - bb.objectiveLoss;
    final uncertainty = margin(aa.objectiveVariance, bb.objectiveVariance);
    if (aa.objectiveVariance == 0 && bb.objectiveVariance == 0) {
      return result(
        'Identical repeated outcomes need verification before comparing.',
      );
    }
    if (delta - uncertainty <= 2) {
      return result(
        delta + uncertainty < -2
            ? 'Baseline performs better on the selected objective in this round.'
            : 'No clear, practically meaningful candidate advantage yet.',
        improvement: delta,
        margin: uncertainty,
        enough: true,
      );
    }
    final directionRisk =
        bb.absoluteOffline -
        aa.absoluteOffline +
        margin(aa.offlineVariance, bb.offlineVariance);
    final carryRisk =
        aa.carry - bb.carry + margin(aa.carryVariance, bb.carryVariance);
    final tradeoff = switch (context.goal) {
      FittingGoal.carry =>
        directionRisk > context.offlineTolerance * .1 ||
            bb.absoluteOffline > context.offlineTolerance,
      FittingGoal.accuracy => carryRisk > 5,
      FittingGoal.approach =>
        bb.stoppingFraction < .8 ||
            bb.absoluteOffline > context.offlineTolerance,
    };
    if (tradeoff) {
      return result(
        'The selected objective improved, but direction, carry or stopping trade-offs need review.',
        improvement: delta,
        margin: uncertainty,
        enough: true,
      );
    }
    return result(
      'Candidate has a modelled advantage on the selected objective in this round.',
      improvement: delta,
      margin: uncertainty,
      enough: true,
      favourable: true,
    );
  }

  return FittingComparison(
    context: context,
    baselineSetup: setups[false],
    candidateSetup: setups[true],
    comparison: round(FittingPhase.comparison),
    confirmation: round(FittingPhase.confirmation),
  );
}
