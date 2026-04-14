import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/shot_optimizer_providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_optimizer.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── Entry point ──────────────────────────────────────────────────────────────

class ShotOptimizerPanel extends ConsumerWidget {
  const ShotOptimizerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(currentShotAnalysisProvider);
    final sessionSummary = ref.watch(sessionOptSummaryProvider);
    final prefs = ref.watch(unitPrefsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: analysis == null
          ? const _EmptyState()
          : _OptimizerContent(
              analysis: analysis,
              sessionSummary: sessionSummary,
              prefs: prefs,
            ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tune, size: 32, color: AppColors.textDimmed),
          const SizedBox(height: 12),
          Text(
            'Shot Optimizer',
            style: AppTextStyles.sans(size: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Hit shots to see diagnostics',
            style: AppTextStyles.sans(size: 11, color: AppColors.textDimmed),
          ),
        ],
      ),
    );
  }
}

// ── Main content ─────────────────────────────────────────────────────────────

class _OptimizerContent extends StatelessWidget {
  final ShotAnalysis analysis;
  final SessionOptSummary? sessionSummary;
  final UnitPrefs prefs;

  const _OptimizerContent({
    required this.analysis,
    required this.sessionSummary,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SummarySection(analysis: analysis, prefs: prefs),
        const Divider(height: 1, color: AppColors.border),
        if (analysis.diagnostics.isNotEmpty) ...[
          _DiagnosticsSection(diagnostics: analysis.diagnostics),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (analysis.recommendations.isNotEmpty) ...[
          _RecommendationsSection(
              recommendations: analysis.recommendations),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (sessionSummary != null)
          _SessionSummarySection(summary: sessionSummary!,  prefs: prefs),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Summary section ──────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final ShotAnalysis analysis;
  final UnitPrefs prefs;

  const _SummarySection({required this.analysis, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final critical = analysis.criticalIssues.length;
    final outOfRange = analysis.outOfRangeMetrics.length;
    final shot = analysis.shot;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusBadge(critical: critical, outOfRange: outOfRange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  analysis.summary,
                  style: AppTextStyles.sans(
                      size: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          if (analysis.carryGap != null && analysis.carryGap! > 1.0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFF59E0B).withAlpha(50)),
              ),
              child: Row(
                children: [
                  Text(
                    'Carry: ${prefs.dist(shot.carry).toStringAsFixed(0)} ${prefs.distLabel}',
                    style: AppTextStyles.mono(size: 11, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 12,
                      color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Text(
                    'Optimal: ${prefs.dist(analysis.optimalCarry!).toStringAsFixed(0)} ${prefs.distLabel}',
                    style: AppTextStyles.mono(
                        size: 11, color: const Color(0xFFF59E0B)),
                  ),
                  const Spacer(),
                  Text(
                    '+${prefs.dist(analysis.carryGap!).toStringAsFixed(0)} ${prefs.distLabel}',
                    style: AppTextStyles.sans(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniStat(
                label: 'Carry',
                value:
                    '${prefs.dist(shot.carry).toStringAsFixed(1)} ${prefs.distLabel}',
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Smash',
                value: shot.smashFactor.toStringAsFixed(2),
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Launch',
                value: '${shot.launchAngle.toStringAsFixed(1)}°',
              ),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'Spin',
                value: '${shot.spinRate.toInt()} rpm',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final int critical;
  final int outOfRange;

  const _StatusBadge({required this.critical, required this.outOfRange});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (critical > 0) {
      color = const Color(0xFFEF4444);
      label = '$critical critical';
    } else if (outOfRange > 0) {
      color = const Color(0xFFF59E0B);
      label = '$outOfRange flagged';
    } else {
      color = AppColors.accent;
      label = 'Optimal';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: AppTextStyles.sans(
            size: 10, weight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  AppTextStyles.sans(size: 9, color: AppColors.textDimmed)),
          Text(value,
              style: AppTextStyles.mono(size: 12, color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Diagnostics section ──────────────────────────────────────────────────────

class _DiagnosticsSection extends StatelessWidget {
  final List<Diagnostic> diagnostics;

  const _DiagnosticsSection({required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DIAGNOSTICS',
            style: AppTextStyles.sans(
                size: 9,
                weight: FontWeight.w600,
                color: AppColors.textDimmed),
          ),
          const SizedBox(height: 8),
          for (final diag in diagnostics) _DiagnosticTile(diagnostic: diag),
        ],
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  final Diagnostic diagnostic;

  const _DiagnosticTile({required this.diagnostic});

  Color get _severityColor => switch (diagnostic.severity) {
        'critical' => const Color(0xFFEF4444),
        'high' => const Color(0xFFF59E0B),
        _ => const Color(0xFF60A5FA),
      };

  IconData get _icon => switch (diagnostic.severity) {
        'critical' => Icons.error_outline,
        'high' => Icons.warning_amber_rounded,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    // Compute how far out of range the metric is for the bar.
    final range = diagnostic.maxOptimal - diagnostic.minOptimal;
    final mid = (diagnostic.minOptimal + diagnostic.maxOptimal) / 2;
    final deviation = (diagnostic.measured - mid).abs();
    final barFraction = (deviation / (range * 1.5)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: _severityColor, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 13, color: _severityColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _humanizeMetric(diagnostic.metric),
                  style: AppTextStyles.sans(
                      size: 12, weight: FontWeight.w600),
                ),
              ),
              Text(
                diagnostic.severity.toUpperCase(),
                style: AppTextStyles.sans(
                    size: 9,
                    weight: FontWeight.w600,
                    color: _severityColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Measured: ${_formatValue(diagnostic.measured, diagnostic.metric)}',
                style:
                    AppTextStyles.mono(size: 11, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                'Optimal: ${_formatValue(diagnostic.minOptimal, diagnostic.metric)}'
                ' – ${_formatValue(diagnostic.maxOptimal, diagnostic.metric)}',
                style:
                    AppTextStyles.sans(size: 10, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Deviation bar
          LayoutBuilder(builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  height: 3,
                  width: constraints.maxWidth * barFraction,
                  decoration: BoxDecoration(
                    color: _severityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            );
          }),
          if (diagnostic.estimatedYardsLost != null &&
              diagnostic.estimatedYardsLost! > 1.0) ...[
            const SizedBox(height: 4),
            Text(
              '~${diagnostic.estimatedYardsLost!.toStringAsFixed(0)} yards lost',
              style: AppTextStyles.sans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: const Color(0xFFF59E0B)),
            ),
          ],
          if (diagnostic.possibleRootCauses.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Possible: ${diagnostic.possibleRootCauses.take(2).map(_humanizeCause).join(', ')}',
              style:
                  AppTextStyles.sans(size: 10, color: AppColors.textDimmed),
            ),
          ],
        ],
      ),
    );
  }

  static String _humanizeMetric(String metric) => switch (metric) {
        'smashFactor' => 'Smash Factor',
        'launchAngle' => 'Launch Angle',
        'spinRate' => 'Spin Rate',
        'spinLoftMismatch' => 'Spin Loft Mismatch',
        'carryDistance' => 'Carry Distance',
        'pathFaceAngleAlignment' => 'Path-Face Alignment',
        'attackAngle' => 'Attack Angle',
        'impactLocation' => 'Impact Location',
        _ => metric,
      };

  static String _formatValue(double value, String metric) => switch (metric) {
        'smashFactor' => value.toStringAsFixed(2),
        'spinRate' || 'spinLoftMismatch' => '${value.toInt()} rpm',
        'launchAngle' || 'attackAngle' => '${value.toStringAsFixed(1)}°',
        'carryDistance' => '${value.toStringAsFixed(0)} yds',
        'pathFaceAngleAlignment' => '${value.toStringAsFixed(1)}°',
        'impactLocation' => '${value.toStringAsFixed(2)}"',
        _ => value.toStringAsFixed(1),
      };

  static String _humanizeCause(String cause) =>
      cause.replaceAll('_', ' ');
}

// ── Recommendations section ──────────────────────────────────────────────────

class _RecommendationsSection extends StatelessWidget {
  final List<Recommendation> recommendations;

  const _RecommendationsSection({required this.recommendations});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECOMMENDATIONS',
            style: AppTextStyles.sans(
                size: 9,
                weight: FontWeight.w600,
                color: AppColors.textDimmed),
          ),
          const SizedBox(height: 8),
          for (final rec in recommendations.take(3))
            _RecommendationTile(recommendation: rec),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final Recommendation recommendation;

  const _RecommendationTile({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${recommendation.priority}',
                  style: AppTextStyles.mono(
                      size: 10, color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recommendation.action.replaceAll('_', ' '),
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            recommendation.description,
            style:
                AppTextStyles.sans(size: 10, color: AppColors.textMuted),
          ),
          if (recommendation.expectedGainYards != null &&
              recommendation.expectedGainYards! > 1.0) ...[
            const SizedBox(height: 4),
            Text(
              'Estimated gain: +${recommendation.expectedGainYards!.toStringAsFixed(0)} yards',
              style: AppTextStyles.sans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: AppColors.accent),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Session summary section ──────────────────────────────────────────────────

class _SessionSummarySection extends StatelessWidget {
  final SessionOptSummary summary;
  final UnitPrefs prefs;

  const _SessionSummarySection({
    required this.summary,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SESSION SUMMARY',
            style: AppTextStyles.sans(
                size: 9,
                weight: FontWeight.w600,
                color: AppColors.textDimmed),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border2),
            ),
            child: Row(
              children: [
                _SessionStat(
                    label: 'Shots', value: '${summary.totalShots}'),
                _SessionStat(
                  label: 'Avg Carry',
                  value:
                      '${prefs.dist(summary.avgCarry).toStringAsFixed(1)} ${prefs.distLabel}',
                ),
                _SessionStat(
                  label: 'Avg Smash',
                  value: summary.avgSmash.toStringAsFixed(2),
                ),
                _SessionStat(
                  label: 'Critical',
                  value: '${summary.totalCritical}',
                  valueColor: summary.totalCritical > 0
                      ? const Color(0xFFEF4444)
                      : AppColors.accent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SessionStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style:
                  AppTextStyles.sans(size: 9, color: AppColors.textDimmed)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.mono(
                size: 12, color: valueColor ?? Colors.white),
          ),
        ],
      ),
    );
  }
}
