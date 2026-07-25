import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

/// A published launch condition and the flight it is expected to produce.
class _Reference {
  final String name;
  final double ballSpeed;
  final double launchAngle;
  final double spin;
  final double carry;
  final double apex;
  final double descentAngle;
  final double flightTime;

  const _Reference(
    this.name, {
    required this.ballSpeed,
    required this.launchAngle,
    required this.spin,
    required this.carry,
    required this.apex,
    required this.descentAngle,
    required this.flightTime,
  });
}

/// Trackman tour averages. The model is fitted to these, so this suite is a
/// regression guard: it fails if a coefficient change pushes any club's flight
/// outside the tolerances below.
const _references = [
  _Reference('driver',
      ballSpeed: 167,
      launchAngle: 10.9,
      spin: 2686,
      carry: 275,
      apex: 32,
      descentAngle: 38,
      flightTime: 6.4),
  _Reference('LPGA driver',
      ballSpeed: 140,
      launchAngle: 13.2,
      spin: 2611,
      carry: 218,
      apex: 25,
      descentAngle: 37,
      flightTime: 5.7),
  _Reference('3-wood',
      ballSpeed: 158,
      launchAngle: 9.2,
      spin: 3655,
      carry: 243,
      apex: 30,
      descentAngle: 43,
      flightTime: 6.2),
  _Reference('5-iron',
      ballSpeed: 135,
      launchAngle: 14.3,
      spin: 5361,
      carry: 195,
      apex: 31,
      descentAngle: 46,
      flightTime: 6.2),
  _Reference('7-iron',
      ballSpeed: 120,
      launchAngle: 16.3,
      spin: 7097,
      carry: 172,
      apex: 32,
      descentAngle: 50,
      flightTime: 6.1),
  _Reference('9-iron',
      ballSpeed: 109,
      launchAngle: 20.4,
      spin: 8647,
      carry: 152,
      apex: 30,
      descentAngle: 51,
      flightTime: 5.8),
  _Reference('pitching wedge',
      ballSpeed: 102,
      launchAngle: 24.2,
      spin: 9316,
      carry: 136,
      apex: 29,
      descentAngle: 52,
      flightTime: 5.6),
];

ShotTrajectory _flight({
  required double ballSpeed,
  required double launchAngle,
  double launchDirection = 0,
  required double spin,
  double spinAxis = 0,
  double? roll,
}) =>
    BallFlightModel.standard.simulate(
      ballSpeedMph: ballSpeed,
      launchAngleDeg: launchAngle,
      launchDirectionDeg: launchDirection,
      spinRpm: spin,
      spinAxisDeg: spinAxis,
      measuredRollYds: roll,
    );

void main() {
  group('tour reference flights', () {
    for (final ref in _references) {
      test('${ref.name} lands in the expected window', () {
        final flight = _flight(
          ballSpeed: ref.ballSpeed,
          launchAngle: ref.launchAngle,
          spin: ref.spin,
        );

        expect(
          (flight.carry - ref.carry).abs() / ref.carry,
          lessThan(0.08),
          reason: '${ref.name} carry ${flight.carry} vs ${ref.carry}',
        );
        expect(
          (flight.apex - ref.apex).abs(),
          lessThan(4.5),
          reason: '${ref.name} apex ${flight.apex} vs ${ref.apex}',
        );
        expect(
          (flight.descentAngle - ref.descentAngle).abs(),
          lessThan(6.0),
          reason: '${ref.name} descent ${flight.descentAngle} '
              'vs ${ref.descentAngle}',
        );
        expect(
          (flight.flightTime - ref.flightTime).abs(),
          lessThan(0.6),
          reason: '${ref.name} hang time ${flight.flightTime} '
              'vs ${ref.flightTime}',
        );
      });
    }
  });

  group('flight shape', () {
    test('starts at the tee and finishes on the ground', () {
      final flight = _flight(ballSpeed: 150, launchAngle: 12, spin: 2800);

      expect(flight.points.first.x, 0);
      expect(flight.points.first.y, 0);
      expect(flight.points.first.z, 0);
      expect(flight.points.last.y, 0);
      expect(flight.points.last.z, closeTo(flight.carry, 0.01));
      expect(flight.points.length, greaterThan(50));
    });

    test('time and downrange distance increase monotonically', () {
      final flight = _flight(ballSpeed: 150, launchAngle: 12, spin: 2800);

      for (var i = 1; i < flight.points.length; i++) {
        expect(flight.points[i].t, greaterThan(flight.points[i - 1].t));
        expect(flight.points[i].z, greaterThan(flight.points[i - 1].z));
      }
    });

    test('the ball slows down through the flight', () {
      final flight = _flight(ballSpeed: 150, launchAngle: 12, spin: 2800);

      expect(flight.points.first.speed, closeTo(150, 0.01));
      expect(flight.landingSpeed, lessThan(150 * 0.6));
      expect(flight.landingSpeed, greaterThan(20));
    });

    test('apex sits between the tee and the landing point', () {
      final flight = _flight(ballSpeed: 150, launchAngle: 12, spin: 2800);

      expect(flight.apex, greaterThan(0));
      expect(flight.apexDistance, greaterThan(0));
      expect(flight.apexDistance, lessThan(flight.carry));
      // Backspin holds the ball up, so the apex is past the halfway point.
      expect(flight.apexDistance, greaterThan(flight.carry * 0.45));
    });
  });

  group('spin axis', () {
    test('zero axis flies straight', () {
      final flight = _flight(ballSpeed: 150, launchAngle: 12, spin: 3000);

      expect(flight.offline.abs(), lessThan(0.01));
      expect(flight.curve.abs(), lessThan(0.01));
    });

    test('a positive axis curves right and a negative axis curves left', () {
      final fade =
          _flight(ballSpeed: 150, launchAngle: 12, spin: 3000, spinAxis: 10);
      final draw =
          _flight(ballSpeed: 150, launchAngle: 12, spin: 3000, spinAxis: -10);

      expect(fade.curve, greaterThan(5));
      expect(draw.curve, lessThan(-5));
      expect(fade.curve, closeTo(-draw.curve, 0.5));
    });

    test('more axis tilt curves the ball further', () {
      final gentle =
          _flight(ballSpeed: 150, launchAngle: 12, spin: 3000, spinAxis: 5);
      final severe =
          _flight(ballSpeed: 150, launchAngle: 12, spin: 3000, spinAxis: 20);

      expect(severe.curve, greaterThan(gentle.curve * 2));
      // Sidespin comes at the cost of carry.
      expect(severe.carry, lessThan(gentle.carry));
    });

    test('curve is measured from the start line, not the target line', () {
      final pushed = _flight(
        ballSpeed: 150,
        launchAngle: 12,
        launchDirection: 4,
        spin: 3000,
        spinAxis: 8,
      );

      // Started right and curved further right.
      expect(pushed.offline, greaterThan(pushed.curve));
      expect(pushed.curve, greaterThan(0));
    });

    test('a straight push finishes right with no curve', () {
      final pushed = _flight(
        ballSpeed: 150,
        launchAngle: 12,
        launchDirection: 4,
        spin: 3000,
      );

      expect(pushed.offline, greaterThan(10));
      expect(pushed.curve.abs(), lessThan(0.5));
    });
  });

  group('spin rate', () {
    test('more backspin flies higher and lands steeper', () {
      final low = _flight(ballSpeed: 150, launchAngle: 12, spin: 2200);
      final high = _flight(ballSpeed: 150, launchAngle: 12, spin: 5000);

      expect(high.apex, greaterThan(low.apex));
      expect(high.descentAngle, greaterThan(low.descentAngle));
    });

    test('spin far above optimal costs carry', () {
      final optimal = _flight(ballSpeed: 165, launchAngle: 11, spin: 2600);
      final ballooning = _flight(ballSpeed: 165, launchAngle: 11, spin: 6000);

      expect(ballooning.carry, lessThan(optimal.carry));
    });
  });

  group('roll', () {
    test('a steeper landing runs out less', () {
      final driver = _flight(ballSpeed: 165, launchAngle: 11, spin: 2500);
      final wedge = _flight(ballSpeed: 100, launchAngle: 25, spin: 9500);

      expect(driver.roll, greaterThan(wedge.roll));
      expect(driver.totalDistance, greaterThan(driver.carry));
    });

    test('a measured roll from the device wins over the estimate', () {
      final flight =
          _flight(ballSpeed: 165, launchAngle: 11, spin: 2500, roll: 7);

      expect(flight.roll, 7);
      expect(flight.totalDistance, closeTo(flight.carry + 7, 0.001));
    });

    test('the resting point continues along the ground track', () {
      final flight = _flight(
        ballSpeed: 150,
        launchAngle: 12,
        launchDirection: 3,
        spin: 3000,
        spinAxis: 10,
      );
      final rest = flight.restPosition;

      expect(rest.z, greaterThan(flight.carry));
      expect(rest.x.abs(), greaterThan(flight.offline.abs()));
      expect(rest.y, 0);
    });
  });

  group('degenerate input', () {
    test('no ball speed yields an empty flight', () {
      final flight = _flight(ballSpeed: 0, launchAngle: 12, spin: 3000);

      expect(flight.isEmpty, isTrue);
      expect(flight.carry, 0);
    });

    test('a negative launch angle yields an empty flight', () {
      final flight = _flight(ballSpeed: 120, launchAngle: -2, spin: 3000);

      expect(flight.isEmpty, isTrue);
    });

    test('zero spin still flies, just lower', () {
      final spinning = _flight(ballSpeed: 150, launchAngle: 12, spin: 3000);
      final knuckle = _flight(ballSpeed: 150, launchAngle: 12, spin: 0);

      expect(knuckle.isEmpty, isFalse);
      expect(knuckle.apex, lessThan(spinning.apex));
      expect(knuckle.carry, lessThan(spinning.carry));
    });
  });

  group('ShotData integration', () {
    ShotData shot({
      double ballSpeed = 150,
      double launchAngle = 12,
      double launchDirection = 0,
      double spinRate = 3000,
      double spinAxis = 0,
      double? run,
    }) =>
        ShotData(
          ballSpeed: ballSpeed,
          spinRate: spinRate,
          spinAxis: spinAxis,
          launchDirection: launchDirection,
          launchAngle: launchAngle,
          clubSpeed: ballSpeed / 1.45,
          run: run,
        );

    test('the simulated flight is cached per shot', () {
      final s = shot();

      expect(identical(s.trajectory, s.trajectory), isTrue);
    });

    test('carry and offline come from the simulation', () {
      final s = shot(launchDirection: 3, spinAxis: 8);

      expect(s.carry, s.trajectory.carry);
      expect(s.lateralOffset, s.trajectory.offline);
      expect(s.curveDistance, s.trajectory.curve);
      expect(s.descentAngle, s.trajectory.descentAngle);
    });

    test('a device-reported roll is used for total distance', () {
      final s = shot(run: 12);

      expect(s.rollDistance, 12);
      expect(s.totalDistance, closeTo(s.carry + 12, 0.001));
    });

    test('apex falls back to the simulation when the device has none', () {
      final s = shot();

      expect(s.apex, isNull);
      expect(s.apexHeight, s.trajectory.apex);
      expect(s.apexHeight, greaterThan(0));
    });

    test('a driver-like shot produces a believable carry', () {
      final s = shot(ballSpeed: 158, launchAngle: 13, spinRate: 2540);

      expect(s.carry, greaterThan(230));
      expect(s.carry, lessThan(270));
    });
  });
}
