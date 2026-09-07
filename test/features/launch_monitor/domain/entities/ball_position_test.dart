import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/notifications.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/ball_position.dart';

/// A sensor frame with the given raw position words, built the way the device
/// sends them: `11 01`, a reserved byte, ready, detected, then three
/// little-endian int32s.
SensorData _sensor({
  int x = 0,
  int y = 0,
  int z = 0,
  bool detected = true,
  bool ready = false,
}) {
  List<String> le32(int v) {
    final raw = v < 0 ? v + 0x100000000 : v;
    return [
      for (var shift = 0; shift < 32; shift += 8)
        ((raw >> shift) & 0xFF).toRadixString(16).padLeft(2, '0'),
    ];
  }

  return parseSensorData([
    '11',
    '01',
    '00',
    ready ? '01' : '00',
    detected ? '01' : '00',
    ...le32(x),
    ...le32(y),
    ...le32(z),
  ]);
}

void main() {
  group('decoding a sensor frame into mat coordinates', () {
    test('raw words are twentieths of a millimetre', () {
      // The reference divides by 10, and its grid works out to exactly 200 of
      // the resulting units — which reads as a 20cm grid over a metre square,
      // and equally as a 10cm grid over half a metre. The mat picks the second:
      // see the scale group below.
      final p = BallPosition.fromSensor(_sensor(x: 1000, y: -250, z: 155));

      expect(p.depthMm, 50 * depthSign);
      expect(p.lateralMm, -12.5 * lateralSign);
      expect(p.heightMm, 7.75);
    });

    test(
      'protocol X is depth and protocol Y is lateral, not the other way',
      () {
        // The reference plots Y horizontally and X vertically. Getting this
        // backwards would put the ball in the wrong half of the mat and read as
        // plausible, so it is worth a test of its own.
        final alongTargetLine = BallPosition.fromSensor(_sensor(x: 3000));
        expect(alongTargetLine.depthMm.abs(), 150);
        expect(alongTargetLine.lateralMm, 0);

        final acrossTargetLine = BallPosition.fromSensor(_sensor(y: 3000));
        expect(acrossTargetLine.lateralMm.abs(), 150);
        expect(acrossTargetLine.depthMm, 0);
      },
    );

    test('zero is the middle of what the monitor can see', () {
      // Not the monitor itself, which stands off to the golfer's right. Walking
      // the ball to the edges gives readings spread either side of zero on both
      // axes — so zero is the centre of the field of view. That is why the
      // manual's ready-zone offsets, quoted from the device's body, never fitted
      // these coordinates.
      final p = BallPosition.fromSensor(_sensor());
      expect(p.depthMm, 0);
      expect(p.lateralMm, 0);
      expect(detectedFrontMm + detectedBackMm, lessThan(100));
      expect(detectedRightMm + detectedLeftMm, lessThan(100));
    });

    test('raw words are carried through untransformed', () {
      // Everything above them is inference; these are what settle an argument
      // between the drawing and the mat.
      final p = BallPosition.fromSensor(_sensor(x: 4750, y: 1750, z: 210));
      expect(p.rawX, 4750);
      expect(p.rawY, 1750);
      expect(p.rawZ, 210);
    });

    test('detection and ready flags carry through', () {
      expect(
        BallPosition.fromSensor(_sensor(detected: false)).detected,
        isFalse,
      );
      expect(BallPosition.fromSensor(_sensor(ready: true)).ready, isTrue);
    });
  });

  group('the drawn window', () {
    // Fixed. An earlier version rescaled itself to keep a stray ball in frame,
    // which made everything drawn on it appear to move while the ball sat still.
    test('is square, so the status-bar indicator does not stretch it', () {
      const b = MatBounds.mat;
      expect(b.widthMm, b.depthMm);
    });

    test('holds the whole area the monitor can see a ball in', () {
      // Walked out on the mat until the ball stopped being recognised. Earlier
      // windows were sized around the manual's 25cm ready zone and left the
      // back half and one whole side of the real area off the picture.
      const b = MatBounds.mat;
      for (final (depth, lateral) in const [
        (detectedFrontMm, detectedLeftMm),
        (detectedFrontMm, detectedRightMm),
        (detectedBackMm, detectedLeftMm),
        (detectedBackMm, detectedRightMm),
      ]) {
        expect(depth, inInclusiveRange(b.minDepthMm, b.maxDepthMm));
        expect(lateral, inInclusiveRange(b.minLateralMm, b.maxLateralMm));
      }
    });

    test('puts a ball at the front of the mat at the front of the picture', () {
      // The reported bug: pushed to the very front of the hitting area, the
      // ball still drew a third of the way down, because the window covered
      // ground the sensor cannot see.
      const b = MatBounds.mat;
      final fromTop = (b.maxDepthMm - detectedFrontMm) / b.depthMm;
      expect(fromTop, lessThan(0.05));

      final fromBottom = (detectedBackMm - b.minDepthMm) / b.depthMm;
      expect(fromBottom, lessThan(0.05), reason: 'and the back at the back');
    });

  });

  group('readiness is the device\'s call, not ours', () {
    // The app used to infer whether the ball was inside a ready zone from the
    // manual's offsets. Those only hold with the monitor standing where the
    // manual puts it, and a real setup read a metre in front — so every real
    // ball got a confident, wrong verdict. The monitor's own light already
    // answers the question.
    test('a ready frame reads as ready, wherever the ball is', () {
      final near = BallPosition.fromSensor(
        parseSensorData(['11', '01', '00', '01', '01', ...List.filled(12, '00')]),
      );
      expect(near.ready, isTrue);

      // Same flag, out at the far edge of the square. Position has no say.
      final far = BallPosition.fromSensor(
        parseSensorData([
          '11', '01', '00', '01', '01',
          '7c', '27', '00', '00', // X = 10108
          '02', '0c', '00', '00', // Y = 3074
          '00', '00', '00', '00',
        ]),
      );
      expect(far.ready, isTrue);
      expect(
        far.depthMm,
        greaterThan(500),
        reason: 'out at the front of the hitting square',
      );
    });

    test('a frame the device has not called ready is not ready', () {
      final p = BallPosition.fromSensor(
        parseSensorData(['11', '01', '00', '00', '01', ...List.filled(12, '00')]),
      );
      expect(p.detected, isTrue);
      expect(p.ready, isFalse);
    });
  });

  test('byte 3 is carried through unflattened', () {
    // `ready` folds `01` and `02` into one bool, following the Go reference.
    // The manual's solid-versus-blinking light suggests they differ, so the raw
    // value is kept in case that turns out to matter.
    final s = parseSensorData([
      '11', '01', '00', '02', '01',
      ...List.filled(12, '00'),
    ]);
    expect(s.readyState, 2);
    expect(BallPosition.fromSensor(s).readyState, 2);
  });
}
