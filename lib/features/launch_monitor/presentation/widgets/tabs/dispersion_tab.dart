import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/theme.dart';

class DispersionTab extends StatefulWidget {
  final List<ShotData> allShots;
  final List<Club> clubs;
  final Club? selectedClub;
  final ShotData? highlightedShot;
  final ValueChanged<Club?> onClubSelected;
  /// Retained for API compatibility; the horizontal filter bar handles selection.
  final bool showSidebar;

  const DispersionTab({
    super.key,
    required this.allShots,
    required this.clubs,
    this.selectedClub,
    this.highlightedShot,
    required this.onClubSelected,
    this.showSidebar = false,
  });

  @override
  State<DispersionTab> createState() => _DispersionTabState();
}

class _DispersionTabState extends State<DispersionTab> {
  Club? _filterClub;

  @override
  void initState() {
    super.initState();
    _filterClub = widget.selectedClub;
  }

  @override
  Widget build(BuildContext context) {
    final clubsWithShots = widget.clubs
        .where((c) => widget.allShots.any((s) => s.clubId == c.id))
        .toList();

    final selectedShots = _filterClub == null
        ? widget.allShots
        : widget.allShots.where((s) => s.clubId == _filterClub!.id).toList();

    final shotCount = selectedShots.length;

    final avgCarry = selectedShots.isEmpty
        ? 0.0
        : selectedShots.map((s) => s.carry).reduce((a, b) => a + b) /
              selectedShots.length;

    final avgOffline = selectedShots.isEmpty
        ? 0.0
        : selectedShots
                .map((s) => s.carry * (s.launchDirection * math.pi / 180.0))
                .reduce((a, b) => a + b) /
            selectedShots.length;

    String offlineStr() {
      if (selectedShots.isEmpty) return '--';
      final abs = avgOffline.abs();
      if (abs < 0.05) return '0.0';
      final dir = avgOffline < 0 ? 'L' : 'R';
      return '${abs.toStringAsFixed(1)} $dir';
    }

    return Column(
      children: [
        // Stats row
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _DispStat(
                label: 'Shots',
                value: shotCount > 0 ? shotCount.toString() : '--',
                unit: '',
              ),
              _DispStat(
                label: 'Avg Carry',
                value: avgCarry > 0 ? avgCarry.toStringAsFixed(1) : '--',
                unit: 'yds',
              ),
              _DispStat(
                label: 'Avg Offline',
                value: offlineStr(),
                unit: selectedShots.isEmpty ? '' : 'yds',
              ),
            ],
          ),
        ),
        // Club filter bar — shown when clubs have shots
        if (clubsWithShots.isNotEmpty) _buildFilterBar(clubsWithShots),
        // Canvas
        Expanded(
          child: widget.allShots.isEmpty
              ? Center(
                  child: Text(
                    'Hit shots to see dispersion',
                    style: AppTextStyles.sans(color: AppColors.textMuted),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      _YAxis(
                        allShots: selectedShots.isEmpty
                            ? widget.allShots
                            : selectedShots,
                      ),
                      Expanded(
                        child: CustomPaint(
                          painter: _DispersionPainter(
                            allShots: widget.allShots,
                            clubs: widget.clubs,
                            filterClub: _filterClub,
                            highlightedShot: widget.highlightedShot,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(List<Club> clubsWithShots) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [
          _FilterChip(
            label: 'All',
            color: AppColors.accent,
            active: _filterClub == null,
            onTap: () => setState(() => _filterClub = null),
          ),
          ...clubsWithShots.map((club) => Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _FilterChip(
                  label: club.shortName,
                  color: club.color,
                  active: _filterClub?.id == club.id,
                  onTap: () => setState(() => _filterClub = club),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Stat tile ─────────────────────────────────────────────────────────────────

class _DispStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _DispStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textDimmed,
              weight: FontWeight.w400,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTextStyles.mono(size: 52)),
              const SizedBox(width: 4),
              Text(unit,
                  style:
                      AppTextStyles.sans(size: 14, color: AppColors.textDimmed)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(30) : Colors.transparent,
          border: Border.all(
            color: active ? color : AppColors.border2,
            width: active ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != 'All') ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: AppTextStyles.sans(
                size: 11,
                weight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? color : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Y-axis labels ─────────────────────────────────────────────────────────────

class _YAxis extends StatelessWidget {
  final List<ShotData> allShots;

  const _YAxis({required this.allShots});

  @override
  Widget build(BuildContext context) {
    final carries = allShots.map((s) => s.carry).toList();
    final minC = carries.reduce(math.min);
    final maxC = carries.reduce(math.max);

    final step = ((maxC - minC) / 3).ceilToDouble();
    final bottom = (minC / 10).floor() * 10.0;
    final labels =
        List.generate(4, (i) => bottom + step * i).reversed.toList();

    return SizedBox(
      width: 28,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels
            .map((v) => Text(
                  v.toStringAsFixed(0),
                  style:
                      AppTextStyles.mono(size: 9, color: AppColors.textDimmed),
                ))
            .toList(),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _DispersionPainter extends CustomPainter {
  final List<ShotData> allShots;
  final List<Club> clubs;
  final Club? filterClub;
  final ShotData? highlightedShot;

  _DispersionPainter({
    required this.allShots,
    required this.clubs,
    required this.filterClub,
    this.highlightedShot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (allShots.isEmpty) return;

    final carries = allShots.map((s) => s.carry).toList();
    final laterals = allShots.map((s) => s.lateralOffset).toList();

    final minCarry = carries.reduce(math.min) - 15;
    final maxCarry = carries.reduce(math.max) + 15;
    final maxLateral = laterals.map((v) => v.abs()).reduce(math.max) + 15;

    double toX(double lateral) =>
        size.width / 2 + lateral / maxLateral * (size.width / 2);

    double toY(double carry) =>
        size.height * (1.0 - (carry - minCarry) / (maxCarry - minCarry));

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 0.5;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);

    final carryRange = (maxCarry - minCarry).clamp(10.0, double.infinity);
    final hStep = (carryRange / 3).ceilToDouble();
    final hBase = (minCarry / hStep).floor() * hStep;
    for (var c = hBase; c <= maxCarry; c += hStep) {
      final y = toY(c);
      if (y < 0 || y > size.height) continue;
      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final vertXs = [size.width * 0.15, size.width / 2, size.width * 0.85];
    for (final x in vertXs) {
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, size.height), gridPaint);
      final lateral = (x / size.width - 0.5) * 2 * maxLateral;
      final isCenter = lateral.abs() < 0.1;
      final labelText = isCenter
          ? '0'
          : '${lateral.abs().toStringAsFixed(0)} ${lateral < 0 ? 'L' : 'R'}';
      labelPainter
        ..text = TextSpan(
          text: labelText,
          style: AppTextStyles.mono(size: 9, color: AppColors.textDimmed),
        )
        ..layout();
      labelPainter.paint(canvas, Offset(x - labelPainter.width / 2, 4));
    }

    final shotsPerClub = <String, List<ShotData>>{};
    for (final shot in allShots) {
      if (shot.clubId != null) {
        shotsPerClub.putIfAbsent(shot.clubId!, () => []).add(shot);
      }
    }

    final clubById = {for (final c in clubs) c.id: c};

    // Background clubs
    for (final club in clubs) {
      if (club.id == filterClub?.id) continue;
      final shots = shotsPerClub[club.id];
      if (shots == null || shots.isEmpty) continue;
      _drawClubEllipse(
        canvas,
        shots,
        filterClub == null ? club.color : club.color.withAlpha(18),
        filterClub == null ? 1.5 : 0.6,
        toX,
        toY,
        filled: filterClub == null,
        fillAlpha: filterClub == null ? 10 : 4,
      );
    }

    if (filterClub == null) {
      for (final shot in allShots) {
        final color = shot.clubId != null
            ? (clubById[shot.clubId!]?.color ?? Colors.white)
            : Colors.white;
        canvas.drawCircle(
          Offset(toX(shot.lateralOffset), toY(shot.carry)),
          3.5,
          Paint()..color = color,
        );
      }
    } else {
      final shots = shotsPerClub[filterClub!.id];
      if (shots != null && shots.isNotEmpty) {
        _drawClubEllipse(
          canvas, shots, filterClub!.color, 1.5, toX, toY,
          filled: true, fillAlpha: 15,
        );
        final dotPaint = Paint()..color = Colors.white;
        for (final shot in shots) {
          canvas.drawCircle(
            Offset(toX(shot.lateralOffset), toY(shot.carry)), 3.5, dotPaint);
        }
      }
    }

    if (highlightedShot != null) {
      final hx = toX(highlightedShot!.lateralOffset);
      final hy = toY(highlightedShot!.carry);
      final ringColor = highlightedShot!.clubId != null
          ? (clubById[highlightedShot!.clubId!]?.color ?? AppColors.accent)
          : AppColors.accent;
      canvas.drawCircle(Offset(hx, hy), 14,
          Paint()
            ..color = ringColor.withAlpha(40)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(hx, hy), 10,
          Paint()
            ..color = ringColor.withAlpha(220)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawCircle(Offset(hx, hy), 5, Paint()..color = Colors.white);
    }
  }

  void _drawClubEllipse(
    Canvas canvas,
    List<ShotData> shots,
    Color color,
    double strokeWidth,
    double Function(double) toX,
    double Function(double) toY, {
    bool filled = false,
    int fillAlpha = 20,
  }) {
    if (shots.isEmpty) return;
    final avgLateral =
        shots.map((s) => s.lateralOffset).reduce((a, b) => a + b) /
            shots.length;
    final avgCarry =
        shots.map((s) => s.carry).reduce((a, b) => a + b) / shots.length;

    if (shots.length == 1) {
      canvas.drawCircle(
        Offset(toX(avgLateral), toY(avgCarry)), 5, Paint()..color = color);
      return;
    }

    double sd(Iterable<double> vals) {
      final list = vals.toList();
      final mean = list.reduce((a, b) => a + b) / list.length;
      final variance = list
              .map((x) => (x - mean) * (x - mean))
              .reduce((a, b) => a + b) /
          (list.length - 1);
      return math.sqrt(variance);
    }

    final sigmaLateral = sd(shots.map((s) => s.lateralOffset));
    final sigmaCarry = sd(shots.map((s) => s.carry));
    final cx = toX(avgLateral);
    final cy = toY(avgCarry);
    final rx = (toX(avgLateral + sigmaLateral) - cx).abs() + 6;
    final ry = (toY(avgCarry + sigmaCarry) - cy).abs() + 6;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: rx * 2, height: ry * 2);

    if (filled) {
      canvas.drawOval(rect, Paint()..color = color.withAlpha(fillAlpha));
    }
    canvas.drawOval(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLen = 3.0;
    const gapLen = 4.0;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final count = (len / (dashLen + gapLen)).floor();
    final ux = dx / len;
    final uy = dy / len;
    for (var i = 0; i < count; i++) {
      final t0 = i * (dashLen + gapLen);
      final t1 = t0 + dashLen;
      canvas.drawLine(Offset(p1.dx + ux * t0, p1.dy + uy * t0),
          Offset(p1.dx + ux * t1, p1.dy + uy * t1), paint);
    }
  }

  @override
  bool shouldRepaint(_DispersionPainter old) =>
      old.allShots != allShots ||
      old.clubs != clubs ||
      old.filterClub?.id != filterClub?.id ||
      old.highlightedShot != highlightedShot;
}
