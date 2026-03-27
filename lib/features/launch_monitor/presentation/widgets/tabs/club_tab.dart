import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/theme.dart';

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
  int _subTab = 0; // 0 = Top, 1 = Impact
  bool _showAvg = false;
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

    final last = widget.selectedShot ?? widget.shots.first;
    final avg = ShotData.averageOf(widget.shots);
    final display = _showAvg ? avg : last;
    final club = _clubFor(last);
    final clubType = club?.type ?? ClubType.iron;

    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _SubTab(label: 'Top', active: _subTab == 0,
                  onTap: () => setState(() => _subTab = 0)),
              const SizedBox(width: 8),
              _SubTab(label: 'Impact', active: _subTab == 1,
                  onTap: () => setState(() => _subTab = 1)),
              const Spacer(),
              if (_subTab == 1) ...[
                GestureDetector(
                  onTap: () => setState(() => _showHeatmap = !_showHeatmap),
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
        Expanded(
          child: _subTab == 0
              ? _TopView(shot: display, clubType: clubType, clubId: last.clubId)
              : _ImpactView(
                  shot: display,
                  allShots: widget.shots,
                  clubType: clubType,
                  clubId: last.clubId,
                  showHeatmap: _showHeatmap,
                ),
        ),
      ],
    );
  }
}

// ── Sub-tab chip ──────────────────────────────────────────────────────────────

class _SubTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SubTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSubtle : Colors.transparent,
          border: Border.all(
              color: active ? AppColors.accent : AppColors.border2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: AppTextStyles.sans(
              size: 11,
              weight: FontWeight.w400,
              color: active ? AppColors.accent : AppColors.textMuted,
            )),
      ),
    );
  }
}

// ── Top view ──────────────────────────────────────────────────────────────────

class _TopView extends StatelessWidget {
  final ShotData shot;
  final ClubType clubType;
  final String? clubId;

  const _TopView(
      {required this.shot, required this.clubType, required this.clubId});

  static String _assetPath(ClubType type, String? id) {
    if (id == 'dr') return 'assets/clubs/driver-top.jpg';
    if (id == 'mdr') return 'assets/clubs/mini-top.png';
    return switch (type) {
      ClubType.wood => 'assets/clubs/wood-top.jpg',
      ClubType.miniDriver => 'assets/clubs/mini-top.png',
      ClubType.hybrid => 'assets/clubs/hybrid-top.jpg',
      ClubType.iron => 'assets/clubs/iron-top.jpg',
      ClubType.wedge => 'assets/clubs/wedge-top.jpg',
      ClubType.putter => 'assets/clubs/iron-top.jpg',
    };
  }

  // Crown width relative to driver = 1.0 (based on heel-to-toe mm).
  static double _scale(ClubType type, String? id) {
    if (id == 'dr') return 1.00;
    if (id == 'mdr') return 0.84;
    return switch (type) {
      ClubType.wood => 0.80,
      ClubType.miniDriver => 0.84,
      ClubType.hybrid => 0.64,
      ClubType.iron => 0.54,
      ClubType.wedge => 0.56,
      ClubType.putter => 0.50,
    };
  }

  // Natural width/height ratios from trimmed product photos (all portrait).
  // driver-top.jpg 314×811, mini-top.png 618×711, wood-top.jpg 578×1153,
  // hybrid-top.jpg 431×1123, iron-top.jpg 193×743, wedge-top.jpg 243×1050
  static double _topAspect(ClubType type, String? id) {
    if (id == 'dr') return 314.0 / 811.0;
    if (id == 'mdr') return 618.0 / 711.0;
    return switch (type) {
      ClubType.wood => 578.0 / 1153.0,
      ClubType.miniDriver => 618.0 / 711.0,
      ClubType.hybrid => 431.0 / 1123.0,
      ClubType.iron => 193.0 / 743.0,
      ClubType.wedge || ClubType.putter => 243.0 / 1050.0,
    };
  }

  // Hosel rotation pivot as fractions of the original image dimensions.
  // Calibrated pixel coords: driver(17,294)/314×811, mini(119,328)/618×711,
  //   wood(43,413)/578×1153, hybrid(63,379)/431×1123,
  //   iron(15,230)/193×743, wedge(19,210)/243×1050
  static Offset _topPivotFrac(ClubType type, String? id) {
    if (id == 'dr')  return const Offset(0.0541, 0.3625); // 17/314, 294/811
    if (id == 'mdr') return const Offset(0.1925, 0.4613); // 119/618, 328/711
    return switch (type) {
      ClubType.wood       => const Offset(0.0744, 0.3582), // 43/578, 413/1153
      ClubType.miniDriver => const Offset(0.1925, 0.4613),
      ClubType.hybrid     => const Offset(0.1462, 0.3375), // 63/431, 379/1123
      ClubType.iron       => const Offset(0.0777, 0.3096), // 15/193, 230/743
      ClubType.wedge || ClubType.putter =>
        const Offset(0.0782, 0.2000),                       // 19/243, 210/1050
    };
  }

  // For face-on images (face at top): fraction of image height to crop at bottom.
  static double _cropFrac(ClubType type, String? id) {
    if (id == 'dr') return 0.60;
    return switch (type) {
      ClubType.wood                     => 0.56,
      ClubType.hybrid                   => 0.56,
      ClubType.iron                     => 0.52,
      ClubType.wedge || ClubType.putter => 0.52,
      _                                 => 0.0,
    };
  }

  // Mini-driver uses a crown-view image (face at image bottom).
  static bool _isCrownView(String? id, ClubType type) =>
      id == 'mdr' || type == ClubType.miniDriver;

  @override
  Widget build(BuildContext context) {
    final path = _assetPath(clubType, clubId);
    final scale = _scale(clubType, clubId);
    final imgAspect = _topAspect(clubType, clubId);
    final piv = _topPivotFrac(clubType, clubId);
    final isCrown = _isCrownView(clubId, clubType);
    final faceAngle = shot.faceAngle ?? 0.0;
    final faceRad = faceAngle * math.pi / 180.0;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvasW = constraints.maxWidth;
                final canvasH = constraints.maxHeight;

                var imgW = canvasW * scale;
                var imgH = imgW / imgAspect;
                var imgLeft = canvasW / 2.0 - imgW / 2.0;

                double imgTop, dispH;
                double faceCx, faceCy;

                if (isCrown) {
                  // Crown view (mini-top): face at image bottom.
                  // Anchor bottom at 55% of canvas; Stack clips the shaft above.
                  imgTop = canvasH * 0.55 - imgH;
                  dispH  = imgH;
                  final hoselX = imgLeft + piv.dx * imgW;
                  final hoselY = imgTop  + piv.dy * imgH;
                  final dx = (0.5 - piv.dx) * imgW;
                  final dy = (1.0 - piv.dy) * imgH;
                  faceCx = hoselX + dx * math.cos(faceRad)
                                  + dy * math.sin(faceRad);
                  faceCy = hoselY - dx * math.sin(faceRad)
                                  + dy * math.cos(faceRad);
                } else {
                  // Face-on view (driver, wood, hybrid, iron, wedge):
                  // Face/leading edge at TOP; shaft hidden by cropping the bottom.
                  // Cap visible height to fit within the canvas on wide screens.
                  final cropFrac = _cropFrac(clubType, clubId);
                  final rawDispH = imgH * (1.0 - cropFrac);
                  dispH = math.min(rawDispH, canvasH * 0.85);
                  if (dispH < rawDispH) {
                    imgH = dispH / (1.0 - cropFrac);
                    imgW = imgH * imgAspect;
                    imgLeft = canvasW / 2.0 - imgW / 2.0;
                  }
                  imgTop = (canvasH - dispH) / 2.0;
                  // Indicator originates at the calibrated hosel position.
                  // The image rotates around the same point, so it stays fixed.
                  faceCx = imgLeft + piv.dx * imgW;
                  faceCy = imgTop  + piv.dy * imgH;
                }

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Container(color: AppColors.surface),
                    Positioned(
                      left: imgLeft,
                      top: imgTop,
                      width: imgW,
                      height: dispH,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: isCrown
                              ? Alignment.bottomCenter
                              : Alignment.topCenter,
                          maxWidth: imgW,
                          maxHeight: imgH,
                          child: SizedBox(
                            width: imgW,
                            height: imgH,
                            child: Transform.rotate(
                              angle: faceRad,
                              alignment: Alignment(
                                2 * piv.dx - 1,
                                2 * piv.dy - 1,
                              ),
                              child: Image.asset(path, fit: BoxFit.fill),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Overlay: only drawn when face/path data is available.
                    if (shot.faceAngle != null || shot.swingPath != null)
                      CustomPaint(
                        painter: _TopOverlayPainter(
                          shot: shot,
                          faceCx: faceCx,
                          faceCy: faceCy,
                        ),
                        child: const SizedBox.expand(),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ClubMetric(
                label: 'Swing path',
                value: shot.swingPath != null
                    ? '${shot.swingPath!.abs().toStringAsFixed(1)}°'
                        ' ${shot.swingPath! >= 0 ? 'R' : 'L'}'
                    : '--',
              ),
              _ClubMetric(
                label: 'Face angle',
                value: shot.faceAngle != null
                    ? '${shot.faceAngle!.abs().toStringAsFixed(1)}°'
                        ' ${shot.faceAngle! >= 0 ? 'R' : 'L'}'
                    : '--',
              ),
              _ClubMetric(
                label: 'Ang. att.',
                value: shot.angleOfAttack != null
                    ? '${shot.angleOfAttack!.toStringAsFixed(1)}°'
                    : '--',
              ),
              _ClubMetric(
                label: 'Dyn. loft',
                value: shot.dynamicLoft != null
                    ? '${shot.dynamicLoft!.toStringAsFixed(1)}°'
                    : '--',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Overlay painter: dashed target reference + face-to-target line (teal) +
// club path line (orange) + value text in chart area (Foresight-style).
// [faceCx, faceCy] is the ball/contact point at the leading edge of the club.
class _TopOverlayPainter extends CustomPainter {
  final ShotData shot;
  final double faceCx;
  final double faceCy;

  _TopOverlayPainter({
    required this.shot,
    required this.faceCx,
    required this.faceCy,
  });

  void _drawDashed(Canvas canvas, Offset start, Offset end, Paint paint,
      {double dash = 6, double gap = 4}) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final total = math.sqrt(dx * dx + dy * dy);
    if (total == 0) return;
    final ux = dx / total;
    final uy = dy / total;
    double dist = 0;
    bool on = true;
    while (dist < total) {
      final seg = math.min(dist + (on ? dash : gap), total);
      if (on) {
        canvas.drawLine(
          Offset(start.dx + ux * dist, start.dy + uy * dist),
          Offset(start.dx + ux * seg, start.dy + uy * seg),
          paint,
        );
      }
      dist = seg;
      on = !on;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const teal = Color(0xFF00D4CC);
    const orange = Color(0xFFF59E42);

    // Dashed vertical target reference line through the face x-centre
    _drawDashed(
      canvas,
      Offset(faceCx, 8),
      Offset(faceCx, size.height - 8),
      Paint()
        ..color = AppColors.textDimmed.withAlpha(70)
        ..strokeWidth = 1.0,
    );

    // Lines extend 40% of canvas height from the face anchor point
    final lineLen = size.height * 0.40;

    // Face-to-target line (teal) — originates at face, rotated by faceAngle
    final faceAngle = shot.faceAngle ?? 0.0;
    final faceRad = faceAngle * math.pi / 180.0;
    canvas.drawLine(
      Offset(faceCx + lineLen * math.sin(faceRad),
          faceCy - lineLen * math.cos(faceRad)),
      Offset(faceCx - lineLen * math.sin(faceRad),
          faceCy + lineLen * math.cos(faceRad)),
      Paint()
        ..color = teal
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Swing path line (orange) — originates at face, rotated by swingPath
    final swingPath = shot.swingPath ?? 0.0;
    final swingRad = swingPath * math.pi / 180.0;
    canvas.drawLine(
      Offset(faceCx + lineLen * math.sin(swingRad),
          faceCy - lineLen * math.cos(swingRad)),
      Offset(faceCx - lineLen * math.sin(swingRad),
          faceCy + lineLen * math.cos(swingRad)),
      Paint()
        ..color = orange
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Ball/contact dot at face anchor
    canvas.drawCircle(
        Offset(faceCx, faceCy), 5, Paint()..color = Colors.white.withAlpha(200));
    canvas.drawCircle(
        Offset(faceCx, faceCy), 3, Paint()..color = AppColors.accent);

    // Value overlays (top-left of chart area)
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Color color, Offset pos) {
      tp
        ..text = TextSpan(
          text: text,
          style: AppTextStyles.mono(size: 11, color: color)
              .copyWith(fontWeight: FontWeight.w600),
        )
        ..layout();
      tp.paint(canvas, pos);
    }

    final faceDir = faceAngle > 0 ? 'R' : faceAngle < 0 ? 'L' : '—';
    drawLabel(
      '${faceAngle.abs().toStringAsFixed(1)}° $faceDir  FACE TO TGT',
      teal,
      const Offset(12, 10),
    );

    final pathDir = swingPath > 0 ? 'I→O' : swingPath < 0 ? 'O→I' : '—';
    drawLabel(
      '${swingPath.abs().toStringAsFixed(1)}° $pathDir  PATH',
      orange,
      const Offset(12, 26),
    );
  }

  @override
  bool shouldRepaint(_TopOverlayPainter old) =>
      old.shot != shot || old.faceCx != faceCx || old.faceCy != faceCy;
}

// ── Impact view ───────────────────────────────────────────────────────────────

class _ImpactView extends StatelessWidget {
  final ShotData shot;
  final List<ShotData> allShots;
  final ClubType clubType;
  final String? clubId;
  final bool showHeatmap;

  const _ImpactView({
    required this.shot,
    required this.allShots,
    required this.clubType,
    required this.clubId,
    required this.showHeatmap,
  });

  static String _assetPath(ClubType type, String? id) {
    if (id == 'dr') return 'assets/clubs/driver-impact.png';
    if (id == 'mdr') return 'assets/clubs/mini-impact.png';
    return switch (type) {
      ClubType.wood => 'assets/clubs/wood-impact.jpg',
      ClubType.miniDriver => 'assets/clubs/mini-impact.png',
      ClubType.hybrid => 'assets/clubs/hybrid-impact.jpg',
      ClubType.iron => 'assets/clubs/iron-impact.jpg',
      ClubType.wedge => 'assets/clubs/wedge-impact.jpg',
      ClubType.putter => 'assets/clubs/iron-impact.jpg',
    };
  }

  // Width relative to driver face = 1.0
  // Based on real face heel-to-toe widths (mm):
  //   Driver ~115, Mini ~98, 3w ~80, Hybrid ~63, Iron ~67, Wedge ~71
  static double _widthScale(ClubType type, String? id) {
    if (id == 'dr') return 1.00;
    if (id == 'mdr') return 0.85;
    return switch (type) {
      ClubType.wood => 0.70,
      ClubType.miniDriver => 0.85,
      ClubType.hybrid => 0.55,
      ClubType.iron => 0.58,
      ClubType.wedge => 0.62,
      ClubType.putter => 0.52,
    };
  }

  // Full-image aspect ratios (width/height) from trimmed product photos:
  //   driver-impact.png  754×672  = 1.12
  //   mini-impact.png    640×556  = 1.15
  //   wood-impact.jpg    497×343  = 1.45
  //   hybrid-impact.jpg  939×668  = 1.41
  //   iron-impact.jpg    710×545  = 1.30
  //   wedge-impact.jpg   720×554  = 1.30
  static double _aspectRatio(ClubType type, String? id) {
    if (id == 'dr') return 1.12;
    if (id == 'mdr') return 1.15;
    return switch (type) {
      ClubType.wood => 1.45,
      ClubType.miniDriver => 1.15,
      ClubType.hybrid => 1.41,
      ClubType.iron => 1.30,
      ClubType.wedge => 1.30,
      ClubType.putter => 1.30,
    };
  }

  // Fraction of the image top to crop so only the club head + ferrule is shown.
  // Removes shaft from all images for consistent, proportional head display.
  static double _cropTop(ClubType type, String? id) {
    if (id == 'dr')  return 0.50;
    if (id == 'mdr') return 0.35;
    return switch (type) {
      ClubType.wood       => 0.45,
      ClubType.miniDriver => 0.35,
      ClubType.hybrid     => 0.42,
      ClubType.iron       => 0.32,
      ClubType.wedge || ClubType.putter => 0.32,
    };
  }

  // Face bounds [fL, fT, fR, fB] as fractions of the displayed image.
  // Centre of each rect = user-calibrated sweet spot (0,0 mm impact origin):
  //   driver-impact.png  754×672  SP=(273,594)  → cx=0.362, cy=0.884
  //   mini-impact.png    640×556  SP=(260,410)  → cx=0.406, cy=0.737
  //   wood-impact.jpg    497×343  SP=(181,279)  → cx=0.364, cy=0.813
  //   hybrid-impact.jpg  939×668  SP=(335,549)  → cx=0.357, cy=0.822
  //   iron-impact.jpg    710×545  SP=(257,445)  → cx=0.362, cy=0.817
  //   wedge-impact.jpg   720×554  SP=(222,457)  → cx=0.308, cy=0.825
  static List<double> _faceBounds(ClubType type, String? id) {
    if (id == 'dr')  return [0.022, 0.714, 0.702, 0.928];  // cx=0.362, cy=0.821
    if (id == 'mdr') return [0.096, 0.647, 0.716, 0.827]; // cx=0.406, cy=0.737
    return switch (type) {
      ClubType.wood || ClubType.miniDriver =>
        [0.064, 0.723, 0.664, 0.903],                      // cx=0.364, cy=0.813
      ClubType.hybrid =>
        [0.087, 0.732, 0.627, 0.912],                      // cx=0.357, cy=0.822
      ClubType.iron =>
        [0.092, 0.717, 0.632, 0.917],                      // cx=0.362, cy=0.817
      ClubType.wedge || ClubType.putter =>
        [0.058, 0.725, 0.558, 0.925],                      // cx=0.308, cy=0.825
    };
  }

  @override
  Widget build(BuildContext context) {
    final path = _assetPath(clubType, clubId);
    final wScale = _widthScale(clubType, clubId);
    final fullAspect = _aspectRatio(clubType, clubId);
    final cropTop = _cropTop(clubType, clubId);
    // Cropped aspect: same width, shorter height → wider ratio
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
                // Full image height at this display width (before crop)
                final fullH = w / fullAspect;

                // Remap face bounds from full-image fractions to cropped fractions
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
                      // Club face photo cropped to remove shaft above ferrule.
                      // OverflowBox lets the image render at full height; ClipRect
                      // hides everything above the cropped region.
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
                      // Impact data overlay: crosshair + dots/heatmap + current shot
                      CustomPaint(
                        painter: _ImpactOverlayPainter(
                          shot: shot,
                          allShots: allShots,
                          showHeatmap: showHeatmap,
                          faceBounds: bounds,
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
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

// Overlay painter: impact crosshair + shot dots/heatmap + current shot ring.
// faceBounds [fL, fT, fR, fB] are fractions of the canvas size, describing
// the approximate club face region within the photo.
class _ImpactOverlayPainter extends CustomPainter {
  final ShotData shot;
  final List<ShotData> allShots;
  final bool showHeatmap;
  final List<double> faceBounds; // [fL, fT, fR, fB] fractions

  _ImpactOverlayPainter({
    required this.shot,
    required this.allShots,
    required this.showHeatmap,
    required this.faceBounds,
  });

  static const double _maxMm = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fL = size.width * faceBounds[0];
    final fT = size.height * faceBounds[1];
    final fR = size.width * faceBounds[2];
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
    label('TOE', Offset(fL + 14, fT + 8));
    label('HEEL', Offset(fR - 16, fT + 8));
    label('HI', Offset(cx, fT + 8));
    label('LO', Offset(cx, fB - 8));

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
      final c = ((px - fL) / cellW).floor().clamp(0, cols - 1);
      final r = ((py - fT) / cellH).floor().clamp(0, rows - 1);
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
          ..color = AppColors.accentSubtle
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(
        Offset(ix, iy),
        9,
        Paint()
          ..color = AppColors.accent.withAlpha(200)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(Offset(ix, iy), 4, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_ImpactOverlayPainter old) =>
      old.shot != shot ||
      old.allShots != allShots ||
      old.showHeatmap != showHeatmap;
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
        color: active ? AppColors.accentSubtle : AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? AppColors.accent : AppColors.border2),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            right: active ? 2 : null,
            left: active ? null : 2,
            top: 2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.textDimmed,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
