import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/shot_optimizer_providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_optimizer.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── Entry point ──────────────────────────────────────────────────────────────

class ShotOptimizerPanel extends ConsumerWidget {
  /// Drawn when the panel sits as a docked side panel; disable when the
  /// panel fills the screen as its own tab.
  final bool showLeftBorder;

  /// The shots to analyse. Leave null on the live session — the panel then
  /// follows the launch monitor and the globally selected shot. A saved
  /// session passes its own shots, which the launch monitor knows nothing
  /// about, along with [selectedShotIndex] into that list.
  final List<ShotData>? shots;
  final int selectedShotIndex;

  const ShotOptimizerPanel({
    super.key,
    this.showLeftBorder = true,
    this.shots,
    this.selectedShotIndex = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explicit = shots;
    final ShotAnalysis? analysis;
    final SessionOptSummary? sessionSummary;
    if (explicit == null) {
      analysis = ref.watch(currentShotAnalysisProvider);
      sessionSummary = ref.watch(sessionOptSummaryProvider);
    } else {
      final optimizer = ref.read(shotOptimizerProvider);
      final clubs = ref.watch(clubsProvider);
      analysis = analyzeShotAt(optimizer, explicit, selectedShotIndex, clubs);
      sessionSummary = summariseShots(optimizer, explicit, clubs);
    }
    final prefs = ref.watch(unitPrefsProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: showLeftBorder
            ? const Border(left: BorderSide(color: AppColors.border))
            : null,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 36, color: AppColors.textDimmed),
            const SizedBox(height: 14),
            Text(
              'Shot Optimizer',
              style: AppTextStyles.sans(
                size: 15,
                weight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hit a shot to see what it cost you and what to work on.',
              textAlign: TextAlign.center,
              style: AppTextStyles.sans(
                size: 12,
                color: AppColors.textDimmed,
              ).copyWith(height: 1.4),
            ),
          ],
        ),
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
        // What to do comes before the evidence for it: the panel exists to
        // end in an action, and the diagnostics are the working that
        // justifies it.
        if (analysis.recommendations.isNotEmpty) ...[
          _RecommendationsSection(
            recommendations: analysis.recommendations,
            prefs: prefs,
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (analysis.diagnostics.isNotEmpty) ...[
          _DiagnosticsSection(diagnostics: analysis.diagnostics, prefs: prefs),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (sessionSummary != null)
          _SessionSummarySection(summary: sessionSummary!, prefs: prefs),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Shared pieces ────────────────────────────────────────────────────────────

/// Section heading, in the same caps label the tiles and dispersion header
/// use. [trailing] carries a count so a section announces its own size.
class _SectionHeader extends StatelessWidget {
  final String label;
  final String? trailing;

  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.statLabel()),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(
            trailing!,
            style: AppTextStyles.statLabel(color: AppColors.textDimmed),
          ),
        ],
      ],
    );
  }
}

/// Label above, number below, unit trailing — the grammar the tiles and the
/// dispersion header already use, so a readout means the same thing wherever
/// it appears. The number scales down rather than overflowing when the panel
/// is docked narrow.
class _StatReadout extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? valueColor;

  const _StatReadout({
    required this.label,
    required this.value,
    this.unit = '',
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.statLabel(),
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTextStyles.statValue(
                    size: 20,
                    color: valueColor ?? Colors.white,
                  ),
                ),
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit, style: AppTextStyles.statUnit()),
            ],
          ],
        ),
      ],
    );
  }
}

/// Readouts in one row where they fit, two-by-two where they don't. Four
/// numbers crammed across a docked 380px rail is how they ended up at 12pt
/// in the first place, which is unreadable from the mat.
class _StatGrid extends StatelessWidget {
  final List<_StatReadout> stats;

  const _StatGrid({required this.stats});

  /// Below this a readout starts clipping its label or shrinking its digits.
  static const _minCellWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _minCellWidth * stats.length) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: stats[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < stats.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: stats[i]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: i + 1 < stats.length
                        ? stats[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        );
      },
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
    final gap = analysis.carryGap;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(critical: critical, outOfRange: outOfRange),
          const SizedBox(height: 10),
          Text(
            analysis.summary,
            style: AppTextStyles.sans(
              size: 13,
              color: AppColors.textMuted,
            ).copyWith(height: 1.45),
          ),
          if (gap != null && gap > 1.0 && analysis.optimalCarry != null) ...[
            const SizedBox(height: 12),
            _CarryGapCallout(
              gapYards: gap,
              optimalCarryYards: analysis.optimalCarry!,
              prefs: prefs,
            ),
          ],
          const SizedBox(height: 16),
          _StatGrid(
            stats: [
              _StatReadout(
                label: 'Carry',
                value: prefs.dist(shot.carry).toStringAsFixed(1),
                unit: prefs.distLabel,
              ),
              _StatReadout(
                label: 'Smash',
                value: shot.smashFactor.toStringAsFixed(2),
              ),
              _StatReadout(
                label: 'Launch',
                value: shot.launchAngle.toStringAsFixed(1),
                unit: '°',
              ),
              _StatReadout(
                label: 'Spin',
                value: '${shot.spinRate.toInt()}',
                unit: 'rpm',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The distance still on the table. Leads with the gain rather than
/// restating the carry, which the readout directly below already shows.
class _CarryGapCallout extends StatelessWidget {
  final double gapYards;
  final double optimalCarryYards;
  final UnitPrefs prefs;

  const _CarryGapCallout({
    required this.gapYards,
    required this.optimalCarryYards,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final gain = prefs.dist(gapYards).toStringAsFixed(0);
    final optimal = prefs.dist(optimalCarryYards).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.severityWarning.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.severityWarning.withAlpha(70)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.trending_up,
            size: 16,
            color: AppColors.severityWarning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '+$gain ${prefs.distLabel}',
                    style: AppTextStyles.sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.severityWarning,
                    ),
                  ),
                  TextSpan(
                    text: '  on offer — optimal carry is '
                        '$optimal ${prefs.distLabel}',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
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
    final IconData icon;
    if (critical > 0) {
      color = AppColors.severityCritical;
      icon = Icons.error_outline;
      label = '$critical critical ${critical == 1 ? 'issue' : 'issues'}';
    } else if (outOfRange > 0) {
      color = AppColors.severityWarning;
      icon = Icons.warning_amber_rounded;
      label = '$outOfRange flagged';
    } else {
      color = context.accent;
      icon = Icons.check_circle_outline;
      label = 'Optimal';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.sans(
              size: 12,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommendations section ──────────────────────────────────────────────────

class _RecommendationsSection extends StatelessWidget {
  final List<Recommendation> recommendations;
  final UnitPrefs prefs;

  const _RecommendationsSection({
    required this.recommendations,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final shown = recommendations.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            label: 'Work on',
            trailing: recommendations.length > shown.length
                ? '${shown.length} of ${recommendations.length}'
                : null,
          ),
          const SizedBox(height: 10),
          for (final rec in shown)
            _RecommendationTile(recommendation: rec, prefs: prefs),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final Recommendation recommendation;
  final UnitPrefs prefs;

  const _RecommendationTile({
    required this.recommendation,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final gain = recommendation.expectedGainYards;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.accentSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${recommendation.priority}',
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w700,
                    color: context.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    _sentenceCase(recommendation.action),
                    style: AppTextStyles.sans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: context.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recommendation.description,
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textMuted,
            ).copyWith(height: 1.45),
          ),
          if (gain != null && gain > 1.0) ...[
            const SizedBox(height: 8),
            Text(
              'Estimated gain '
              '+${prefs.dist(gain).toStringAsFixed(0)} ${prefs.distLabel}',
              style: AppTextStyles.sans(
                size: 12,
                weight: FontWeight.w700,
                color: context.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Diagnostics section ──────────────────────────────────────────────────────

class _DiagnosticsSection extends StatelessWidget {
  final List<Diagnostic> diagnostics;
  final UnitPrefs prefs;

  const _DiagnosticsSection({required this.diagnostics, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            label: 'Diagnostics',
            trailing: '${diagnostics.length}',
          ),
          const SizedBox(height: 10),
          for (final diag in diagnostics)
            _DiagnosticTile(diagnostic: diag, prefs: prefs),
        ],
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  final Diagnostic diagnostic;
  final UnitPrefs prefs;

  const _DiagnosticTile({required this.diagnostic, required this.prefs});

  Color get _severityColor => switch (diagnostic.severity) {
    Severity.critical => AppColors.severityCritical,
    Severity.high => AppColors.severityWarning,
    _ => AppColors.severityInfo,
  };

  IconData get _icon => switch (diagnostic.severity) {
    Severity.critical => Icons.error_outline,
    Severity.high => Icons.warning_amber_rounded,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    // How far out of range the metric sits, for the deviation bar.
    final range = diagnostic.maxOptimal - diagnostic.minOptimal;
    final mid = (diagnostic.minOptimal + diagnostic.maxOptimal) / 2;
    final deviation = (diagnostic.measured - mid).abs();
    final barFraction = (deviation / (range * 1.5)).clamp(0.0, 1.0);
    final lost = diagnostic.estimatedYardsLost;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        // Severity tints the whole card's edge rather than a heavy bar down
        // one side, and is repeated in the icon and the word so it never
        // rests on colour alone.
        border: Border.all(color: _severityColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 15, color: _severityColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _humanizeMetric(diagnostic.metric),
                  style: AppTextStyles.sans(size: 14, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                diagnostic.severity.name.toUpperCase(),
                style: AppTextStyles.statLabel(color: _severityColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _InlineFigure(
                label: 'Measured',
                value: _formatValue(diagnostic.measured, diagnostic.metric),
                valueColor: _severityColor,
              ),
              _InlineFigure(
                label: 'Optimal',
                value:
                    '${_formatValue(diagnostic.minOptimal, diagnostic.metric)}'
                    '–${_formatValue(diagnostic.maxOptimal, diagnostic.metric)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DeviationBar(fraction: barFraction, color: _severityColor),
          if (lost != null && lost > 1.0) ...[
            const SizedBox(height: 10),
            Text(
              '~${prefs.dist(lost).toStringAsFixed(0)} ${prefs.distLabel} lost',
              style: AppTextStyles.sans(
                size: 12,
                weight: FontWeight.w700,
                color: AppColors.severityWarning,
              ),
            ),
          ],
          if (diagnostic.possibleRootCauses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Possibly: '
              '${diagnostic.possibleRootCauses.take(2).map(_sentenceCase).join(' · ')}',
              style: AppTextStyles.sans(
                size: 12,
                color: AppColors.textDimmed,
              ).copyWith(height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  String _formatValue(double value, String metric) => switch (metric) {
    'smashFactor' => value.toStringAsFixed(2),
    'spinRate' || 'spinLoftMismatch' => '${value.toInt()} rpm',
    'launchAngle' || 'attackAngle' => '${value.toStringAsFixed(1)}°',
    // Held in yards like everything in the domain layer. This used to print
    // the raw number with a hardcoded "yds", so a golfer working in metres
    // read one figure here in a different unit from the rest of the panel.
    'carryDistance' =>
      '${prefs.dist(value).toStringAsFixed(0)} ${prefs.distLabel}',
    'pathFaceAngleAlignment' => '${value.toStringAsFixed(1)}°',
    'impactLocation' => '${value.toStringAsFixed(2)}"',
    _ => value.toStringAsFixed(1),
  };
}

/// Caps label with its figure beside it, for the measured / optimal pair.
class _InlineFigure extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InlineFigure({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.statLabel()),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.statValue(
            size: 15,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

class _DeviationBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _DeviationBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(
        children: [
          Container(height: 4, color: AppColors.border2),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(height: 4, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Session summary section ──────────────────────────────────────────────────

class _SessionSummarySection extends StatelessWidget {
  final SessionOptSummary summary;
  final UnitPrefs prefs;

  const _SessionSummarySection({required this.summary, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(label: 'Session so far'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border2),
            ),
            child: _StatGrid(
              stats: [
                _StatReadout(label: 'Shots', value: '${summary.totalShots}'),
                _StatReadout(
                  label: 'Avg carry',
                  value: prefs.dist(summary.avgCarry).toStringAsFixed(1),
                  unit: prefs.distLabel,
                ),
                _StatReadout(
                  label: 'Avg smash',
                  value: summary.avgSmash.toStringAsFixed(2),
                ),
                _StatReadout(
                  label: 'Critical',
                  value: '${summary.totalCritical}',
                  valueColor: summary.totalCritical > 0
                      ? AppColors.severityCritical
                      : context.accent,
                ),
              ],
            ),
          ),
          if (summary.topIssueMetric != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border2),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.insights,
                    size: 15,
                    color: AppColors.severityWarning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recurring: '
                      '${_humanizeMetric(summary.topIssueMetric!)}'
                      ' — ${summary.topIssueCount}× this session',
                      style: AppTextStyles.sans(
                        size: 12,
                        color: AppColors.textMuted,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                  if (summary.totalYardsLost > 1) ...[
                    const SizedBox(width: 8),
                    Text(
                      '~${prefs.dist(summary.totalYardsLost).toStringAsFixed(0)}'
                      ' ${prefs.distLabel}',
                      style: AppTextStyles.sans(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.severityWarning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Copy helpers ─────────────────────────────────────────────────────────────

String _humanizeMetric(String metric) => switch (metric) {
  'smashFactor' => 'Smash factor',
  'launchAngle' => 'Launch angle',
  'spinRate' => 'Spin rate',
  'spinLoftMismatch' => 'Spin loft mismatch',
  'carryDistance' => 'Carry distance',
  'pathFaceAngleAlignment' => 'Path-face alignment',
  'attackAngle' => 'Attack angle',
  'impactLocation' => 'Impact location',
  _ => _sentenceCase(metric),
};

/// `ball_contact_off_center` → `Ball contact off center`. These strings come
/// out of the domain layer as identifiers; rendering them raw put lowercase
/// snake-case fragments straight into the UI.
String _sentenceCase(String raw) {
  final words = raw.replaceAll('_', ' ').trim();
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}
