import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
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
    final prefs = ref.watch(unitPrefsProvider);
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
                key: ValueKey(metrics[i]),
                metric: metrics[i],
                currentShot: last,
                avgShot: avg,
                prefs: prefs,
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

/// Returns the display unit label for [m] respecting [prefs].
String tileUnit(TileMetric m, UnitPrefs prefs) => switch (m) {
  TileMetric.ballSpeed || TileMetric.clubSpeed => prefs.speedLabel,
  TileMetric.apex ||
  TileMetric.carry ||
  TileMetric.run ||
  TileMetric.totalDistance => prefs.distLabel,
  _ => m.unit,
};

String metricValue(TileMetric m, ShotData? s, UnitPrefs prefs) {
  if (s == null) return '--';
  return switch (m) {
    TileMetric.ballSpeed => prefs.spd(s.ballSpeed).toStringAsFixed(1),
    TileMetric.launchDirection => '${s.launchDirection.toStringAsFixed(1)}°',
    TileMetric.launchAngle => '${s.launchAngle.toStringAsFixed(1)}°',
    TileMetric.spinRate => s.spinRate.toStringAsFixed(0),
    TileMetric.spinAxis => '${s.spinAxis.toStringAsFixed(1)}°',
    TileMetric.apex =>
      s.apex != null ? prefs.dist(s.apex!).toStringAsFixed(1) : '--',
    TileMetric.carry => prefs.dist(s.carry).toStringAsFixed(1),
    TileMetric.run =>
      s.run != null ? prefs.dist(s.run!).toStringAsFixed(1) : '--',
    TileMetric.totalDistance => prefs.dist(s.totalDistance).toStringAsFixed(1),
    TileMetric.clubSpeed => prefs.spd(s.clubSpeed).toStringAsFixed(1),
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

double? metricRaw(TileMetric m, ShotData? s, UnitPrefs prefs) {
  if (s == null) return null;
  return switch (m) {
    TileMetric.ballSpeed => prefs.spd(s.ballSpeed),
    TileMetric.launchDirection => s.launchDirection,
    TileMetric.launchAngle => s.launchAngle,
    TileMetric.spinRate => s.spinRate,
    TileMetric.spinAxis => s.spinAxis,
    TileMetric.apex => s.apex != null ? prefs.dist(s.apex!) : null,
    TileMetric.carry => prefs.dist(s.carry),
    TileMetric.run => s.run != null ? prefs.dist(s.run!) : null,
    TileMetric.totalDistance => prefs.dist(s.totalDistance),
    TileMetric.clubSpeed => prefs.spd(s.clubSpeed),
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
  final UnitPrefs prefs;

  const _MetricTile({
    super.key,
    required this.metric,
    required this.currentShot,
    required this.avgShot,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final currentStr = metricValue(metric, currentShot, prefs);
    final avgStr = metricValue(metric, avgShot, prefs);

    String footer = '';
    if (avgShot != null && currentShot != null) {
      final cur = metricRaw(metric, currentShot, prefs);
      final avg = metricRaw(metric, avgShot, prefs);
      if (cur != null && avg != null) {
        final diff = cur - avg;
        footer = 'AVG $avgStr  ±${diff.abs().toStringAsFixed(1)}';
      }
    } else if (avgShot != null) {
      footer = 'AVG $avgStr';
    }

    final unit = tileUnit(metric, prefs);

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
                child: _SplitFlapText(
                  text: currentStr,
                  style: AppTextStyles.mono(size: 108, weight: FontWeight.w600),
                ),
              ),
            ),
          ),
          // Unit below value — always reserve height so all tiles scale uniformly
          Text(
            unit.isEmpty ? '\u00A0' : unit,
            style: AppTextStyles.sans(
              size: 13,
              color: unit.isEmpty ? Colors.transparent : AppColors.textDimmed,
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

// ── Split-flap value animation ────────────────────────────────────────────────

class _SplitFlapText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _SplitFlapText({required this.text, required this.style});

  @override
  State<_SplitFlapText> createState() => _SplitFlapTextState();
}

class _SplitFlapTextState extends State<_SplitFlapText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  String _from = '';

  static const _duration = Duration(milliseconds: 550);

  @override
  void initState() {
    super.initState();
    _from = widget.text;
    _ctrl = AnimationController(vsync: this, duration: _duration);
  }

  @override
  void didUpdateWidget(_SplitFlapText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _from = old.text;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Returns the character to display at [index] given animation progress [t].
  // Digits cycle through 0–9 with a left-to-right stagger; other chars flip
  // at the halfway point of their window.
  String _char(int index, double t) {
    final to = widget.text;
    final from = _from;
    final toChar = index < to.length ? to[index] : ' ';
    final fromChar = index < from.length ? from[index] : ' ';

    if (toChar == fromChar) return toChar;

    // Each character gets a staggered 70%-wide window within [0, 1].
    final offset = (index * 0.06).clamp(0.0, 0.45);
    final localT = ((t - offset) / 0.7).clamp(0.0, 1.0);

    if (localT >= 1.0) return toChar;
    if (localT <= 0.0) return fromChar;

    final isNumeric =
        RegExp(r'\d').hasMatch(toChar) || RegExp(r'\d').hasMatch(fromChar);
    if (isNumeric) {
      // Snap to final in the last 15% of the window; cycle digits before that.
      if (localT > 0.85) return toChar;
      return ((localT * 10).floor() % 10).toString();
    }

    return localT < 0.5 ? fromChar : toChar;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final len = math.max(widget.text.length, _from.length);
        final buf = StringBuffer();
        for (var i = 0; i < len; i++) {
          buf.write(_char(i, t));
        }
        return Text(buf.toString(), style: widget.style);
      },
    );
  }
}

// ── Customize bottom sheet ────────────────────────────────────────────────────

class _CustomizeSheet extends ConsumerStatefulWidget {
  final List<TileMetric> current;
  final ValueChanged<List<TileMetric>> onApply;

  const _CustomizeSheet({required this.current, required this.onApply});

  @override
  ConsumerState<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends ConsumerState<_CustomizeSheet> {
  late List<TileMetric> _selected;

  static const _ballMetrics = [
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

  static const _clubMetrics = [
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
    _selected = List.from(widget.current);
  }

  void _add(TileMetric m) => setState(() => _selected.add(m));
  void _remove(TileMetric m) => setState(() => _selected.remove(m));
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _selected.insert(newIndex, _selected.removeAt(oldIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(unitPrefsProvider);
    final ballAvail =
        _ballMetrics.where((m) => !_selected.contains(m)).toList();
    final clubAvail =
        _clubMetrics.where((m) => !_selected.contains(m)).toList();

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
                Text('Customize tiles',
                    style:
                        AppTextStyles.sans(size: 16, weight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _selected.clear()),
                  child: Text('Clear all',
                      style: AppTextStyles.sans(
                          size: 12, color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Active tiles (reorderable) ──────────────────────────
                  if (_selected.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Text('Active',
                          style: AppTextStyles.sans(
                              size: 10,
                              weight: FontWeight.w600,
                              color: AppColors.textDimmed)),
                    ),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, _, __) => Material(
                        color: Colors.transparent,
                        elevation: 4,
                        shadowColor: Colors.black54,
                        child: child,
                      ),
                      onReorder: _reorder,
                      children: [
                        for (int i = 0; i < _selected.length; i++)
                          _buildRow(_selected[i], i, prefs),
                      ],
                    ),
                  ],
                  // ── Available — ball ────────────────────────────────────
                  if (ballAvail.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Ball data',
                          style: AppTextStyles.sans(
                              size: 10,
                              weight: FontWeight.w600,
                              color: AppColors.textDimmed)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _AvailableChips(
                          metrics: ballAvail, onAdd: _add),
                    ),
                  ],
                  // ── Available — club ────────────────────────────────────
                  if (clubAvail.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Club data',
                          style: AppTextStyles.sans(
                              size: 10,
                              weight: FontWeight.w600,
                              color: AppColors.textDimmed)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _AvailableChips(
                          metrics: clubAvail, onAdd: _add),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
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
                  widget.onApply(List.from(_selected));
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

  Widget _buildRow(TileMetric m, int index, UnitPrefs prefs) {
    return Container(
      key: ValueKey(m),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle,
                  size: 18, color: AppColors.textDimmed),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(m.label,
                style: AppTextStyles.sans(size: 13, color: Colors.white)),
          ),
          if (tileUnit(m, prefs).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(tileUnit(m, prefs),
                  style: AppTextStyles.sans(
                          size: 11, color: AppColors.textDimmed)
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          GestureDetector(
            onTap: () => _remove(m),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppColors.textDimmed),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableChips extends StatelessWidget {
  final List<TileMetric> metrics;
  final ValueChanged<TileMetric> onAdd;

  const _AvailableChips({required this.metrics, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics
          .map((m) => GestureDetector(
                onTap: () => onAdd(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(m.label,
                          style: AppTextStyles.sans(
                              size: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
