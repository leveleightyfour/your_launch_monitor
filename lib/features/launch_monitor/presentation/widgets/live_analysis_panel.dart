import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_sniffer/features/launch_monitor/application/session_analyser.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class LiveAnalysisPanel extends ConsumerWidget {
  const LiveAnalysisPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(sessionAnalysisProvider);
    final prefs = ref.watch(unitPrefsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: analysis == null
          ? _EmptyState()
          : _AnalysisContent(analysis: analysis, prefs: prefs),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.analytics_outlined,
              size: 32, color: AppColors.textDimmed),
          const SizedBox(height: 12),
          Text(
            'Analysis feed',
            style: AppTextStyles.sans(size: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Hit shots to see live insights',
            style: AppTextStyles.sans(size: 11, color: AppColors.textDimmed),
          ),
        ],
      ),
    );
  }
}

// ── Main content ──────────────────────────────────────────────────────────────

class _AnalysisContent extends StatelessWidget {
  final SessionAnalysis analysis;
  final UnitPrefs prefs;

  const _AnalysisContent({required this.analysis, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _ScoreSection(analysis: analysis, prefs: prefs),
        const Divider(height: 1, color: AppColors.border),
        if (analysis.missPattern.total > 0) ...[
          _MissPatternSection(miss: analysis.missPattern),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (analysis.fatigueIndicators.isNotEmpty) ...[
          _FatigueSection(indicators: analysis.fatigueIndicators),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (analysis.events.isNotEmpty) ...[
          _AnalysisFeed(events: analysis.events),
          const Divider(height: 1, color: AppColors.border),
        ],
        if (analysis.recommendationTitle != null)
          _RecommendationCard(
            title: analysis.recommendationTitle!,
            body: analysis.recommendationBody ?? '',
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Score section ─────────────────────────────────────────────────────────────

class _ScoreSection extends StatelessWidget {
  final SessionAnalysis analysis;
  final UnitPrefs prefs;

  const _ScoreSection({required this.analysis, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final score = analysis.score;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ScoreRing(score: score.score),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score.label,
                  style: AppTextStyles.sans(
                      size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  score.summary,
                  style: AppTextStyles.sans(
                      size: 11, color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniStat(
                      label: 'Rolling carry',
                      value:
                          '${prefs.dist(analysis.rollingCarry).toStringAsFixed(1)} ${prefs.distLabel}',
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      label: 'Smash',
                      value: analysis.rollingSmash.toStringAsFixed(2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.sans(size: 9, color: AppColors.textDimmed)),
        Text(value,
            style: AppTextStyles.mono(size: 13, color: Colors.white)),
      ],
    );
  }
}

// ── Score ring ────────────────────────────────────────────────────────────────

class _ScoreRing extends StatelessWidget {
  final int score;

  const _ScoreRing({required this.score});

  Color get _ringColor => switch (score) {
        >= 80 => AppColors.accent,
        >= 60 => const Color(0xFFF59E0B),
        _ => const Color(0xFFEF4444),
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(
        painter: _RingPainter(score: score, color: _ringColor),
        child: Center(
          child: Text(
            '$score',
            style: AppTextStyles.mono(size: 22, weight: FontWeight.w400,
                color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int score;
  final Color color;

  const _RingPainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 5.0;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Background track
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepTotal,
      false,
      Paint()
        ..color = AppColors.border2
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Foreground arc
    final sweepAngle = _sweepTotal * (score / 100.0);
    if (sweepAngle > 0) {
      canvas.drawArc(
        rect,
        _startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  static const double _startAngle = math.pi * 0.75;   // ~7 o'clock
  static const double _sweepTotal = math.pi * 1.5;    // 270° sweep

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.score != score || old.color != color;
}

// ── Miss pattern section ──────────────────────────────────────────────────────

class _MissPatternSection extends StatelessWidget {
  final MissPatternData miss;

  const _MissPatternSection({required this.miss});

  static const _order = [
    MissDirection.straight,
    MissDirection.slightRight,
    MissDirection.slightLeft,
    MissDirection.missRight,
    MissDirection.missLeft,
  ];

  Color _colorFor(MissDirection d) => switch (d) {
        MissDirection.straight => AppColors.accent,
        MissDirection.slightRight || MissDirection.slightLeft =>
          const Color(0xFF60A5FA),
        MissDirection.missRight || MissDirection.missLeft =>
          const Color(0xFFF59E0B),
      };

  @override
  Widget build(BuildContext context) {
    final maxCount = _order
        .map((d) => miss.countFor(d))
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MISS PATTERN',
            style: AppTextStyles.sans(
                size: 9,
                weight: FontWeight.w600,
                color: AppColors.textDimmed),
          ),
          const SizedBox(height: 4),
          Text(
            'Direction breakdown',
            style:
                AppTextStyles.sans(size: 12, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final dir in _order)
            _MissRow(
              label: miss.labelFor(dir),
              count: miss.countFor(dir),
              maxCount: maxCount,
              color: _colorFor(dir),
            ),
        ],
      ),
    );
  }
}

class _MissRow extends StatelessWidget {
  final String label;
  final int count;
  final double maxCount;
  final Color color;

  const _MissRow({
    required this.label,
    required this.count,
    required this.maxCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount > 0 ? count / maxCount : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: AppTextStyles.sans(size: 11, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    height: 4,
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: AppTextStyles.mono(
                  size: 11,
                  color: count > 0 ? color : AppColors.textDimmed),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fatigue section ───────────────────────────────────────────────────────────

class _FatigueSection extends StatelessWidget {
  final List<FatigueIndicator> indicators;

  const _FatigueSection({required this.indicators});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FATIGUE INDICATORS',
            style: AppTextStyles.sans(
                size: 9,
                weight: FontWeight.w600,
                color: AppColors.textDimmed),
          ),
          const SizedBox(height: 10),
          for (final ind in indicators) _FatigueRow(indicator: ind),
        ],
      ),
    );
  }
}

class _FatigueRow extends StatelessWidget {
  final FatigueIndicator indicator;

  const _FatigueRow({required this.indicator});

  Color get _changeColor {
    if (indicator.isPositive) return AppColors.accent;
    if (indicator.isNegative) return const Color(0xFFF59E0B);
    return AppColors.textMuted;
  }

  /// Bar fill fraction — clamps ±30% change to 0-100% range,
  /// centred at 50% (no change = half bar).
  double get _barFraction =>
      ((indicator.changePercent / 30.0) * 0.5 + 0.5).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  indicator.label,
                  style: AppTextStyles.sans(
                      size: 11, color: AppColors.textMuted),
                ),
              ),
              Text(
                indicator.changeLabel,
                style: AppTextStyles.sans(
                    size: 11,
                    weight: FontWeight.w600,
                    color: _changeColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
                  width: constraints.maxWidth * _barFraction,
                  decoration: BoxDecoration(
                    color: _changeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Analysis feed ─────────────────────────────────────────────────────────────

class _AnalysisFeed extends StatelessWidget {
  final List<AnalysisEvent> events;

  const _AnalysisFeed({required this.events});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ANALYSIS FEED',
            style: AppTextStyles.sans(
                size: 9,
                weight: FontWeight.w600,
                color: AppColors.textDimmed),
          ),
          const SizedBox(height: 8),
          for (final event in events) _FeedItem(event: event),
        ],
      ),
    );
  }
}

class _FeedItem extends StatelessWidget {
  final AnalysisEvent event;

  const _FeedItem({required this.event});

  Color get _accentColor => switch (event.type) {
        AnalysisEventType.warning => const Color(0xFFF59E0B),
        AnalysisEventType.positive => AppColors.accent,
        AnalysisEventType.info => const Color(0xFF60A5FA),
      };

  IconData get _icon => switch (event.type) {
        AnalysisEventType.warning => Icons.warning_amber_rounded,
        AnalysisEventType.positive => Icons.trending_up,
        AnalysisEventType.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: _accentColor, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 8),
            child: Icon(_icon, size: 13, color: _accentColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AppTextStyles.sans(
                      size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  event.body,
                  style: AppTextStyles.sans(
                      size: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommendation card ───────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  final String title;
  final String body;

  const _RecommendationCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECOMMENDATION',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: AppTextStyles.sans(
                      size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
