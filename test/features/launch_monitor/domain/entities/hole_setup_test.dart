import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

const _hole = HoleSetup(
  enabled: true,
  greenDistance: 165,
  greenWidth: 30,
  greenDepth: 25,
  greenOffset: 0,
  fairwayWidth: 40,
);

ShotData _shot({
  double ballSpeed = 120,
  double launchAngle = 18,
  double launchDirection = 0,
  double spinRate = 6500,
  double spinAxis = 0,
  HoleSetup? hole,
}) =>
    ShotData(
      ballSpeed: ballSpeed,
      spinRate: spinRate,
      spinAxis: spinAxis,
      launchDirection: launchDirection,
      launchAngle: launchAngle,
      clubSpeed: ballSpeed / 1.4,
      hole: hole,
    );

void main() {
  group('surfaceAt', () {
    test('a disabled hole is fairway everywhere', () {
      const off = HoleSetup();

      expect(off.surfaceAt(0, 100), Surface.fairway);
      expect(off.surfaceAt(500, 900), Surface.fairway);
      expect(off.surfaceAt(-80, -40), Surface.fairway);
    });

    test('the middle of the green is green', () {
      expect(_hole.surfaceAt(0, 165), Surface.green);
    });

    test('the green is an ellipse, not a box', () {
      // On the axes, just inside the edges.
      expect(_hole.surfaceAt(14, 165), Surface.green);
      expect(_hole.surfaceAt(0, 177), Surface.green);
      // The corner of the bounding box is not on the green.
      expect(_hole.surfaceAt(14, 177), isNot(Surface.green));
    });

    test('beside and behind the green is rough', () {
      expect(_hole.surfaceAt(25, 165), Surface.rough);
      expect(_hole.surfaceAt(0, 200), Surface.rough);
    });

    test('the fairway is a strip from the tee to the front of the green', () {
      expect(_hole.surfaceAt(0, 80), Surface.fairway);
      expect(_hole.surfaceAt(19, 80), Surface.fairway);
      expect(_hole.surfaceAt(21, 80), Surface.rough);
      // Past the front edge but short of the green surface itself.
      expect(_hole.surfaceAt(0, 160), Surface.green);
      expect(_hole.surfaceAt(19, 160), Surface.rough);
    });

    test('an offset green moves with its offset', () {
      const right = HoleSetup(enabled: true, greenOffset: 20);

      expect(right.surfaceAt(20, 165), Surface.green);
      expect(right.surfaceAt(0, 165), isNot(Surface.green));
      expect(right.pin.x, 20);
    });

    test('front and back edges bracket the centre', () {
      expect(_hole.greenFront, 165 - 12.5);
      expect(_hole.greenBack, 165 + 12.5);
    });
  });

  group('turf mapping', () {
    test('each surface maps to its own turf model', () {
      expect(_hole.groundAt(0, 165), GroundModel.green);
      expect(_hole.groundAt(0, 80), GroundModel.fairway);
      expect(_hole.groundAt(60, 80), GroundModel.rough);
    });
  });

  group('distanceFromPin', () {
    test('measures from the green centre', () {
      expect(_hole.distanceFromPin(const Vec3(0, 0, 165)), closeTo(0, 1e-9));
      expect(_hole.distanceFromPin(const Vec3(3, 0, 161)), closeTo(5, 1e-9));
    });
  });

  group('validation and persistence', () {
    test('values are clamped into range', () {
      final silly = const HoleSetup().copyWith(
        greenDistance: 5000,
        greenWidth: 0,
        greenOffset: -900,
        fairwayWidth: 2,
      );

      expect(silly.greenDistance, HoleSetup.maxGreenDistance);
      expect(silly.greenWidth, HoleSetup.minGreenSize);
      expect(silly.greenOffset, -HoleSetup.maxGreenOffset);
      expect(silly.fairwayWidth, HoleSetup.minFairwayWidth);
    });

    test('the shipped default plays to a green', () {
      // The feature shipped defaulting to off, so nobody saw a green and the
      // dimension controls stayed hidden behind the toggle. A fresh install
      // now plays a par 3 out of the box.
      expect(HoleSetup.standard.enabled, isTrue);
      expect(HoleSetup.standard.greenDistance, greaterThan(0));
      expect(HoleSetup.standard.fairwayWidth, greaterThan(0));
      // ...and the explicit "no hole" value still means no hole.
      expect(HoleSetup.off.enabled, isFalse);
    });

    test('survives a JSON round trip', () {
      final restored = HoleSetup.fromJson(_hole.toJson());

      expect(restored, _hole);
    });

    test('missing fields fall back to defaults', () {
      final restored = HoleSetup.fromJson(const {'enabled': true});

      expect(restored.enabled, isTrue);
      expect(restored.greenDistance, 165);
      expect(restored.fairwayWidth, 40);
    });
  });

  group('the ball plays off what it lands on', () {
    test('no hole is identical to plain fairway', () {
      final plain = _shot();
      final disabled = _shot(hole: const HoleSetup());
      final explicit = BallFlightModel.standard.simulate(
        ballSpeedMph: 120,
        launchAngleDeg: 18,
        launchDirectionDeg: 0,
        spinRpm: 6500,
        spinAxisDeg: 0,
      );

      expect(plain.trajectory.roll, explicit.roll);
      expect(plain.trajectory.restPosition.z, explicit.restPosition.z);
      expect(disabled.trajectory.roll, explicit.roll);
      expect(disabled.totalDistance, plain.totalDistance);
    });

    test('landing on the green checks; the same shot short releases', () {
      final onFairway = _shot(hole: const HoleSetup());
      final carry = onFairway.carry;

      // A green centred exactly where this shot lands.
      final greenUnderBall = _shot(
        hole: HoleSetup(
          enabled: true,
          greenDistance: carry,
          greenWidth: 40,
          greenDepth: 40,
        ),
      );
      // A green far away, so the same shot lands on fairway.
      final greenMilesAway = _shot(
        hole: HoleSetup(enabled: true, greenDistance: carry + 120),
      );

      expect(greenUnderBall.rollDistance,
          lessThan(greenMilesAway.rollDistance));
      expect(greenUnderBall.totalDistance,
          lessThan(greenMilesAway.totalDistance));
    });

    test('missing the fairway into the rough stops the ball dead', () {
      // Narrow fairway, shot pushed well right of it.
      final pushed = _shot(
        launchDirection: 8,
        hole: const HoleSetup(
          enabled: true,
          greenDistance: 400,
          fairwayWidth: 20,
        ),
      );
      final straight = _shot(
        hole: const HoleSetup(
          enabled: true,
          greenDistance: 400,
          fairwayWidth: 20,
        ),
      );

      expect(pushed.trajectory.offline.abs(), greaterThan(10));
      expect(pushed.rollDistance, lessThan(straight.rollDistance));
    });

    test('turf is resolved at each contact, not once at landing', () {
      // A ball that lands on the fairway and runs onto a green picks up the
      // green's turf part way through its roll. Note which way that goes: a
      // green is a *smoother* surface, so a ball rolling onto one releases
      // further. Checking comes from the bounce, where spin bites — not from
      // the roll. This is the same physics as the test above, arriving at the
      // opposite answer because the ball gets there a different way.
      final fairwayOnly = _shot(hole: const HoleSetup());
      final carry = fairwayOnly.carry;

      // Front edge sits 6 yards past the pitch mark, well inside the roll.
      final greenJustBeyond = _shot(
        hole: HoleSetup(
          enabled: true,
          greenDistance: carry + 18,
          greenWidth: 60,
          greenDepth: 24,
          fairwayWidth: 60,
        ),
      );

      // It lands on the fairway — the green starts beyond the pitch mark.
      expect(greenJustBeyond.hole!.surfaceAt(0, carry), Surface.fairway);
      // ...and finishes on the green, so the roll must differ from fairway
      // alone even though nothing about the flight or the landing changed.
      expect(greenJustBeyond.rollDistance,
          greaterThan(fairwayOnly.rollDistance));
      expect(
        greenJustBeyond.hole!
            .surfaceAt(0, greenJustBeyond.trajectory.restPosition.z),
        Surface.green,
      );
    });

    test('a shot carries the hole it was played to', () {
      final played = _shot(hole: _hole);
      final rehit = played.copyWith(dbId: 7);

      expect(rehit.hole, _hole);
      expect(rehit.trajectory.roll, played.trajectory.roll);
      expect(played.copyWith(clearHole: true).hole, isNull);
    });

    test('carry and the airborne numbers ignore the terrain entirely', () {
      final plain = _shot(hole: const HoleSetup());
      final onGreen = _shot(
        hole: HoleSetup(enabled: true, greenDistance: _shot().carry),
      );

      expect(onGreen.carry, plain.carry);
      expect(onGreen.apexHeight, plain.apexHeight);
      expect(onGreen.descentAngle, plain.descentAngle);
      expect(onGreen.lateralOffset, plain.lateralOffset);
    });
  });
}
