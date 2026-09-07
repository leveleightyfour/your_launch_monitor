import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/ball_position.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/ball_position_map.dart';

/// The map is square and spans ±[mapHalfRangeMm], so these convert a mat
/// coordinate to the pixel it must land on. Written out longhand rather than
/// reusing the painter's own maths — a test that shares the arithmetic it is
/// checking cannot catch the arithmetic being wrong.
const double _width = 300;

const _bounds = MatBounds.mat;
final double _height = _width * _bounds.depthMm / _bounds.widthMm;

double _pxX(double lateralMm) =>
    (lateralMm - _bounds.minLateralMm) / _bounds.widthMm * _width;
double _pxY(double depthMm) =>
    _height - (depthMm - _bounds.minDepthMm) / _bounds.depthMm * _height;

/// A real reading, at the correct scale: raw 10150 / 3090 is a ball sitting
/// inside the manual's ready zone.
const double _ballDepth = 508;
const double _ballLateral = 155;

/// Where rendered frames are dropped for eyeballing. Painter bugs that every
/// assertion passes are a real category — a legible frame is the only check for
/// those — so the rig writes them on every run.
final _outDir = Directory('${Directory.systemTemp.path}/ball_position_frames');

/// One rendered frame, as raw RGBA.
class _Frame {
  final Uint8List rgba;
  final int width;
  const _Frame(this.rgba, this.width);

  ({int r, int g, int b}) at(double x, double y) {
    final i = ((y.round() * width) + x.round()) * 4;
    return (r: rgba[i], g: rgba[i + 1], b: rgba[i + 2]);
  }
}

Future<_Frame> _render(
  WidgetTester tester, {
  required BallPosition? position,
  required bool detecting,
  required String name,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF08090B),
        body: Center(
          child: SizedBox(
            width: _width,
            height: _height,
            child: BallPositionMap(
              position: position,
              detecting: detecting,
              // A plain face, so capturing a frame never reaches for a
              // network font. The frames are checked on geometry, not type.
              labelStyle: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(BallPositionMap),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );

  late _Frame frame;
  // toImage completes on the raster thread, which the fake clock inside
  // testWidgets never advances — without runAsync this simply hangs.
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png != null) {
      _outDir.createSync(recursive: true);
      File(
        '${_outDir.path}/$name.png',
      ).writeAsBytesSync(png.buffer.asUint8List());
    }
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame = _Frame(raw!.buffer.asUint8List(), image.width);
    image.dispose();
  });
  return frame;
}

/// The ball is the only pure-white thing on the mat. Everything else — turf,
/// zone markings, lettering — sits well below this, so a near-white pixel means
/// a ball and nothing else.
bool _isBall(({int r, int g, int b}) c) => c.r > 230 && c.g > 230 && c.b > 230;

/// Full-strength amber. The faded warning band over turf never reaches this, so
/// a hit means the ring around the ball or a lettered warning.
bool _isAmber(({int r, int g, int b}) c) =>
    c.r > 150 && c.g > 80 && c.g < c.r && c.b < 90;

/// Whether any pixel in a box satisfies [test]. The marks here are small and
/// anti-aliased, so sampling a single point is a coin toss.
bool _anyIn(
  _Frame frame,
  bool Function(({int r, int g, int b})) test, {
  required double left,
  required double top,
  required double right,
  required double bottom,
}) {
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      // Guard on the rounded value: at() rounds, so a y of 299.6 passes a
      // bounds check against 300 and then reads pixel 300.
      if (x.round() < 0 ||
          y.round() < 0 ||
          x.round() >= _width ||
          y.round() >= _height) {
        continue;
      }
      if (test(frame.at(x, y))) return true;
    }
  }
  return false;
}

/// Whether a ball is drawn at a mat coordinate.
bool _ballAt(_Frame frame, {double depthMm = 0, double lateralMm = 0}) {
  final x = _pxX(lateralMm);
  final y = _pxY(depthMm);
  return _anyIn(
    frame,
    _isBall,
    left: x - 10,
    top: y - 10,
    right: x + 10,
    bottom: y + 10,
  );
}

/// The band along the bottom where the map letters its verdict.
final double _verdictTop = _height - 26;
final double _verdictBottom = _height - 4;

bool _amberVerdict(_Frame frame) => _anyIn(
  frame,
  _isAmber,
  left: 0,
  top: _verdictTop,
  right: _width - 1,
  bottom: _verdictBottom,
);

BallPosition _ball({
  double depthMm = 0,
  double lateralMm = 0,
  bool ready = true,
  bool detected = true,
}) => BallPosition(
  depthMm: depthMm,
  lateralMm: lateralMm,
  heightMm: 0,
  detected: detected,
  ready: ready,
);

void main() {
  group('the map puts the ball where the ball is', () {
    testWidgets('a ball toward the target is drawn toward the target', (
      tester,
    ) async {
      // Depth runs up the map. Getting this inverted is the single most likely
      // way for the drawing to be confidently wrong, and it would look
      // perfectly plausible on screen.
      final frame = await _render(
        tester,
        position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral),
        detecting: true,
        name: 'forward',
      );

      expect(
        _ballAt(frame, depthMm: _ballDepth, lateralMm: _ballLateral),
        isTrue,
        reason: 'the ball is drawn where the device says it is',
      );
      expect(
        _ballAt(frame, depthMm: _bounds.minDepthMm + 60, lateralMm: _ballLateral),
        isFalse,
        reason: 'and not at the mirrored spot behind it',
      );
    });

    testWidgets('a ball right of centre is drawn right of centre', (
      tester,
    ) async {
      final frame = await _render(
        tester,
        position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral),
        detecting: true,
        name: 'right',
      );

      expect(
        _ballAt(frame, depthMm: _ballDepth, lateralMm: _ballLateral),
        isTrue,
      );
      expect(
        _ballAt(frame, depthMm: _ballDepth, lateralMm: _bounds.minLateralMm + 60),
        isFalse,
      );
    });

    testWidgets('a ball beyond the drawn area stays whole at the edge', (
      tester,
    ) async {
      // It used to pin to the exact edge, where half of it fell outside the
      // clip and all you saw was a sliver in a corner. The window itself stays
      // put: rescaling it to chase the ball made the zone appear to move.
      final frame = await _render(
        tester,
        position: _ball(depthMm: _bounds.maxDepthMm + 900, lateralMm: _ballLateral),
        detecting: true,
        name: 'off-mat',
      );

      expect(
        _anyIn(
          frame,
          _isBall,
          left: 0,
          top: 0,
          right: _width - 1,
          bottom: _height - 1,
        ),
        isTrue,
        reason: 'somewhere on the map, whole, not clipped into a corner',
      );
    });
  });

  group('the map only claims what it knows', () {
    testWidgets('no ball detected draws no ball', (tester) async {
      final frame = await _render(
        tester,
        position: _ball(detected: false),
        detecting: true,
        name: 'no-ball',
      );
      expect(
        _ballAt(frame, depthMm: _ballDepth, lateralMm: _ballLateral),
        isFalse,
      );
    });

    testWidgets('detection off draws no ball even with a position', (
      tester,
    ) async {
      // A stale dot is worse than no dot: it says the ball is somewhere it may
      // well not be any more.
      final frame = await _render(
        tester,
        position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral),
        detecting: false,
        name: 'detection-off',
      );
      expect(
        _ballAt(frame, depthMm: _ballDepth, lateralMm: _ballLateral),
        isFalse,
      );
    });

    testWidgets('a ball seen but not settled reads differently from ready', (
      tester,
    ) async {
      // The ball stays white either way — it is a golf ball, and recolouring
      // it would cost the one shape here that needs no legend. Readiness is
      // the ring around it, so that is what has to differ.
      const inFront = _ballDepth;
      bool amberRing(_Frame f) => _anyIn(
        f,
        _isAmber,
        left: _pxX(_ballLateral) - 14,
        top: _pxY(inFront) - 14,
        right: _pxX(_ballLateral) + 14,
        bottom: _pxY(inFront) + 14,
      );

      final settled = await _render(
        tester,
        position: _ball(depthMm: inFront, lateralMm: _ballLateral),
        detecting: true,
        name: 'ready',
      );
      final unsettled = await _render(
        tester,
        position: _ball(
          depthMm: inFront,
          lateralMm: _ballLateral,
          ready: false,
        ),
        detecting: true,
        name: 'not-ready',
      );

      expect(
        _ballAt(settled, depthMm: inFront, lateralMm: _ballLateral),
        isTrue,
      );
      expect(
        _ballAt(unsettled, depthMm: inFront, lateralMm: _ballLateral),
        isTrue,
      );
      expect(amberRing(settled), isFalse, reason: 'ready reads green');
      expect(amberRing(unsettled), isTrue, reason: 'not settled reads amber');
    });
  });

  group('the map reports the monitor\'s verdict, not its own', () {
    testWidgets('a ball the device calls ready is not warned about', (
      tester,
    ) async {
      final frame = await _render(
        tester,
        position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral),
        detecting: true,
        name: 'in-capture-band',
      );
      expect(
        _amberVerdict(frame),
        isFalse,
        reason: 'nothing to say when the ball is where it should be',
      );
    });

    testWidgets('a ball the device has not called ready is warned about', (
      tester,
    ) async {
      // The case the whole feature exists for.
      final frame = await _render(
        tester,
        position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral, ready: false),
        detecting: true,
        name: 'rear-of-zone',
      );
      expect(_amberVerdict(frame), isTrue);
    });

    testWidgets('and position has no say in it', (tester) async {
      final frame = await _render(
        tester,
        position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral, ready: false),
        detecting: true,
        name: 'outside-zone',
      );
      expect(_amberVerdict(frame), isTrue);
    });
  });

  testWidgets('the map fits a box shorter than it is wide', (tester) async {
    // It goes in the session rail, which is a fixed-width column of whatever
    // height the window leaves. A square drawing in a short column overflows
    // unless it is allowed to shrink.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 110,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: BallPositionMap(
                      position: _ball(
                        depthMm: _ballDepth,
                        lateralMm: _ballLateral,
                      ),
                      detecting: true,
                      labelStyle: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  const Text('WAITING FOR THE FIRST SHOT'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byType(BallPositionMap));
    expect(box.height, lessThanOrEqualTo(110));
    expect(box.width, box.height, reason: 'still square, just smaller');
  });

  testWidgets('the painter only repaints when something moved', (tester) async {
    // The position provider rounds to whole millimetres precisely so a
    // stationary ball stops producing work. That is wasted if the painter
    // repaints anyway.
    final a = BallPositionMapPainter(
      position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral),
      detecting: true,
    );
    final same = BallPositionMapPainter(
      position: _ball(depthMm: _ballDepth, lateralMm: _ballLateral),
      detecting: true,
    );
    final moved = BallPositionMapPainter(
      position: _ball(depthMm: 260),
      detecting: true,
    );

    expect(a.shouldRepaint(same), isFalse);
    expect(a.shouldRepaint(moved), isTrue);
  });
}
