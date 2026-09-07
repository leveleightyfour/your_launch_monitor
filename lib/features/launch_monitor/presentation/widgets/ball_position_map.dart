/// Plan view of the mat with the ball on it.
///
/// Answers "where is the ball, and will the club be measured from there?" —
/// the question behind the device manual's ready-zone page. The geometry and
/// the caveats on it live in [BallPosition]; this only draws.
///
/// Drawn as a mat rather than as a plot. The first cut was a grid with a dot on
/// it — honest, but it asks the golfer to read a chart while holding a club.
/// Turf, a marked zone and a white ball are recognisable without being read.
/// The greens are the app's existing course surfaces, the same ones the flight
/// view lands shots on, so this is that world seen from above; the accent stays
/// out of it entirely, because the accent means "your shot" and a ball sitting
/// on the mat is not a shot yet.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:omni_sniffer/features/launch_monitor/application/ball_position_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/ball_position.dart';
import 'package:omni_sniffer/shared/app_icons.dart';
import 'package:omni_sniffer/shared/theme.dart';

const _ink42 = Color(0x6BFFFFFF);
const _ink55 = Color(0x8CFFFFFF);

/// Mown band width on the mat, in millimetres. The bands run across the target
/// line: this whole feature is about how far up the mat the ball sits, and
/// banding at right angles to that is what makes the distance readable.
const double _mowBandMm = 100;

class BallPositionMap extends StatelessWidget {
  final BallPosition? position;

  /// Ball detection has to be armed for a position to mean anything. When it
  /// isn't, the map says so rather than showing an empty mat, which would
  /// read as "no ball there" instead of "not looking".
  final bool detecting;

  /// The face the map letters its labels in. Defaults to the design's mono.
  ///
  /// Injectable because [GoogleFonts] loads over the network on first use, and
  /// capturing a rendered frame in a test has to run outside the fake clock —
  /// which is exactly when that fetch fires and fails. A painter should not be
  /// pulling resources mid-paint anyway.
  final TextStyle? labelStyle;

  const BallPositionMap({
    super.key,
    required this.position,
    required this.detecting,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    const bounds = MatBounds.mat;
    return AspectRatio(
      // The drawn area is whatever holds the monitor and the zone, which the
      // manual puts well off to one side — not a square centred on the origin.
      aspectRatio: bounds.widthMm / bounds.depthMm,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: BallPositionMapPainter(
            position: position,
            detecting: detecting,
            labelStyle:
                labelStyle ?? GoogleFonts.dmMono(fontWeight: FontWeight.w400),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

@visibleForTesting
class BallPositionMapPainter extends CustomPainter {
  final BallPosition? position;
  final bool detecting;
  final TextStyle labelStyle;

  /// Drawn at status-cluster size, where lettering, banding and the target line
  /// are noise rather than information.
  final bool compact;

  /// Ball-state colour for the mat's edge. This is the old status dot's job,
  /// folded in: hue answers "is there a ball and is it settled" from across the
  /// bay, the picture inside answers "and is it in the right place" up close.
  final Color? edgeColour;

  BallPositionMapPainter({
    required this.position,
    required this.detecting,
    this.labelStyle = const TextStyle(),
    this.compact = false,
    this.edgeColour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bounds = MatBounds.mat;
    final pxPerMm = size.width / bounds.widthMm;

    // Depth runs up the map — the target is away from the golfer, which is
    // away from the viewer of a tablet propped at the mat. Canvas Y grows
    // downward, hence the flip.
    Offset toCanvas(double depthMm, double lateralMm) => Offset(
      (lateralMm - bounds.minLateralMm) * pxPerMm,
      size.height -
          (depthMm - bounds.minDepthMm) / bounds.depthMm * size.height,
    );

    final mat = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(mat);

    _paintTurf(canvas, size, toCanvas, bounds, banded: !compact);
    // At status-cluster size the zone shrinks to a few pixels — and shrinks
    // further whenever the view rescales to keep the ball in frame — so it
    // stops reading as "the area to aim for" and starts reading as a second,
    // unexplained dot. The border colour already carries the ball state; the
    // picture inside is just where the ball is.
    if (!compact) _paintTargetLine(canvas, size, toCanvas);

    final p = position;
    final showBall = detecting && p != null && p.detected;
    final ballAt = showBall
        ? _ballCanvasPosition(p, toCanvas, bounds, pxPerMm)
        : null;
    if (ballAt != null) _paintBall(canvas, p!, ballAt, pxPerMm);

    canvas.restore();

    // Edge last, over the clip, so the mat reads as an object with a lip.
    canvas.drawRRect(
      mat,
      Paint()
        ..color = edgeColour ?? const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeColour != null ? 2 : (compact ? 1 : 2),
    );

    if (compact) return;

    _paintTargetLabel(canvas, size);
    if (showBall) {
      _paintVerdict(canvas, size, p, ballAt);
    } else {
      _paintEmptyState(canvas, size);
    }
  }

  /// Mown turf, banded across the target line.
  void _paintTurf(
    Canvas canvas,
    Size size,
    Offset Function(double, double) toCanvas,
    MatBounds bounds, {
    bool banded = true,
  }) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.turfFairway);
    if (!banded) return;

    final stripe = Paint()..color = AppColors.turfFairwayStripe;
    // Phased on the monitor, so the banding reads as distance out from it
    // rather than as an arbitrary pattern that shifts when the map resizes.
    for (
      var depth = bounds.minDepthMm - _mowBandMm;
      depth < bounds.maxDepthMm + _mowBandMm;
      depth += _mowBandMm * 2
    ) {
      final top = toCanvas(depth + _mowBandMm, 0).dy;
      final bottom = toCanvas(depth, 0).dy;
      canvas.drawRect(Rect.fromLTRB(0, top, size.width, bottom), stripe);
    }
  }

  /// The line the golfer is hitting down, out from the monitor.
  void _paintTargetLine(
    Canvas canvas,
    Size size,
    Offset Function(double, double) toCanvas,
  ) {
    final x = toCanvas(0, 0).dx;
    _dashedLine(
      canvas,
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = AppColors.targetLine.withAlpha(46)
        ..strokeWidth = 1.5,
    );
  }

  /// A golf ball: white, with the shadow that makes it sit *on* the turf rather
  /// than float above a chart.
  double get _ballRadius => compact ? 3.5 : 8.0;

  /// Where the ball lands on the canvas, inset by its own size: pinned to the
  /// exact edge, half of it falls outside the mat's clip and all the golfer
  /// sees is a sliver in a corner.
  Offset _ballCanvasPosition(
    BallPosition p,
    Offset Function(double, double) toCanvas,
    MatBounds bounds,
    double pxPerMm,
  ) {
    final inset = (_ballRadius + (compact ? 1 : 4)) / pxPerMm;
    final depth = p.depthMm.clamp(
      bounds.minDepthMm + inset,
      bounds.maxDepthMm - inset,
    );
    final lateral = p.lateralMm.clamp(
      bounds.minLateralMm + inset,
      bounds.maxLateralMm - inset,
    );
    return toCanvas(depth.toDouble(), lateral.toDouble());
  }

  void _paintBall(Canvas canvas, BallPosition p, Offset at, double pxPerMm) {
    final radius = _ballRadius;

    canvas.drawCircle(
      at.translate(1.5, 2.5),
      radius,
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // A ball the device has seen but not settled gets a ring; a settled one is
    // left clean. The quiet state is the good state, and amber is the only ring
    // colour that survives being drawn on turf — the green one this used to use
    // for "ready" was invisible against the zone it sat in.
    if (!p.ready) {
      final ring = radius + (compact ? 2 : 4);
      canvas.drawCircle(
        at,
        ring,
        Paint()..color = AppColors.severityWarning.withAlpha(56),
      );
      canvas.drawCircle(
        at,
        ring,
        Paint()
          ..color = AppColors.severityWarning
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 1.2 : 2,
      );
    }

    canvas.drawCircle(at, radius, Paint()..color = Colors.white);
    // Always outlined, so the ball keeps its edge on any turf behind it.
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = const Color(0x59000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1 : 1.5,
    );
  }

  void _paintTargetLabel(Canvas canvas, Size size) {
    final label = _text('TARGET', 8, _ink42, tracking: 2.0);
    label.paint(canvas, Offset((size.width - label.width) / 2, 10));

    // Painted, not an icon: a new glyph in the tree-shaken font can't ship in
    // an over-the-air patch.
    final tip = Offset(size.width / 2, 5);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 4, tip.dy + 4)
      ..lineTo(tip.dx + 4, tip.dy + 4)
      ..close();
    canvas.drawPath(path, Paint()..color = _ink42);
  }

  /// What the monitor says about the ball, in the monitor's own terms. The app
  /// no longer works out whether the ball is "in the zone" — the device's light
  /// already answers that, and every attempt to re-derive it from geometry
  /// produced a confident verdict about a box in the wrong place.
  void _paintVerdict(Canvas canvas, Size size, BallPosition p, Offset? ballAt) {
    final (message, colour) = p.ready
        ? ('READY', AppColors.turfGreenEdge)
        : ('NOT READY', AppColors.severityWarning);

    final label = _text(message, 8, colour, tracking: 1.4);
    // Bottom by default, but a ball down there would end up with lettering
    // struck through it — which is exactly the reading you came to look at.
    final bottom = size.height - label.height - 14;
    final clashes = ballAt != null && ballAt.dy > bottom - 14;
    _plate(canvas, label, size, clashes ? 26 : bottom);
  }

  void _paintEmptyState(Canvas canvas, Size size) {
    final label = _text(
      detecting ? 'NO BALL DETECTED' : 'DETECTION OFF',
      9,
      Colors.white70,
      tracking: 1.6,
    );
    _plate(canvas, label, size, (size.height - label.height) / 2 - 5);
  }

  /// Lettering on a dark plate, so it stays readable wherever the turf banding
  /// happens to fall behind it.
  void _plate(Canvas canvas, TextPainter label, Size size, double top) {
    final box = Rect.fromLTWH(
      (size.width - label.width) / 2 - 9,
      top,
      label.width + 18,
      label.height + 9,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = const Color(0xB3000000),
    );
    label.paint(canvas, Offset((size.width - label.width) / 2, top + 4));
  }

  TextPainter _text(
    String value,
    double size,
    Color colour, {
    double tracking = 1.2,
  }) {
    return TextPainter(
      text: TextSpan(
        text: value,
        style: labelStyle.copyWith(
          fontSize: size,
          color: colour,
          letterSpacing: tracking,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final total = (to - from).distance;
    if (total == 0) return;
    final step = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(from + step * travelled, from + step * end, paint);
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(BallPositionMapPainter old) =>
      old.position != position ||
      old.detecting != detecting ||
      old.compact != compact ||
      old.edgeColour != edgeColour ||
      old.labelStyle != labelStyle;
}

/// The map in a panel, wired to the live position.
///
/// Opened from the top bar's MAT chip. The chip stays the glanceable signal —
/// this is the thing you consult while setting up, not while standing over the
/// ball, so it is a deliberate action rather than something that appears on its
/// own.
class BallPositionPanel extends ConsumerWidget {
  const BallPositionPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const BallPositionPanel(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(ballPositionProvider);
    final detecting = ref.watch(
      launchMonitorProvider.select((s) => s.detecting),
    );

    return Dialog(
      backgroundColor: const Color(0xFF0B0C0F),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0x24FFFFFF)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          // Scrollable: the map is square, so on a short window — a phone in
          // landscape, a small desktop window — the map plus its two notes is
          // taller than the dialog gets, and a Column would simply clip the
          // caveat off the bottom.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'BALL POSITION',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        color: Colors.white,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: 'Close',
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(AppIcons.close, size: 15, color: _ink42),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                BallPositionMap(position: position, detecting: detecting),
                const SizedBox(height: 12),
                // The numbers, not just the picture. Everything above the raw
                // words is inference, so when the drawing and the mat disagree
                // this is what settles which of them is wrong.
                _Reading(position: position),
                const SizedBox(height: 12),
                Text(
                  'The monitor\'s light is the word on whether the ball is '
                  'ready to hit. This is where it is sitting.',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 10,
                    color: _ink55,
                    height: 1.5,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                // Says plainly which markings are measured and which are read
                // off a manual, rather than letting the drawing imply both are
                // known.
                Text(
                  'Position is measured from the monitor. The scale is read '
                  'off a third-party connector rather than vendor docs, so the '
                  'distances below are the numbers to check it against.',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    color: _ink42,
                    height: 1.5,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mat at status-cluster size, for the session top bar.
///
/// Same turf, same zone, same ball — with everything that needs reading
/// stripped out. At this size lettering, banding and the target line are noise;
/// what survives is the one relationship that matters at a glance: is the ball
/// inside the marked square or not. Tap for the full picture and the numbers.
class BallPositionMiniMap extends ConsumerWidget {
  /// Roughly the height of the chips it sits beside.
  final double size;

  const BallPositionMiniMap({super.key, this.size = 30});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(ballPositionProvider);
    final detecting = ref.watch(
      launchMonitorProvider.select((s) => s.detecting),
    );

    // Exactly the states the status dot used to signal, in the same hues, so
    // nothing is lost by there being one control here instead of two.
    final detected = position?.detected ?? false;
    final ready = position?.ready ?? false;
    final (edge, state) = !detecting
        ? (AppColors.textDimmed, 'Detection off')
        : ready
        ? (Colors.green, 'Ball ready')
        : detected
        ? (Colors.orange, 'Ball detected, not ready')
        : (Colors.red, 'No ball detected');

    final label = state;

    return Tooltip(
      message: '$label. Tap for the mat',
      child: Semantics(
        button: true,
        label: '$label. Show the ball position on the mat',
        child: GestureDetector(
          onTap: () => BallPositionPanel.show(context),
          behavior: HitTestBehavior.opaque,
          // Painted small, tapped at 44: the picture should not have to grow
          // to be hittable.
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: SizedBox(
                width: size,
                height: size,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: BallPositionMapPainter(
                      position: position,
                      detecting: detecting,
                      compact: true,
                      edgeColour: edge,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The live numbers under the map.
///
/// Shown rather than hidden behind a debug flag, because the transform above
/// them is read off a third-party connector rather than vendor documentation:
/// when the drawing looks wrong, this is what tells you whether the ball moved
/// or the arithmetic is off.
class _Reading extends StatelessWidget {
  final BallPosition? position;

  const _Reading({required this.position});

  @override
  Widget build(BuildContext context) {
    final p = position;
    // Nothing to report, and the map above has already said why — a second
    // "no ball" line under it would only repeat the picture.
    if (p == null || !p.detected) return const SizedBox.shrink();

    String mm(double v) => '${v >= 0 ? '+' : ''}${v.round()}';
    return Column(
      children: [
        Text(
          'FRONT ${mm(p.depthMm)}mm   SIDE ${mm(p.lateralMm)}mm',
          textAlign: TextAlign.center,
          style: AppTextStyles.mono(size: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 3),
        Text(
          'RAW ${p.rawX} / ${p.rawY} / ${p.rawZ}   '
          'STATE 0x${p.readyState.toRadixString(16).padLeft(2, '0')}',
          textAlign: TextAlign.center,
          style: AppTextStyles.mono(size: 9, color: AppColors.textDimmed),
        ),
      ],
    );
  }
}
