import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/theme.dart';

// Colour tokens shared by both panels
const _kTeal   = Color(0xFF2DD4B0); // AppColors.accent
const _kPurple = Color(0xFF9D6EC8);
const _kBlue   = Color(0xFF5B9BD5);
const _kOrange = Color(0xFFE07840);

class ClubTab extends StatefulWidget {
  final List<ShotData> shots;
  final List<Club> clubs;
  final ShotData? selectedShot;

  const ClubTab({
    super.key,
    required this.shots,
    required this.clubs,
    this.selectedShot,
  });

  @override
  State<ClubTab> createState() => _ClubTabState();
}

class _ClubTabState extends State<ClubTab> {
  int  _subTab    = 0; // 0 = Top, 1 = Side, 2 = Impact
  bool _showAvg   = false;
  bool _showHeatmap = false;

  Club? _clubFor(ShotData s) => s.clubId == null
      ? null
      : widget.clubs.where((c) => c.id == s.clubId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    if (widget.shots.isEmpty) {
      return Center(
        child: Text('No shots yet',
            style: AppTextStyles.sans(color: AppColors.textMuted)),
      );
    }

    final last    = widget.selectedShot ?? widget.shots.first;
    final avg     = ShotData.averageOf(widget.shots);
    final display = _showAvg ? avg : last;
    final club    = _clubFor(last);
    final clubType = club?.type ?? ClubType.iron;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        return Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border))),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (!isWide) ...[
                    _SubTab(
                      label: 'Top',
                      active: _subTab == 0,
                      onTap: () => setState(() => _subTab = 0),
                    ),
                    const SizedBox(width: 8),
                    _SubTab(
                      label: 'Side',
                      active: _subTab == 1,
                      onTap: () => setState(() => _subTab = 1),
                    ),
                    const SizedBox(width: 8),
                    _SubTab(
                      label: 'Impact',
                      active: _subTab == 2,
                      onTap: () => setState(() => _subTab = 2),
                    ),
                  ],
                  const Spacer(),
                  if (isWide || _subTab == 2) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showHeatmap = !_showHeatmap),
                      child: Row(children: [
                        Text('Heatmap',
                            style: AppTextStyles.sans(
                                size: 10, color: AppColors.textMuted)),
                        const SizedBox(width: 6),
                        _Toggle(active: _showHeatmap),
                      ]),
                    ),
                    const SizedBox(width: 12),
                  ],
                  GestureDetector(
                    onTap: () => setState(() => _showAvg = !_showAvg),
                    child: Row(children: [
                      Text('Show AVG',
                          style: AppTextStyles.sans(
                              size: 10, color: AppColors.textMuted)),
                      const SizedBox(width: 6),
                      _Toggle(active: _showAvg),
                    ]),
                  ),
                ],
              ),
            ),
            // ── Content ────────────────────────────────────────────────────
            Expanded(
              child: isWide
                  ? Column(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _TrajPanel(shot: display)),
                              Container(width: 1, color: AppColors.border),
                              Expanded(
                                child: _LoftPanel(
                                  shot: display,
                                  clubType: clubType,
                                  clubId: last.clubId,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: AppColors.border),
                        Expanded(
                          flex: 3,
                          child: _ImpactSection(
                            shot: display,
                            allShots: widget.shots,
                            clubType: clubType,
                            clubId: last.clubId,
                            showHeatmap: _showHeatmap,
                          ),
                        ),
                      ],
                    )
                  : switch (_subTab) {
                      1 => _LoftPanel(
                          shot: display,
                          clubType: clubType,
                          clubId: last.clubId,
                        ),
                      2 => _ImpactSection(
                          shot: display,
                          allShots: widget.shots,
                          clubType: clubType,
                          clubId: last.clubId,
                          showHeatmap: _showHeatmap,
                        ),
                      _ => _TrajPanel(shot: display),
                    },
            ),
          ],
        );
      },
    );
  }
}

// ── Sub-tab chip ──────────────────────────────────────────────────────────────

class _SubTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SubTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? context.accentSubtle : Colors.transparent,
          border: Border.all(
              color: active ? context.accent : AppColors.border2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: AppTextStyles.sans(
              size: 11,
              weight: FontWeight.w400,
              color: active ? context.accent : AppColors.textMuted,
            )),
      ),
    );
  }
}

// ── Trajectory panel (top-down ball + face / path overlay) ────────────────────

class _TrajPanel extends StatelessWidget {
  final ShotData shot;
  const _TrajPanel({required this.shot});

  static String _spinFmt(int v) {
    if (v >= 1000) {
      return '${v ~/ 1000},${(v % 1000).toString().padLeft(3, '0')}';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final spinAxisRad = shot.spinAxis * math.pi / 180.0;
    final sideSpin    = shot.spinRate * math.sin(spinAxisRad);
    final sideAbs     = sideSpin.abs().round();
    final sideDir     = sideSpin >= 0 ? 'R' : 'L';

    final dir     = shot.launchDirection;
    final dirStr  = '${dir >= 0 ? 'R' : 'L'}${dir.abs().toStringAsFixed(1)}°';

    final offline    = shot.lateralOffset;
    final offlineStr = '${offline >= 0 ? 'R' : 'L'}${offline.abs().toStringAsFixed(1)}';

    final faceAngle  = shot.faceAngle;
    final faceStr    = faceAngle?.abs().toStringAsFixed(1);
    final faceLabel  = faceAngle == null
        ? null
        : (faceAngle >= 0 ? 'Face opened' : 'Face closed');

    final path      = shot.swingPath;
    final pathStr   = path?.abs().toStringAsFixed(1);
    final pathLabel = path == null
        ? null
        : (path > 0 ? 'In to Out' : path < 0 ? 'Out to In' : 'Neutral');

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.surface),
        CustomPaint(
          painter: _TrajPainter(shot: shot, accent: context.accent),
          child: const SizedBox.expand(),
        ),
        // Face angle — top center
        if (faceStr != null)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$faceStr°',
                    style: AppTextStyles.mono(size: 16, weight: FontWeight.w600)
                        .copyWith(color: _kTeal)),
                Text(faceLabel!,
                    style: AppTextStyles.sans(size: 9, color: _kTeal)),
              ],
            ),
          ),
        // Side spin — left center
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$sideDir${_spinFmt(sideAbs)}',
                    style: AppTextStyles.mono(size: 15, weight: FontWeight.w600)
                        .copyWith(color: _kPurple)),
                Text('Side Spin (rpm)',
                    style: AppTextStyles.sans(size: 8, color: _kPurple)),
              ],
            ),
          ),
        ),
        // Swing path — right center
        if (pathStr != null)
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$pathStr°',
                      style:
                          AppTextStyles.mono(size: 15, weight: FontWeight.w600)
                              .copyWith(color: _kTeal)),
                  Text(pathLabel!,
                      style: AppTextStyles.sans(size: 9, color: _kTeal)),
                ],
              ),
            ),
          ),
        // Direction + Offline — bottom left
        Positioned(
          left: 8,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dirStr,
                  style: AppTextStyles.mono(size: 13, weight: FontWeight.w600)
                      .copyWith(color: _kBlue)),
              Text('Direction',
                  style: AppTextStyles.sans(size: 8, color: _kBlue)),
              const SizedBox(height: 5),
              Text(offlineStr,
                  style: AppTextStyles.mono(size: 13, weight: FontWeight.w600)
                      .copyWith(color: _kOrange)),
              Text('Offline (yd)',
                  style: AppTextStyles.sans(size: 8, color: _kOrange)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrajPainter extends CustomPainter {
  final ShotData shot;
  final Color accent;
  const _TrajPainter({required this.shot, required this.accent});

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint p,
      {double on = 5, double off = 4}) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len;
    final uy = dy / len;
    var d = 0.0;
    var draw = true;
    while (d < len) {
      final seg = math.min(d + (draw ? on : off), len);
      if (draw) {
        canvas.drawLine(Offset(a.dx + ux * d, a.dy + uy * d),
            Offset(a.dx + ux * seg, a.dy + uy * seg), p);
      }
      d = seg;
      draw = !draw;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final cy = size.height * 0.52;
    final r  = math.min(size.width, size.height) * 0.28;

    // Outer circle
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = AppColors.border2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Dashed target reference line (vertical through ball)
    _dashed(
      canvas,
      Offset(cx, cy - r - 14),
      Offset(cx, cy + r * 0.3),
      Paint()
        ..color = AppColors.textDimmed.withAlpha(55)
        ..strokeWidth = 1.0,
    );

    final lineLen = r * 0.92;

    // Face angle line (solid teal)
    final faceRad = (shot.faceAngle ?? 0.0) * math.pi / 180.0;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + lineLen * math.sin(faceRad),
             cy - lineLen * math.cos(faceRad)),
      Paint()
        ..color = _kTeal
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Swing path line (dimmed teal)
    final pathRad = (shot.swingPath ?? 0.0) * math.pi / 180.0;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + lineLen * math.sin(pathRad),
             cy - lineLen * math.cos(pathRad)),
      Paint()
        ..color = _kTeal.withAlpha(110)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    // Ball dot
    canvas.drawCircle(
        Offset(cx, cy), 7, Paint()..color = Colors.white.withAlpha(210));
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_TrajPainter old) => old.shot != shot || old.accent != accent;
}

// ── Loft panel (side-view launch angle + spin) ────────────────────────────────

class _LoftPanel extends StatelessWidget {
  final ShotData shot;
  final ClubType clubType;
  final String? clubId;

  const _LoftPanel({
    required this.shot,
    required this.clubType,
    required this.clubId,
  });

  static String _spinFmt(int v) {
    if (v >= 1000) {
      return '${v ~/ 1000},${(v % 1000).toString().padLeft(3, '0')}';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final spinAxisRad = shot.spinAxis * math.pi / 180.0;
    final backSpin    = (shot.spinRate * math.cos(spinAxisRad)).abs().round();

    final dynLoft = shot.dynamicLoft;
    final aoa     = shot.angleOfAttack;
    final aoaLabel = aoa == null
        ? null
        : (aoa > 0 ? 'Ascending' : aoa < 0 ? 'Descending' : 'Level');

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.surface),
        CustomPaint(
          painter: _LoftPainter(shot: shot),
          child: const SizedBox.expand(),
        ),
        // Back spin — top left (prominent)
        Positioned(
          top: 10,
          left: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_spinFmt(backSpin),
                  style: AppTextStyles.mono(size: 20, weight: FontWeight.w600)
                      .copyWith(color: _kPurple)),
              Text('Back Spin (rpm)',
                  style: AppTextStyles.sans(size: 9, color: _kPurple)),
            ],
          ),
        ),
        // Dynamic loft — top right
        if (dynLoft != null)
          Positioned(
            top: 10,
            right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${dynLoft.toStringAsFixed(1)}°',
                    style: AppTextStyles.mono(size: 16, weight: FontWeight.w600)
                        .copyWith(color: _kTeal)),
                Text('Dynamic Loft',
                    style: AppTextStyles.sans(size: 9, color: _kTeal)),
              ],
            ),
          ),
        // Launch angle — center-ish
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0.0, 0.10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${shot.launchAngle.toStringAsFixed(1)}°',
                    style: AppTextStyles.mono(size: 20, weight: FontWeight.w600)),
                Text('Angle',
                    style: AppTextStyles.sans(
                        size: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
        // Angle of attack — right center
        if (aoa != null && aoaLabel != null)
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${aoa.abs().toStringAsFixed(1)}°',
                      style:
                          AppTextStyles.mono(size: 14, weight: FontWeight.w600)
                              .copyWith(color: _kTeal)),
                  Text(aoaLabel,
                      style: AppTextStyles.sans(size: 9, color: _kTeal)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LoftPainter extends CustomPainter {
  final ShotData shot;
  const _LoftPainter({required this.shot});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Impact origin: bottom-right quadrant
    final ox = w * 0.70;
    final oy = h * 0.80;
    final lineLen = math.min(w, h) * 0.52;

    // Ground line
    canvas.drawLine(
      Offset(0, oy),
      Offset(w, oy),
      Paint()
        ..color = AppColors.border2
        ..strokeWidth = 1.0,
    );

    final launchRad = shot.launchAngle * math.pi / 180.0;

    // Launch trajectory line (teal, going up-left)
    final launchEnd = Offset(
      ox - lineLen * math.cos(launchRad),
      oy - lineLen * math.sin(launchRad),
    );
    canvas.drawLine(
      Offset(ox, oy),
      launchEnd,
      Paint()
        ..color = _kTeal
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // AoA line (faint, showing club approach direction)
    final aoaDeg = shot.angleOfAttack ?? -2.0;
    final aoaRad = aoaDeg.abs() * math.pi / 180.0;
    final aoaLen = lineLen * 0.40;
    final aoaEnd = Offset(
      ox + aoaLen * math.cos(aoaRad),
      oy + (aoaDeg < 0 ? aoaLen * math.sin(aoaRad) : -aoaLen * math.sin(aoaRad)),
    );
    canvas.drawLine(
      Offset(ox, oy),
      aoaEnd,
      Paint()
        ..color = AppColors.textDimmed.withAlpha(80)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Loft wedge shading (between AoA line and launch line)
    if (shot.dynamicLoft != null) {
      final dynRad = shot.dynamicLoft! * math.pi / 180.0;
      final loftLen = lineLen * 0.35;
      final loftEnd = Offset(
        ox - loftLen * math.cos(dynRad),
        oy - loftLen * math.sin(dynRad),
      );
      final wedge = Path()
        ..moveTo(ox, oy)
        ..lineTo(launchEnd.dx, launchEnd.dy)
        ..lineTo(loftEnd.dx, loftEnd.dy)
        ..close();
      canvas.drawPath(wedge, Paint()..color = _kTeal.withAlpha(18));
      canvas.drawLine(
        Offset(ox, oy),
        loftEnd,
        Paint()
          ..color = _kTeal.withAlpha(90)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Ball at launch end
    canvas.drawCircle(
        launchEnd, 5.5, Paint()..color = Colors.white.withAlpha(210));
    canvas.drawCircle(launchEnd, 3.5, Paint()..color = _kTeal);

    // Impact dot
    canvas.drawCircle(
        Offset(ox, oy),
        4,
        Paint()..color = AppColors.textDimmed.withAlpha(150));
  }

  @override
  bool shouldRepaint(_LoftPainter old) => old.shot != shot;
}

// ── Impact section (face view + impact overlay) ───────────────────────────────

class _ImpactSection extends StatelessWidget {
  final ShotData shot;
  final List<ShotData> allShots;
  final ClubType clubType;
  final String? clubId;
  final bool showHeatmap;

  const _ImpactSection({
    required this.shot,
    required this.allShots,
    required this.clubType,
    required this.clubId,
    required this.showHeatmap,
  });

  static String _assetPath(ClubType type, String? id) {
    if (id == 'dr')  return 'assets/clubs/driver-impact.png';
    if (id == 'mdr') return 'assets/clubs/mini-impact.png';
    return switch (type) {
      ClubType.wood      => 'assets/clubs/wood-impact.jpg',
      ClubType.miniDriver => 'assets/clubs/mini-impact.png',
      ClubType.hybrid    => 'assets/clubs/hybrid-impact.jpg',
      ClubType.iron      => 'assets/clubs/iron-impact.jpg',
      ClubType.wedge     => 'assets/clubs/wedge-impact.jpg',
      ClubType.putter    => 'assets/clubs/iron-impact.jpg',
    };
  }

  static double _widthScale(ClubType type, String? id) {
    if (id == 'dr')  return 1.00;
    if (id == 'mdr') return 0.85;
    return switch (type) {
      ClubType.wood      => 0.70,
      ClubType.miniDriver => 0.85,
      ClubType.hybrid    => 0.55,
      ClubType.iron      => 0.58,
      ClubType.wedge     => 0.62,
      ClubType.putter    => 0.52,
    };
  }

  static double _aspectRatio(ClubType type, String? id) {
    if (id == 'dr')  return 1.12;
    if (id == 'mdr') return 1.15;
    return switch (type) {
      ClubType.wood      => 1.45,
      ClubType.miniDriver => 1.15,
      ClubType.hybrid    => 1.41,
      ClubType.iron      => 1.30,
      ClubType.wedge     => 1.30,
      ClubType.putter    => 1.30,
    };
  }

  static double _cropTop(ClubType type, String? id) {
    if (id == 'dr')  return 0.50;
    if (id == 'mdr') return 0.35;
    return switch (type) {
      ClubType.wood      => 0.45,
      ClubType.miniDriver => 0.35,
      ClubType.hybrid    => 0.42,
      ClubType.iron      => 0.32,
      ClubType.wedge || ClubType.putter => 0.32,
    };
  }

  static List<double> _faceBounds(ClubType type, String? id) {
    if (id == 'dr')  return [0.022, 0.714, 0.702, 0.928];
    if (id == 'mdr') return [0.096, 0.647, 0.716, 0.827];
    return switch (type) {
      ClubType.wood || ClubType.miniDriver =>
        [0.064, 0.723, 0.664, 0.903],
      ClubType.hybrid =>
        [0.087, 0.732, 0.627, 0.912],
      ClubType.iron =>
        [0.092, 0.717, 0.632, 0.917],
      ClubType.wedge || ClubType.putter =>
        [0.058, 0.725, 0.558, 0.925],
    };
  }

  @override
  Widget build(BuildContext context) {
    final path       = _assetPath(clubType, clubId);
    final wScale     = _widthScale(clubType, clubId);
    final fullAspect = _aspectRatio(clubType, clubId);
    final cropTop    = _cropTop(clubType, clubId);
    final croppedAspect = fullAspect / (1.0 - cropTop);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth * 0.72 * wScale;
                final maxH = constraints.maxHeight * 0.88;
                double w = maxW;
                double h = w / croppedAspect;
                if (h > maxH) {
                  h = maxH;
                  w = h * croppedAspect;
                }
                final fullH = w / fullAspect;

                final fb = _faceBounds(clubType, clubId);
                final bounds = cropTop > 0
                    ? [
                        fb[0],
                        (fb[1] - cropTop) / (1.0 - cropTop),
                        fb[2],
                        (fb[3] - cropTop) / (1.0 - cropTop),
                      ]
                    : fb;

                return SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.bottomCenter,
                          maxWidth: w,
                          maxHeight: fullH,
                          child: SizedBox(
                            width: w,
                            height: fullH,
                            child: Image.asset(
                              path,
                              fit: BoxFit.fill,
                              color: const Color(0xFF12151E),
                              colorBlendMode: BlendMode.multiply,
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _ImpactOverlayPainter(
                          shot: shot,
                          allShots: allShots,
                          showHeatmap: showHeatmap,
                          faceBounds: bounds,
                          accent: context.accent,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ClubMetric(
                  label: 'CARRY',
                  value: '${shot.carry.toStringAsFixed(1)} yds'),
              _ClubMetric(
                label: 'HORIZ. IMP.',
                value: shot.horizontalImpact != null
                    ? '${shot.horizontalImpact!.abs().toStringAsFixed(1)} mm '
                        '${shot.horizontalImpact! >= 0 ? 'T' : 'H'}'
                    : '--',
              ),
              _ClubMetric(
                label: 'VERT. IMP.',
                value: shot.verticalImpact != null
                    ? '${shot.verticalImpact!.abs().toStringAsFixed(1)} mm '
                        '${shot.verticalImpact! >= 0 ? 'Hi' : 'Lo'}'
                    : '--',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Impact overlay painter ────────────────────────────────────────────────────

class _ImpactOverlayPainter extends CustomPainter {
  final ShotData shot;
  final List<ShotData> allShots;
  final bool showHeatmap;
  final List<double> faceBounds;
  final Color accent;

  _ImpactOverlayPainter({
    required this.shot,
    required this.allShots,
    required this.showHeatmap,
    required this.faceBounds,
    required this.accent,
  });

  static const double _maxMm = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fL = size.width  * faceBounds[0];
    final fT = size.height * faceBounds[1];
    final fR = size.width  * faceBounds[2];
    final fB = size.height * faceBounds[3];
    final fW = fR - fL;
    final fH = fB - fT;
    final cx = fL + fW / 2;
    final cy = fT + fH / 2;

    // Crosshair
    final hp = Paint()..color = AppColors.border2..strokeWidth = 0.5;
    canvas.drawLine(Offset(fL + 4, cy), Offset(fR - 2, cy), hp);
    canvas.drawLine(Offset(cx, fT + 4), Offset(cx, fB - 4), hp);

    // Zone labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, Offset pos) {
      tp
        ..text = TextSpan(
            text: t,
            style: AppTextStyles.sans(size: 8, color: AppColors.textDimmed))
        ..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    label('TOE',  Offset(fL + 14, fT + 8));
    label('HEEL', Offset(fR - 16, fT + 8));
    label('HI',   Offset(cx, fT + 8));
    label('LO',   Offset(cx, fB - 8));

    if (showHeatmap) {
      _drawHeatmap(canvas, fL, fT, fW, fH, cx, cy);
    } else {
      _drawAllDots(canvas, cx, cy, fW, fH);
    }
    _drawCurrentDot(canvas, cx, cy, fW, fH);
  }

  double _toX(double mm, double cx, double fW) =>
      cx - (mm / _maxMm) * (fW / 2 - 14);
  double _toY(double mm, double cy, double fH) =>
      cy - (mm / _maxMm) * (fH / 2 - 10);

  void _drawAllDots(Canvas canvas, double cx, double cy, double fW, double fH) {
    final p = Paint()..color = Colors.white.withAlpha(160);
    for (final s in allShots) {
      if (s == shot) continue;
      if (s.horizontalImpact == null || s.verticalImpact == null) continue;
      canvas.drawCircle(
        Offset(_toX(s.horizontalImpact!, cx, fW),
               _toY(s.verticalImpact!, cy, fH)),
        3,
        p,
      );
    }
  }

  void _drawHeatmap(Canvas canvas, double fL, double fT, double fW, double fH,
      double cx, double cy) {
    const cols = 9;
    const rows = 7;
    final cellW = fW / cols;
    final cellH = fH / rows;
    final grid = List.generate(rows, (_) => List.filled(cols, 0));
    var maxCount = 0;

    for (final s in allShots) {
      if (s.horizontalImpact == null || s.verticalImpact == null) continue;
      final px = _toX(s.horizontalImpact!, cx, fW);
      final py = _toY(s.verticalImpact!, cy, fH);
      final c  = ((px - fL) / cellW).floor().clamp(0, cols - 1);
      final r  = ((py - fT) / cellH).floor().clamp(0, rows - 1);
      grid[r][c]++;
      if (grid[r][c] > maxCount) maxCount = grid[r][c];
    }
    if (maxCount == 0) return;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final count = grid[r][c];
        if (count == 0) continue;
        final t = count / maxCount;
        final color = Color.lerp(
          const Color(0xFF1A3A6A),
          const Color(0xFFE05A2B),
          t,
        )!.withAlpha((t * 200 + 40).round().clamp(0, 255));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(fL + c * cellW, fT + r * cellH, cellW, cellH),
              const Radius.circular(2)),
          Paint()..color = color,
        );
      }
    }
  }

  void _drawCurrentDot(
      Canvas canvas, double cx, double cy, double fW, double fH) {
    if (shot.horizontalImpact == null || shot.verticalImpact == null) return;
    final ix = _toX(shot.horizontalImpact!, cx, fW);
    final iy = _toY(shot.verticalImpact!, cy, fH);
    canvas.drawCircle(
        Offset(ix, iy),
        14,
        Paint()
          ..color = accent.withAlpha(30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(
        Offset(ix, iy),
        9,
        Paint()
          ..color = accent.withAlpha(200)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(Offset(ix, iy), 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_ImpactOverlayPainter old) =>
      old.shot != shot ||
      old.allShots != allShots ||
      old.showHeatmap != showHeatmap ||
      old.accent != accent;
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _ClubMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ClubMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: AppTextStyles.sans(
                size: 8, weight: FontWeight.w400, color: AppColors.textDimmed)),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.mono(size: 14)),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool active;
  const _Toggle({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 16,
      decoration: BoxDecoration(
        color: active ? context.accentSubtle : AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? context.accent : AppColors.border2),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            right: active ? 2 : null,
            left:  active ? null : 2,
            top: 2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: active ? context.accent : AppColors.textDimmed,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
