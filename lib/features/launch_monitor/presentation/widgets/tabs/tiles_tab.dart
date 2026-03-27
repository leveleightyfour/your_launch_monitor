import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/theme.dart';

class TilesTab extends ConsumerWidget {
  final List<ShotData> shots;
  final ShotData? selectedShot;

  const TilesTab({super.key, required this.shots, this.selectedShot});

  // Column count: phone uses fewer cols to keep tiles readable
  static int _cols(int count, {required bool tablet}) {
    if (count <= 1) return 1;
    if (tablet) {
      if (count <= 4) return 2;
      if (count <= 9) return 3;
      return 4;
    } else {
      if (count <= 4) return 2;
      return 3;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(selectedTilesProvider);
    final avg = shots.isEmpty ? null : ShotData.averageOf(shots);
    final last = selectedShot ?? (shots.isEmpty ? null : shots.first);
    final tablet = isTablet(context);

    const gap = 10.0;
    const pad = 12.0;
    // Reserve space at bottom for the Customize button
    const btnAreaH = 52.0;

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (metrics.isEmpty) {
              return Center(
                child: Text(
                  'No tiles selected',
                  style: AppTextStyles.sans(color: AppColors.textMuted),
                ),
              );
            }

            final cols = _cols(metrics.length, tablet: tablet);
            final rows = (metrics.length / cols).ceil();

            final availW = constraints.maxWidth - pad * 2 - gap * (cols - 1);
            final availH =
                constraints.maxHeight - pad * 2 - gap * (rows - 1) - btnAreaH;

            final tileW = availW / cols;
            final tileH = (availH / rows).clamp(60.0, double.infinity);
            final aspect = (tileW / tileH).clamp(0.4, 5.0);

            return GridView.builder(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + btnAreaH),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: aspect,
              ),
              itemCount: metrics.length,
              itemBuilder: (context, i) => _MetricTile(
                metric: metrics[i],
                currentShot: last,
                avgShot: avg,
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: GestureDetector(
            onTap: () => _showCustomizeSheet(context, ref, metrics),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    'Customize',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCustomizeSheet(
    BuildContext context,
    WidgetRef ref,
    List<TileMetric> current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CustomizeSheet(
        current: current,
        onApply: (updated) =>
            ref.read(selectedTilesProvider.notifier).state = updated,
      ),
    );
  }
}

// ── Metric value resolution ───────────────────────────────────────────────────

String metricValue(TileMetric m, ShotData? s) {
  if (s == null) return '--';
  return switch (m) {
    TileMetric.ballSpeed => s.ballSpeed.toStringAsFixed(1),
    TileMetric.launchDirection => '${s.launchDirection.toStringAsFixed(1)}°',
    TileMetric.launchAngle => '${s.launchAngle.toStringAsFixed(1)}°',
    TileMetric.spinRate => s.spinRate.toStringAsFixed(0),
    TileMetric.spinAxis => '${s.spinAxis.toStringAsFixed(1)}°',
    TileMetric.apex => s.apex?.toStringAsFixed(1) ?? '--',
    TileMetric.carry => s.carry.toStringAsFixed(1),
    TileMetric.run => s.run?.toStringAsFixed(1) ?? '--',
    TileMetric.totalDistance => s.totalDistance.toStringAsFixed(1),
    TileMetric.clubSpeed => s.clubSpeed.toStringAsFixed(1),
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
    TileMetric.impactLocation =>
      s.horizontalImpact != null
          ? '${s.horizontalImpact!.abs().toStringAsFixed(1)} '
                '${s.horizontalImpact! >= 0 ? 'T' : 'H'}'
          : '--',
  };
}

double? metricRaw(TileMetric m, ShotData? s) {
  if (s == null) return null;
  return switch (m) {
    TileMetric.ballSpeed => s.ballSpeed,
    TileMetric.launchDirection => s.launchDirection,
    TileMetric.launchAngle => s.launchAngle,
    TileMetric.spinRate => s.spinRate,
    TileMetric.spinAxis => s.spinAxis,
    TileMetric.apex => s.apex,
    TileMetric.carry => s.carry,
    TileMetric.run => s.run,
    TileMetric.totalDistance => s.totalDistance,
    TileMetric.clubSpeed => s.clubSpeed,
    TileMetric.swingPath => s.swingPath,
    TileMetric.faceAngle => s.faceAngle,
    TileMetric.angleOfAttack => s.angleOfAttack,
    TileMetric.smashFactor => s.smashFactor,
    TileMetric.dynamicLoft => s.dynamicLoft,
    TileMetric.impactLocation => s.horizontalImpact,
  };
}

// ── Single metric tile ────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final TileMetric metric;
  final ShotData? currentShot;
  final ShotData? avgShot;

  const _MetricTile({
    required this.metric,
    required this.currentShot,
    required this.avgShot,
  });

  @override
  Widget build(BuildContext context) {
    final currentStr = metricValue(metric, currentShot);
    final avgStr = metricValue(metric, avgShot);

    String footer = '';
    if (avgShot != null && currentShot != null) {
      final cur = metricRaw(metric, currentShot);
      final avg = metricRaw(metric, avgShot);
      if (cur != null && avg != null) {
        final diff = cur - avg;
        footer = 'AVG $avgStr  ±${diff.abs().toStringAsFixed(1)}';
      }
    } else if (avgShot != null) {
      footer = 'AVG $avgStr';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Label at top
          Text(
            metric.label,
            style: AppTextStyles.sans(
              size: 13,
              weight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          // Value — expands to fill all available space
          Expanded(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: Text(
                  currentStr,
                  style: AppTextStyles.mono(size: 108, weight: FontWeight.w600),
                ),
              ),
            ),
          ),
          // Unit below value — italic
          if (metric.unit.isNotEmpty)
            Text(
              metric.unit,
              style: AppTextStyles.sans(
                size: 13,
                color: AppColors.textDimmed,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          // AVG pill at the bottom
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                footer,
                style: AppTextStyles.mono(size: 11, color: AppColors.textMuted),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Customize bottom sheet ────────────────────────────────────────────────────

class _CustomizeSheet extends StatefulWidget {
  final List<TileMetric> current;
  final ValueChanged<List<TileMetric>> onApply;

  const _CustomizeSheet({required this.current, required this.onApply});

  @override
  State<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<_CustomizeSheet> {
  late final Set<TileMetric> _selected;

  static const _ballData = [
    TileMetric.ballSpeed,
    TileMetric.launchDirection,
    TileMetric.launchAngle,
    TileMetric.spinRate,
    TileMetric.spinAxis,
    TileMetric.apex,
    TileMetric.carry,
    TileMetric.run,
    TileMetric.totalDistance,
  ];

  static const _clubData = [
    TileMetric.clubSpeed,
    TileMetric.swingPath,
    TileMetric.faceAngle,
    TileMetric.angleOfAttack,
    TileMetric.smashFactor,
    TileMetric.dynamicLoft,
    TileMetric.impactLocation,
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.current);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Customize Tiles',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _selected.clear()),
                  child: Text(
                    'Clear all',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.border),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _Section(
                  title: 'Ball data',
                  metrics: _ballData,
                  selected: _selected,
                  onToggle: _toggle,
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Club data',
                  metrics: _clubData,
                  selected: _selected,
                  onToggle: _toggle,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final ordered = TileMetric.values
                      .where(_selected.contains)
                      .toList();
                  widget.onApply(ordered);
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(TileMetric m) => setState(() {
    if (_selected.contains(m)) {
      _selected.remove(m);
    } else {
      _selected.add(m);
    }
  });
}

class _Section extends StatelessWidget {
  final String title;
  final List<TileMetric> metrics;
  final Set<TileMetric> selected;
  final ValueChanged<TileMetric> onToggle;

  const _Section({
    required this.title,
    required this.metrics,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.sans(
            size: 10,
            weight: FontWeight.w600,
            color: AppColors.textDimmed,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics.map((m) {
            final active = selected.contains(m);
            return GestureDetector(
              onTap: () => onToggle(m),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accentFaint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? AppColors.accent : AppColors.border2,
                  ),
                ),
                child: Text(
                  m.label,
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w400,
                    color: active ? AppColors.accent : AppColors.textMuted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
