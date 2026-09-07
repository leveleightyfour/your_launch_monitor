import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:math' as math;

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_optimizer.dart';

// ── Optimizer singleton ──────────────────────────────────────────────────────

final shotOptimizerProvider = Provider((_) => ShotOptimizer());

// ── Analysis over an explicit shot list ──────────────────────────────────────
//
// The providers below read the *live* session. These two functions take the
// shots as an argument instead, so a saved session — which the launch monitor
// provider knows nothing about — can be analysed with exactly the same code.

/// Analyses shot [selectedIndex] of [shots], or null when there is nothing to
/// analyse. Out-of-range indices clamp rather than throw.
ShotAnalysis? analyzeShotAt(
  ShotOptimizer optimizer,
  List<ShotData> shots,
  int selectedIndex,
  List<Club> clubs,
) {
  if (shots.isEmpty) return null;
  final shot = shots[selectedIndex.clamp(0, shots.length - 1)];

  // Resolve club type from the shot's clubId.
  final club = shot.clubId == null
      ? null
      : [
          ...clubs,
          ...Club.catalog,
        ].where((c) => c.id == shot.clubId).firstOrNull;

  return optimizer.analyze(
    shot,
    club?.type ?? ClubType.iron,
    clubId: shot.clubId,
  );
}

// ── Current shot analysis ────────────────────────────────────────────────────

/// Derives a [ShotAnalysis] from the currently selected shot.
/// Recomputes automatically whenever the shot or active club changes.
typedef OptimizerInput = ({List<ShotData> shots, List<Club> clubs});

class OptimizerReport {
  final List<ShotAnalysis> analyses;
  final SessionOptSummary? summary;
  const OptimizerReport(this.analyses, this.summary);
}

// The bounded flight search runs away from the UI isolate on supported native
// platforms. Selection changes reuse the same report for an immutable session.
final optimizerReportProvider = FutureProvider.autoDispose
    .family<OptimizerReport, OptimizerInput>(
      (ref, input) => compute(_buildOptimizerReport, input),
    );

OptimizerReport _buildOptimizerReport(OptimizerInput input) {
  final optimizer = ShotOptimizer();
  final analyses = [
    for (var i = 0; i < input.shots.length; i++)
      analyzeShotAt(optimizer, input.shots, i, input.clubs)!,
  ];
  return OptimizerReport(
    analyses,
    summariseShots(optimizer, input.shots, input.clubs),
  );
}

final liveOptimizerReportProvider = Provider.autoDispose(
  (ref) => ref.watch(
    optimizerReportProvider((
      shots: ref.watch(launchMonitorProvider.select((s) => s.shots)),
      clubs: ref.watch(clubsProvider),
    )),
  ),
);

final currentShotAnalysisProvider =
    Provider.autoDispose<AsyncValue<ShotAnalysis?>>((ref) {
      final index = ref.watch(selectedShotIndexProvider);
      return ref
          .watch(liveOptimizerReportProvider)
          .whenData(
            (report) => report.analyses.isEmpty
                ? null
                : report.analyses[index.clamp(0, report.analyses.length - 1)],
          );
    });

// ── Convenience read-only providers ──────────────────────────────────────────

final recommendationsProvider = Provider.autoDispose<List<Recommendation>>((
  ref,
) {
  return ref.watch(currentShotAnalysisProvider).valueOrNull?.recommendations ??
      [];
});

final criticalIssuesProvider = Provider.autoDispose<List<Diagnostic>>((ref) {
  return ref.watch(currentShotAnalysisProvider).valueOrNull?.criticalIssues ??
      [];
});

// ── Session history summary ──────────────────────────────────────────────────

class SessionOptSummary {
  final int totalShots;
  final double? avgCarry;
  final double? avgSmash;
  final int totalCritical;

  /// Most frequently out-of-range metric this session (null if none).
  final String? topIssueMetric;

  /// How many shots the top issue appeared on.
  final int topIssueCount;

  /// Sum of estimated yards lost across all flagged diagnostics.
  final double totalYardsLost;
  final int assessedShots;
  final List<ClubOptGroup> groups;

  const SessionOptSummary({
    required this.totalShots,
    required this.avgCarry,
    required this.avgSmash,
    required this.totalCritical,
    this.topIssueMetric,
    this.topIssueCount = 0,
    this.totalYardsLost = 0,
    this.assessedShots = 0,
    this.groups = const [],
  });
}

final sessionOptSummaryProvider =
    Provider.autoDispose<AsyncValue<SessionOptSummary?>>(
      (ref) => ref
          .watch(liveOptimizerReportProvider)
          .whenData((report) => report.summary),
    );

/// Rolls [shots] up into a [SessionOptSummary], or null when empty. Takes the
/// shots explicitly so a saved session can be summarised the same way as the
/// live one.
SessionOptSummary? summariseShots(
  ShotOptimizer optimizer,
  List<ShotData> shots,
  List<Club> clubs,
) {
  if (shots.isEmpty) return null;

  final buckets = <String, List<ShotData>>{};
  final issueCounts = <String, int>{};
  var critical = 0;
  var assessed = 0;
  for (final shot in shots) {
    final club = [
      ...clubs,
      ...Club.catalog,
    ].where((c) => c.id == shot.clubId).firstOrNull;
    final analysis = optimizer.analyze(
      shot,
      club?.type ?? ClubType.iron,
      clubId: shot.clubId,
    );
    if (!analysis.assessed) continue;
    assessed++;
    critical += analysis.criticalIssues.length;
    final key =
        '${shot.clubId ?? "Unknown club"} · ${shot.context.intent.name} · ${shot.context.ballSource.name}';
    (buckets[key] ??= []).add(shot);
    for (final metric
        in analysis.outOfRangeMetrics.map((d) => d.metric).toSet()) {
      issueCounts[metric] = (issueCounts[metric] ?? 0) + 1;
    }
  }
  final groups = [
    for (final b in buckets.entries) ClubOptGroup.fromShots(b.key, b.value),
  ];
  final issues = issueCounts.entries.toList()
    ..sort((a, b) {
      final order = b.value.compareTo(a.value);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
  return SessionOptSummary(
    totalShots: shots.length,
    assessedShots: assessed,
    // Cross-club means are intentionally unavailable.
    avgCarry: groups.length == 1 ? groups.first.avgCarry : null,
    avgSmash: groups.length == 1 ? groups.first.avgSmash : null,
    totalCritical: critical,
    groups: groups,
    topIssueMetric: issues.firstOrNull?.key,
    topIssueCount: issues.firstOrNull?.value ?? 0,
  );
}

class ClubOptGroup {
  final String label;
  final int count;
  final double avgCarry;
  final double? carrySd;
  final double? avgSmash;
  final int measuredSpeedCount;
  const ClubOptGroup(
    this.label,
    this.count,
    this.avgCarry,
    this.carrySd,
    this.avgSmash,
    this.measuredSpeedCount,
  );
  factory ClubOptGroup.fromShots(String label, List<ShotData> shots) {
    final mean = shots.fold(0.0, (s, x) => s + x.carry) / shots.length;
    final speeds = shots.where((s) => s.hasMeasuredClubSpeed).toList();
    return ClubOptGroup(
      label,
      shots.length,
      mean,
      shots.length < 2
          ? null
          : math.sqrt(
              shots.fold(0.0, (s, x) => s + math.pow(x.carry - mean, 2)) /
                  (shots.length - 1),
            ),
      speeds.isEmpty
          ? null
          : speeds.fold(0.0, (s, x) => s + x.smashFactor) / speeds.length,
      speeds.length,
    );
  }
}
