import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

// ── Types ─────────────────────────────────────────────────────────────────────

enum AnalysisEventType { warning, info, positive }

enum MissDirection { straight, slightRight, slightLeft, missRight, missLeft }

class AnalysisEvent {
  final String title;
  final String body;
  final int priority;
  final AnalysisEventType type;

  const AnalysisEvent({
    required this.title,
    required this.body,
    required this.priority,
    required this.type,
  });
}

class FatigueIndicator {
  final String label;
  final double changePercent;

  const FatigueIndicator({
    required this.label,
    required this.changePercent,
  });

  String get changeLabel {
    if (changePercent.abs() < 1.0) return 'stable';
    final sign = changePercent > 0 ? '+' : '';
    return '$sign${changePercent.toStringAsFixed(0)}%';
  }

  /// True when this indicator represents a positive trend.
  bool get isPositive => changePercent > 1.0;

  /// True when this indicator represents a negative trend.
  bool get isNegative => changePercent < -1.0;
}

class MissPatternData {
  final Map<MissDirection, int> counts;
  final int total;

  const MissPatternData({required this.counts, required this.total});

  MissDirection get dominant => counts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;

  String labelFor(MissDirection d) => switch (d) {
        MissDirection.straight => 'Straight',
        MissDirection.slightRight => 'Slight R',
        MissDirection.slightLeft => 'Slight L',
        MissDirection.missRight => 'Miss R',
        MissDirection.missLeft => 'Miss L',
      };

  int countFor(MissDirection d) => counts[d] ?? 0;
}

class SessionScore {
  final int score;

  const SessionScore(this.score);

  String get label => switch (score) {
        >= 90 => 'Elite session',
        >= 80 => 'Strong session',
        >= 65 => 'Good session',
        >= 50 => 'Getting there',
        _ => 'Needs work',
      };

  String get summary => switch (score) {
        >= 90 => 'Exceptional consistency across all metrics',
        >= 80 => 'Solid all-round — minor variance to clean up',
        >= 65 => 'Good foundation — one area needs attention',
        >= 50 => 'Inconsistency is costing distance and accuracy',
        _ => 'Focus on fundamentals before pushing for distance',
      };
}

class SessionAnalysis {
  final SessionScore score;
  final MissPatternData missPattern;
  final List<FatigueIndicator> fatigueIndicators;
  final List<AnalysisEvent> events;
  final String? recommendationTitle;
  final String? recommendationBody;
  final double rollingCarry;
  final double rollingSmash;
  final double spinStdDev;
  final int shotCount;

  const SessionAnalysis({
    required this.score,
    required this.missPattern,
    required this.fatigueIndicators,
    required this.events,
    this.recommendationTitle,
    this.recommendationBody,
    required this.rollingCarry,
    required this.rollingSmash,
    required this.spinStdDev,
    required this.shotCount,
  });
}

// ── Engine ────────────────────────────────────────────────────────────────────

class SessionAnalyser {
  /// Number of recent shots used for rolling window calculations.
  final int windowSize;

  const SessionAnalyser({this.windowSize = 20});

  SessionAnalysis analyse(List<ShotData> shots) {
    // shots are newest-first (index 0 = latest shot)
    final window = shots.take(windowSize).toList();

    final missPattern = _computeMissPattern(shots);
    final fatigueIndicators = _computeFatigue(shots);
    final spinStdDev = _stdDev(window.map((s) => s.spinRate));
    final rollingCarry = window.isEmpty
        ? 0.0
        : window.map((s) => s.carry).reduce((a, b) => a + b) / window.length;
    final rollingSmash = window.isEmpty
        ? 0.0
        : window.map((s) => s.smashFactor).reduce((a, b) => a + b) /
            window.length;

    final events = _computeEvents(
        shots, window, missPattern, fatigueIndicators, spinStdDev);
    events.sort((a, b) => b.priority.compareTo(a.priority));

    final score =
        _computeScore(missPattern, fatigueIndicators, spinStdDev, rollingSmash);
    final (recTitle, recBody) =
        _topRecommendation(events, spinStdDev, missPattern);

    return SessionAnalysis(
      score: score,
      missPattern: missPattern,
      fatigueIndicators: fatigueIndicators,
      events: events,
      recommendationTitle: recTitle,
      recommendationBody: recBody,
      rollingCarry: rollingCarry,
      rollingSmash: rollingSmash,
      spinStdDev: spinStdDev,
      shotCount: shots.length,
    );
  }

  MissPatternData _computeMissPattern(List<ShotData> shots) {
    final counts = <MissDirection, int>{
      MissDirection.straight: 0,
      MissDirection.slightRight: 0,
      MissDirection.slightLeft: 0,
      MissDirection.missRight: 0,
      MissDirection.missLeft: 0,
    };
    for (final s in shots) {
      final dir = s.launchDirection;
      if (dir.abs() < 1.0) {
        counts[MissDirection.straight] = counts[MissDirection.straight]! + 1;
      } else if (dir >= 1.0 && dir < 3.0) {
        counts[MissDirection.slightRight] =
            counts[MissDirection.slightRight]! + 1;
      } else if (dir <= -1.0 && dir > -3.0) {
        counts[MissDirection.slightLeft] =
            counts[MissDirection.slightLeft]! + 1;
      } else if (dir >= 3.0) {
        counts[MissDirection.missRight] = counts[MissDirection.missRight]! + 1;
      } else {
        counts[MissDirection.missLeft] = counts[MissDirection.missLeft]! + 1;
      }
    }
    return MissPatternData(counts: counts, total: shots.length);
  }

  List<FatigueIndicator> _computeFatigue(List<ShotData> shots) {
    if (shots.length < 9) return [];
    // Reverse to chronological order (oldest first)
    final chrono = shots.reversed.toList();
    final third = (chrono.length / 3).floor();
    final first = chrono.take(third).toList();
    final last = chrono.skip(chrono.length - third).toList();

    double avgOf(List<ShotData> s, double Function(ShotData) f) =>
        s.map(f).reduce((a, b) => a + b) / s.length;

    double pctChange(double from, double to) =>
        from == 0 ? 0.0 : ((to - from) / from) * 100.0;

    final clubSpeedChange = pctChange(
      avgOf(first, (s) => s.clubSpeed),
      avgOf(last, (s) => s.clubSpeed),
    );
    final smashChange = pctChange(
      avgOf(first, (s) => s.smashFactor),
      avgOf(last, (s) => s.smashFactor),
    );

    // Spin consistency: lower variance = better, report as inverted pct change
    final spinVarFirst = _stdDev(first.map((s) => s.spinRate));
    final spinVarLast = _stdDev(last.map((s) => s.spinRate));
    final spinConsistencyChange =
        spinVarFirst == 0 ? 0.0 : -pctChange(spinVarFirst, spinVarLast);

    final launchChange = pctChange(
      avgOf(first, (s) => s.launchAngle),
      avgOf(last, (s) => s.launchAngle),
    );

    return [
      FatigueIndicator(label: 'Club speed', changePercent: clubSpeedChange),
      FatigueIndicator(label: 'Smash factor', changePercent: smashChange),
      FatigueIndicator(
          label: 'Spin consistency', changePercent: spinConsistencyChange),
      FatigueIndicator(label: 'Launch angle', changePercent: launchChange),
    ];
  }

  List<AnalysisEvent> _computeEvents(
    List<ShotData> allShots,
    List<ShotData> window,
    MissPatternData miss,
    List<FatigueIndicator> fatigue,
    double spinStdDev,
  ) {
    final events = <AnalysisEvent>[];

    // 1. Fatigue: club speed drop > 5% since session start
    final clubFatigue =
        fatigue.where((f) => f.label == 'Club speed').firstOrNull;
    if (clubFatigue != null && clubFatigue.changePercent < -5) {
      events.add(const AnalysisEvent(
        title: 'Fatigue detected',
        body:
            'Club speed has dropped more than 5% since the start of the session. Consider taking a break.',
        priority: 90,
        type: AnalysisEventType.warning,
      ));
    }

    // 2. Spin spike on the most recent shot vs window average
    if (window.length >= 3) {
      final windowAvgSpin = window.skip(1).map((s) => s.spinRate).reduce(
                (a, b) => a + b,
              ) /
          (window.length - 1);
      if (spinStdDev > 100 &&
          window.first.spinRate > windowAvgSpin + 2 * spinStdDev) {
        events.add(AnalysisEvent(
          title: 'Spin spike',
          body:
              'Last shot: ${window.first.spinRate.toStringAsFixed(0)} rpm vs avg ${windowAvgSpin.toStringAsFixed(0)} rpm. Check tee height.',
          priority: 80,
          type: AnalysisEventType.warning,
        ));
      }
    }

    // 3. High spin variance across the window
    if (spinStdDev > 600 && window.length >= 5) {
      events.add(AnalysisEvent(
        title: 'High spin variance',
        body:
            '±${spinStdDev.toStringAsFixed(0)} rpm — suggests inconsistent strike point.',
        priority: 75,
        type: AnalysisEventType.warning,
      ));
    }

    // 4. Directional miss pattern in last 5 shots
    if (allShots.length >= 5) {
      final last5 = allShots.take(5).toList();
      final allRight = last5.every((s) => s.launchDirection >= 1.0);
      final allLeft = last5.every((s) => s.launchDirection <= -1.0);
      if (allRight) {
        events.add(const AnalysisEvent(
          title: 'Miss pattern: right',
          body:
              'Last 5 shots all leaked right — check face angle and alignment.',
          priority: 70,
          type: AnalysisEventType.warning,
        ));
      } else if (allLeft) {
        events.add(const AnalysisEvent(
          title: 'Miss pattern: left',
          body:
              'Last 5 shots all leaked left — check swing path and grip pressure.',
          priority: 70,
          type: AnalysisEventType.warning,
        ));
      }
    }

    // 5. Smash factor declining
    final smashFatigue =
        fatigue.where((f) => f.label == 'Smash factor').firstOrNull;
    if (smashFatigue != null && smashFatigue.changePercent < -3) {
      events.add(const AnalysisEvent(
        title: 'Smash factor declining',
        body:
            'Contact quality is dropping. Reduce swing speed and focus on centre strikes.',
        priority: 65,
        type: AnalysisEventType.warning,
      ));
    }

    // 6. Carry trending down
    if (allShots.length >= 10) {
      final recent5 = allShots.take(5).map((s) => s.carry);
      final prev5 = allShots.skip(5).take(5).map((s) => s.carry);
      final recent5Avg = recent5.reduce((a, b) => a + b) / 5;
      final prev5Avg = prev5.reduce((a, b) => a + b) / 5;
      if (recent5Avg < prev5Avg * 0.97) {
        events.add(AnalysisEvent(
          title: 'Carry trending down',
          body:
              'Last 5 shots averaging ${recent5Avg.toStringAsFixed(1)} yds vs ${prev5Avg.toStringAsFixed(1)} yds prior.',
          priority: 55,
          type: AnalysisEventType.info,
        ));
      } else if (recent5Avg > prev5Avg * 1.03) {
        events.add(AnalysisEvent(
          title: 'Carry trending up',
          body:
              'Last 5 shots averaging ${recent5Avg.toStringAsFixed(1)} yds vs ${prev5Avg.toStringAsFixed(1)} yds prior.',
          priority: 45,
          type: AnalysisEventType.positive,
        ));
      }
    }

    // 7. Clean session — no misses at all
    final missCount = miss.countFor(MissDirection.missRight) +
        miss.countFor(MissDirection.missLeft);
    if (allShots.length >= 10 && missCount == 0) {
      events.add(AnalysisEvent(
        title: 'Zero misses',
        body:
            'All ${allShots.length} shots within the acceptable window — excellent accuracy.',
        priority: 45,
        type: AnalysisEventType.positive,
      ));
    }

    return events;
  }

  SessionScore _computeScore(
    MissPatternData miss,
    List<FatigueIndicator> fatigue,
    double spinStdDev,
    double avgSmash,
  ) {
    double score = 100;

    // Spin variance deduction
    if (spinStdDev > 800) {
      score -= 15;
    } else if (spinStdDev > 600) {
      score -= 10;
    } else if (spinStdDev > 400) {
      score -= 5;
    }

    // Miss deduction (1.5 per miss, capped at -20)
    final missCount = miss.countFor(MissDirection.missRight) +
        miss.countFor(MissDirection.missLeft);
    score -= (missCount * 1.5).clamp(0.0, 20.0);

    // Fatigue deductions
    for (final f in fatigue) {
      if (f.label == 'Club speed' && f.changePercent < -5) score -= 10;
      if (f.label == 'Smash factor' && f.changePercent < -3) score -= 8;
      if (f.label == 'Spin consistency' && f.changePercent < -10) score -= 7;
    }

    // Smash factor quality adjustment
    if (avgSmash > 1.45) {
      score += 3;
    } else if (avgSmash < 1.30) {
      score -= 5;
    }

    return SessionScore(score.round().clamp(0, 100));
  }

  (String?, String?) _topRecommendation(
    List<AnalysisEvent> sortedEvents,
    double spinStdDev,
    MissPatternData miss,
  ) {
    final warning = sortedEvents
        .where((e) => e.type == AnalysisEventType.warning)
        .firstOrNull;

    if (warning != null) {
      if (warning.title.toLowerCase().contains('spin')) {
        return (
          'Focus: spin rate',
          'High variance suggests inconsistent strike point. Try teeing up 2mm higher for the next 10 shots and monitor the spin delta.',
        );
      }
      if (warning.title.contains('Fatigue')) {
        return (
          'Take a break',
          'Club speed has dropped — continued shots risk reinforcing poor mechanics. Rest 5 minutes before the next block.',
        );
      }
      if (warning.title.contains('Miss pattern')) {
        final isRight = warning.title.contains('right');
        return (
          'Fix: ${isRight ? 'right' : 'left'} bias',
          isRight
              ? 'Consistent right miss suggests open face at impact. Check grip and ensure the face is square at address.'
              : 'Consistent left miss suggests a closed face or in-to-out path. Check alignment and follow-through.',
        );
      }
      if (warning.title.contains('Smash')) {
        return (
          'Contact quality dropping',
          'Smash factor decline indicates heel/toe misses are increasing. Reduce swing speed and focus on centre strikes.',
        );
      }
    }

    if (sortedEvents.isEmpty) {
      return (
        'Solid session',
        'All metrics are within normal range. Keep the current tempo and focus on target selection.',
      );
    }

    // Positive event at top
    final positive = sortedEvents
        .where((e) => e.type == AnalysisEventType.positive)
        .firstOrNull;
    if (positive != null) {
      return (positive.title, positive.body);
    }

    return (null, null);
  }

  double _stdDev(Iterable<double> values) {
    final list = values.toList();
    if (list.length <= 1) return 0;
    final mean = list.reduce((a, b) => a + b) / list.length;
    final variance = list
            .map((x) => (x - mean) * (x - mean))
            .reduce((a, b) => a + b) /
        (list.length - 1);
    return math.sqrt(variance);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Derives a [SessionAnalysis] from the live shot stream.
/// Recomputes automatically whenever a new shot arrives.
final sessionAnalysisProvider = Provider<SessionAnalysis?>((ref) {
  final shots = ref.watch(launchMonitorProvider.select((s) => s.shots));
  if (shots.isEmpty) return null;
  return const SessionAnalyser().analyse(shots);
});
