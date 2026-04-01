import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

class DispersionTab extends ConsumerStatefulWidget {
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
  ConsumerState<DispersionTab> createState() => _DispersionTabState();
}

class _DispersionTabState extends ConsumerState<DispersionTab>
    with TickerProviderStateMixin {
  Club? _filterClub;
  late final AnimationController _zoomCtrl;

  // Animated range values for smooth zoom transitions.
  double _oldMinCarry = 0, _oldMaxCarry = 300, _oldMaxLateral = 50;
  double _newMinCarry = 0, _newMaxCarry = 300, _newMaxLateral = 50;
  bool _rangeInitialised = false;

  /// Manual zoom scale: 1.0 = auto-fit, <1 = zoom in, >1 = zoom out.
  double _zoomScale = 1.0;
  double _oldZoomScale = 1.0;
  double _newZoomScale = 1.0;
  late final AnimationController _zoomScaleCtrl;
  static const _zoomStep = 0.25;
  static const _zoomMin = 0.25;
  static const _zoomMax = 3.0;

  @override
  void initState() {
    super.initState();
    _filterClub = widget.selectedClub;
    _zoomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() => setState(() {}));
    _zoomScaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final t = Curves.easeOut.transform(_zoomScaleCtrl.value);
        setState(() {
          _zoomScale = ui.lerpDouble(_oldZoomScale, _newZoomScale, t)!;
        });
      });
  }

  @override
  void dispose() {
    _zoomCtrl.dispose();
    _zoomScaleCtrl.dispose();
    super.dispose();
  }

  /// Compute target range from the given shots and animate towards it.
  void _updateRange(List<ShotData> rangeShots) {
    if (rangeShots.isEmpty) return;
    final carries = rangeShots.map((s) => s.carry).toList();
    final laterals = rangeShots.map((s) => s.lateralOffset).toList();
    final tMinCarry = carries.reduce(math.min) - 15.0;
    final tMaxCarry = carries.reduce(math.max) + 15.0;
    final tMaxLateral = laterals.map((v) => v.abs()).reduce(math.max) + 15.0;

    if (!_rangeInitialised) {
      _oldMinCarry = _newMinCarry = tMinCarry;
      _oldMaxCarry = _newMaxCarry = tMaxCarry;
      _oldMaxLateral = _newMaxLateral = tMaxLateral;
      _rangeInitialised = true;
      return;
    }

    // Snap old values to wherever the current animation is.
    final t = Curves.easeOut.transform(_zoomCtrl.value);
    _oldMinCarry = ui.lerpDouble(_oldMinCarry, _newMinCarry, t)!;
    _oldMaxCarry = ui.lerpDouble(_oldMaxCarry, _newMaxCarry, t)!;
    _oldMaxLateral = ui.lerpDouble(_oldMaxLateral, _newMaxLateral, t)!;

    _newMinCarry = tMinCarry;
    _newMaxCarry = tMaxCarry;
    _newMaxLateral = tMaxLateral;

    _zoomCtrl.forward(from: 0);
  }

  double get _animMinCarry {
    final t = Curves.easeOut.transform(_zoomCtrl.value);
    final base = ui.lerpDouble(_oldMinCarry, _newMinCarry, t)!;
    final mid = (base + _animMaxCarryRaw) / 2;
    return mid - (mid - base) * _zoomScale;
  }

  double get _animMaxCarryRaw {
    final t = Curves.easeOut.transform(_zoomCtrl.value);
    return ui.lerpDouble(_oldMaxCarry, _newMaxCarry, t)!;
  }

  double get _animMaxCarry {
    final t = Curves.easeOut.transform(_zoomCtrl.value);
    final base = ui.lerpDouble(_oldMaxCarry, _newMaxCarry, t)!;
    final min = ui.lerpDouble(_oldMinCarry, _newMinCarry, t)!;
    final mid = (min + base) / 2;
    return mid + (base - mid) * _zoomScale;
  }

  double get _animMaxLateral {
    final t = Curves.easeOut.transform(_zoomCtrl.value);
    return ui.lerpDouble(_oldMaxLateral, _newMaxLateral, t)! * _zoomScale;
  }

  void _animateZoomTo(double target) {
    _oldZoomScale = _zoomScale;
    _newZoomScale = target.clamp(_zoomMin, _zoomMax);
    _zoomScaleCtrl.forward(from: 0);
  }

  void _zoomIn() => _animateZoomTo(_newZoomScale - _zoomStep);

  void _zoomOut() => _animateZoomTo(_newZoomScale + _zoomStep);

  void _zoomReset() => _animateZoomTo(1.0);

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(unitPrefsProvider);

    final clubsWithShots = widget.clubs
        .where((c) => widget.allShots.any((s) => s.clubId == c.id))
        .toList();

    final selectedShots = _filterClub == null
        ? widget.allShots
        : widget.allShots.where((s) => s.clubId == _filterClub!.id).toList();

    // Update animated range whenever shots or filter change.
    final effectiveRange = selectedShots.isEmpty ? widget.allShots : selectedShots;
    _updateRange(effectiveRange);

    final shotCount = selectedShots.length;

    final avgCarryYds = selectedShots.isEmpty
        ? 0.0
        : selectedShots.map((s) => s.carry).reduce((a, b) => a + b) /
              selectedShots.length;

    final avgOfflineYds = selectedShots.isEmpty
        ? 0.0
        : selectedShots
                  .map((s) => s.carry * (s.launchDirection * math.pi / 180.0))
                  .reduce((a, b) => a + b) /
              selectedShots.length;

    String offlineStr() {
      if (selectedShots.isEmpty) return '--';
      final converted = prefs.dist(avgOfflineYds);
      final abs = converted.abs();
      if (abs < 0.05) return '0.0';
      final dir = avgOfflineYds < 0 ? 'L' : 'R';
      return '${abs.toStringAsFixed(1)} $dir';
    }

    return Column(
      children: [
        // Stats row
        LayoutBuilder(
          builder: (context, constraints) {
            final shotsMinWidth = constraints.maxWidth * 0.18;
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _DispStat(
                    label: 'Shots',
                    value: shotCount > 0 ? shotCount.toString() : '--',
                    unit: '',
                    expand: false,
                    minWidth: shotsMinWidth,
                  ),
                  const SizedBox(width: 16),
                  _DispStat(
                    label: 'Avg Carry',
                    value: avgCarryYds > 0
                        ? prefs.dist(avgCarryYds).toStringAsFixed(1)
                        : '--',
                    unit: selectedShots.isEmpty ? '' : prefs.distLabel,
                  ),
                  _DispStat(
                    label: 'Avg Offline',
                    value: offlineStr(),
                    unit: selectedShots.isEmpty ? '' : prefs.distLabel,
                  ),
                ],
              ),
            );
          },
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
              : Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          _YAxis(
                            minCarry: _animMinCarry,
                            maxCarry: _animMaxCarry,
                            prefs: prefs,
                          ),
                          Expanded(
                            child: CustomPaint(
                              painter: _DispersionPainter(
                                allShots: widget.allShots,
                                clubs: widget.clubs,
                                filterClub: _filterClub,
                                highlightedShot: widget.highlightedShot,
                                minCarry: _animMinCarry,
                                maxCarry: _animMaxCarry,
                                maxLateral: _animMaxLateral,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _ZoomControls(
                        onZoomIn: _zoomIn,
                        onZoomOut: _zoomOut,
                        onReset: _zoomReset,
                        canZoomIn: _newZoomScale > _zoomMin,
                        canZoomOut: _newZoomScale < _zoomMax,
                        isDefault: _newZoomScale == 1.0,
                      ),
                    ),
                  ],
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
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        itemCount: clubsWithShots.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return _FilterChip(
              label: 'All',
              color: AppColors.accent,
              active: _filterClub == null,
              onTap: () => setState(() => _filterClub = null),
            );
          }
          final club = clubsWithShots[i - 1];
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _FilterChip(
              label: club.shortName,
              color: club.color,
              active: _filterClub?.id == club.id,
              onTap: () => setState(() => _filterClub = club),
            ),
          );
        },
      ),
    );
  }
}

// ── Stat tile ─────────────────────────────────────────────────────────────────

class _DispStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool expand;
  final double minWidth;

  const _DispStat({
    required this.label,
    required this.value,
    required this.unit,
    this.expand = true,
    this.minWidth = 0,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
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
            Text(
              unit,
              style: AppTextStyles.sans(
                size: 14,
                color: AppColors.textDimmed,
              ),
            ),
          ],
        ),
      ],
    );
    final constrained = minWidth > 0
        ? ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: column,
          )
        : column;
    return expand ? Expanded(child: constrained) : constrained;
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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

// ── Zoom controls ────────────────────────────────────────────────────────────

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final bool canZoomIn;
  final bool canZoomOut;
  final bool isDefault;

  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.canZoomIn,
    required this.canZoomOut,
    required this.isDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.add,
            onTap: canZoomIn ? onZoomIn : null,
          ),
          Container(height: 1, width: 28, color: AppColors.border2),
          GestureDetector(
            onTap: isDefault ? null : onReset,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: Icon(
                Icons.my_location,
                size: 14,
                color: isDefault
                    ? AppColors.textDimmed
                    : AppColors.accent,
              ),
            ),
          ),
          Container(height: 1, width: 28, color: AppColors.border2),
          _ZoomButton(
            icon: Icons.remove,
            onTap: canZoomOut ? onZoomOut : null,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ZoomButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.textMuted : AppColors.textDimmed,
        ),
      ),
    );
  }
}

// ── Y-axis labels ─────────────────────────────────────────────────────────────

class _YAxis extends StatelessWidget {
  final double minCarry;
  final double maxCarry;
  final UnitPrefs prefs;

  const _YAxis({
    required this.minCarry,
    required this.maxCarry,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final range = (maxCarry - minCarry).clamp(10.0, double.infinity);
    final step = (range / 3).ceilToDouble();
    final bottom = (minCarry / step).floor() * step;
    final labels = List.generate(4, (i) => bottom + step * i).reversed.toList();

    return SizedBox(
      width: 28,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels
            .map(
              (v) => Text(
                prefs.dist(v).toStringAsFixed(0),
                style: AppTextStyles.mono(size: 9, color: AppColors.textDimmed),
              ),
            )
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
  final double minCarry;
  final double maxCarry;
  final double maxLateral;

  _DispersionPainter({
    required this.allShots,
    required this.clubs,
    required this.filterClub,
    required this.minCarry,
    required this.maxCarry,
    required this.maxLateral,
    this.highlightedShot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (allShots.isEmpty) return;

    double toX(double lateral) =>
        size.width / 2 + lateral / maxLateral * (size.width / 2);

    double toY(double carry) =>
        size.height * (1.0 - (carry - minCarry) / (maxCarry - minCarry));

    final gridPaint = Paint()
      ..color = AppColors.textDimmed
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
          canvas,
          shots,
          filterClub!.color,
          1.5,
          toX,
          toY,
          filled: true,
          fillAlpha: 15,
        );
        final dotPaint = Paint()..color = Colors.white;
        for (final shot in shots) {
          canvas.drawCircle(
            Offset(toX(shot.lateralOffset), toY(shot.carry)),
            3.5,
            dotPaint,
          );
        }
      }
    }

    if (highlightedShot != null) {
      final hx = toX(highlightedShot!.lateralOffset);
      final hy = toY(highlightedShot!.carry);
      final ringColor = highlightedShot!.clubId != null
          ? (clubById[highlightedShot!.clubId!]?.color ?? AppColors.accent)
          : AppColors.accent;
      canvas.drawCircle(
        Offset(hx, hy),
        14,
        Paint()
          ..color = ringColor.withAlpha(40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(hx, hy),
        10,
        Paint()
          ..color = ringColor.withAlpha(220)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
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
        Offset(toX(avgLateral), toY(avgCarry)),
        5,
        Paint()..color = color,
      );
      return;
    }

    double sd(Iterable<double> vals) {
      final list = vals.toList();
      final mean = list.reduce((a, b) => a + b) / list.length;
      final variance =
          list.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
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
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );

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
      canvas.drawLine(
        Offset(p1.dx + ux * t0, p1.dy + uy * t0),
        Offset(p1.dx + ux * t1, p1.dy + uy * t1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DispersionPainter old) =>
      old.allShots != allShots ||
      old.clubs != clubs ||
      old.filterClub?.id != filterClub?.id ||
      old.highlightedShot != highlightedShot ||
      old.minCarry != minCarry ||
      old.maxCarry != maxCarry ||
      old.maxLateral != maxLateral;
}
