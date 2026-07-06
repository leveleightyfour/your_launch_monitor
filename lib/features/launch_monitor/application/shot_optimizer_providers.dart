import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_optimizer.dart';

// ── Optimizer singleton ──────────────────────────────────────────────────────

final shotOptimizerProvider = Provider((_) => ShotOptimizer());

// ── Current shot analysis ────────────────────────────────────────────────────

/// Derives a [ShotAnalysis] from the currently selected shot.
/// Recomputes automatically whenever the shot or active club changes.
final currentShotAnalysisProvider = Provider<ShotAnalysis?>((ref) {
  final shots = ref.watch(launchMonitorProvider.select((s) => s.shots));
  if (shots.isEmpty) return null;

  final selectedIdx = ref.watch(selectedShotIndexProvider);
  final safeIdx = selectedIdx.clamp(0, shots.length - 1);
  final shot = shots[safeIdx];

  // Resolve club type from the shot's clubId.
  final clubs = ref.watch(clubsProvider);
  final club = shot.clubId == null
      ? null
      : clubs.where((c) => c.id == shot.clubId).firstOrNull;
  final clubType = club?.type ?? ClubType.iron;

  return ref.read(shotOptimizerProvider).analyze(
    shot, clubType, clubId: shot.clubId,
  );
});

// ── Convenience read-only providers ──────────────────────────────────────────

final recommendationsProvider = Provider<List<Recommendation>>((ref) {
  return ref.watch(currentShotAnalysisProvider)?.recommendations ?? [];
});

final criticalIssuesProvider = Provider<List<Diagnostic>>((ref) {
  return ref.watch(currentShotAnalysisProvider)?.criticalIssues ?? [];
});

// ── Session history summary ──────────────────────────────────────────────────

class SessionOptSummary {
  final int totalShots;
  final double avgCarry;
  final double avgSmash;
  final int totalCritical;

  /// Most frequently out-of-range metric this session (null if none).
  final String? topIssueMetric;

  /// How many shots the top issue appeared on.
  final int topIssueCount;

  /// Sum of estimated yards lost across all flagged diagnostics.
  final double totalYardsLost;

  const SessionOptSummary({
    required this.totalShots,
    required this.avgCarry,
    required this.avgSmash,
    required this.totalCritical,
    this.topIssueMetric,
    this.topIssueCount = 0,
    this.totalYardsLost = 0,
  });
}

final sessionOptSummaryProvider = Provider<SessionOptSummary?>((ref) {
  final shots = ref.watch(launchMonitorProvider.select((s) => s.shots));
  if (shots.isEmpty) return null;

  final clubs = ref.watch(clubsProvider);
  final optimizer = ref.read(shotOptimizerProvider);

  double totalCarry = 0;
  double totalSmash = 0;
  int totalCritical = 0;
  double totalYardsLost = 0;
  final issueCounts = <String, int>{};

  for (final shot in shots) {
    totalCarry += shot.carry;
    totalSmash += shot.smashFactor;
    final club = shot.clubId == null
        ? null
        : clubs.where((c) => c.id == shot.clubId).firstOrNull;
    final analysis = optimizer.analyze(
      shot, club?.type ?? ClubType.iron, clubId: shot.clubId,
    );
    totalCritical += analysis.criticalIssues.length;
    for (final diag in analysis.outOfRangeMetrics) {
      issueCounts[diag.metric] = (issueCounts[diag.metric] ?? 0) + 1;
      totalYardsLost += diag.estimatedYardsLost ?? 0;
    }
  }

  MapEntry<String, int>? topIssue;
  for (final entry in issueCounts.entries) {
    if (topIssue == null || entry.value > topIssue.value) topIssue = entry;
  }

  return SessionOptSummary(
    totalShots: shots.length,
    avgCarry: totalCarry / shots.length,
    avgSmash: totalSmash / shots.length,
    totalCritical: totalCritical,
    topIssueMetric: topIssue?.key,
    topIssueCount: topIssue?.value ?? 0,
    totalYardsLost: totalYardsLost,
  );
});
