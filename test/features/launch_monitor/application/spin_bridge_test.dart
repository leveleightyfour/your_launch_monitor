/// What reaches the flight model from a ball frame, and what the shape of the
/// shot depends on.
///
/// Spin axis is the sole driver of curvature — an axis of zero draws a
/// perfectly straight ball whatever else is true — so anything that silently
/// turns an axis into zero turns a shaped shot into a straight one.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/notifications.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

/// A `11 02` frame with each field settable. Byte layout is
/// `11 02 mask speed(2) vAng(2) hAng(2) totalSpin(2) axis(2) back(2) side(2)`.
List<String> _frame({
  String mask = '3f',
  String axisLo = 'c8',
  String axisHi = '00', // 200 -> 2.00 deg
  String spinLo = '38',
  String spinHi = '18', // 6200 rpm
  String backLo = '38',
  String backHi = '18',
  String sideLo = '64',
  String sideHi = '00', // 100 rpm
}) =>
    [
      '11', '02', mask, //
      '5c', '1a', // ball speed
      '44', '04', // vertical angle
      '12', '00', // horizontal angle
      spinLo, spinHi,
      axisLo, axisHi,
      backLo, backHi,
      sideLo, sideHi,
    ];

double _curveYards(double spinRpm, double axisDeg) =>
    BallFlightModel.standard
        .simulate(
          ballSpeedMph: 118,
          launchAngleDeg: 19,
          launchDirectionDeg: 0,
          spinRpm: spinRpm,
          spinAxisDeg: axisDeg,
        )
        .curve;

void main() {
  group('an unmeasured spin axis', () {
    test('parses to exactly zero, which is a dead straight ball', () {
      // int16 sentinel -32768, little-endian.
      final b = parseShotBallMetrics(_frame(axisLo: '00', axisHi: '80'));

      expect(b.spinAxis, 0.0);
      expect(b.isSpinAxisValid, isFalse);
      // ...and zero axis means no curve at all, so an unchecked read of it
      // draws a straight tracer for a shot that curved.
      expect(_curveYards(6200, 0), closeTo(0, 0.01));
    });

    test('is still described by the sidespin the device did measure', () {
      final b = parseShotBallMetrics(_frame(axisLo: '00', axisHi: '80'));

      expect(b.isSidespinValid, isTrue);
      expect(b.sidespinRpm, isNot(0),
          reason: 'the shape is in the components even without an axis');
    });

    test('the device can also flag a parseable axis as meaningless', () {
      // Bitmask 0x3b clears bit 0x04 — spin axis — while the bytes still hold
      // a perfectly readable 2 degrees.
      final b =
          applyOmniBallValidityBitmask(parseShotBallMetrics(_frame(mask: '3b')));

      expect(b.spinAxis, 2.0);
      expect(b.isSpinAxisValid, isFalse,
          reason: 'a readable number the device says not to trust');
    });
  });

  group('spin magnitude', () {
    test('an unmeasured total is not a harmless zero', () {
      final withSpin = BallFlightModel.standard.simulate(
        ballSpeedMph: 118,
        launchAngleDeg: 19,
        launchDirectionDeg: 0,
        spinRpm: 6200,
        spinAxisDeg: 0,
      );
      final without = BallFlightModel.standard.simulate(
        ballSpeedMph: 118,
        launchAngleDeg: 19,
        launchDirectionDeg: 0,
        spinRpm: 0,
        spinAxisDeg: 0,
      );

      // Losing the spin costs the ball its lift: tens of yards of carry and
      // most of its height. A tracer drawn that way looks like another shot.
      expect(withSpin.carry - without.carry, greaterThan(30));
      expect(withSpin.apex, greaterThan(without.apex * 2));
    });

    test('the components reconstruct the total', () {
      final b = parseShotBallMetrics(_frame());

      final fromParts = math.sqrt(
        b.backspinRpm * b.backspinRpm + b.sidespinRpm * b.sidespinRpm,
      );
      expect(fromParts, closeTo(b.totalSpinRpm.abs().toDouble(), 2));
    });
  });

  group('curvature is entirely the axis', () {
    test('curve grows with the axis and mirrors about zero', () {
      expect(_curveYards(6200, 0).abs(), lessThan(0.01));
      expect(_curveYards(6200, 8), greaterThan(8));
      expect(_curveYards(6200, -8), lessThan(-8));
      expect(_curveYards(6200, 8), closeTo(-_curveYards(6200, -8), 0.5));
    });

    test('a bigger axis bends it further', () {
      expect(_curveYards(6200, 15), greaterThan(_curveYards(6200, 8)));
    });

    test('with no spin there is nothing for the axis to tilt', () {
      expect(_curveYards(0, 15).abs(), lessThan(1.0));
    });
  });

  group('topspin', () {
    test('the parser signs the total negative, which .abs() would erase', () {
      // Backspin -200 rpm: the ball is topspinning.
      final b = parseShotBallMetrics(_frame(backLo: '38', backHi: 'ff'));

      expect(b.backspinRpm, lessThan(0));
      expect(b.totalSpinRpm, lessThan(0),
          reason: 'the sign is the parser saying which way it spins');
      // Taking the magnitude turns a diving ball into a climbing one.
      expect(b.totalSpinRpm.abs(), greaterThan(0));
    });
  });
}
