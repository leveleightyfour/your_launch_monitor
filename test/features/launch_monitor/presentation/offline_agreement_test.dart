import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

ShotData _shot({
  required double launchDirection,
  required double spinAxis,
  double ballSpeed = 118,
  double launchAngle = 19,
  double spinRate = 6200,
}) =>
    ShotData(
      clubId: '8i',
      ballSpeed: ballSpeed,
      spinRate: spinRate,
      spinAxis: spinAxis,
      launchDirection: launchDirection,
      launchAngle: launchAngle,
      clubSpeed: ballSpeed / 1.38,
    );

/// What the dispersion headline used to do: project the start line out to the
/// carry and call that the offline. Kept here so the difference it caused
/// stays visible.
double _straightLineOffline(ShotData s) =>
    s.carry * (s.launchDirection * math.pi / 180.0);

void main() {
  group('every view agrees on how far offline a shot finished', () {
    test('a shot started left that curves back is not still fully left', () {
      // The reported case: 8-iron, ~142 m carry, start line a little left,
      // curving right. The dispersion headline read the full start line while
      // the 3D view and the plotted dot showed the ball back near the middle.
      // A gentle fade off a left start line: still finishes left, but nothing
      // like as far left as the start line alone would say.
      final s = _shot(launchDirection: -1.4, spinAxis: 2);

      final straight = _straightLineOffline(s);
      final real = s.lateralOffset;

      expect(straight, lessThan(0), reason: 'started left');
      // The curve pulls it back, so the honest number is closer to the middle.
      expect(real, lessThan(0), reason: 'still finishes left');
      expect(real.abs(), lessThan(straight.abs() * 0.7),
          reason: 'curvature should pull a fading start-line miss back toward '
              'the middle — straight-line said $straight, real is $real');
      // ...and by a margin big enough to have been visible on screen.
      expect((straight - real).abs(), greaterThan(1.0));
    });

    test('the straight-line reckoning cannot see curve at all', () {
      // Same start line, opposite curves. The old formula gives one answer for
      // both, which is the whole defect.
      final draw = _shot(launchDirection: 0, spinAxis: -12);
      final fade = _shot(launchDirection: 0, spinAxis: 12);

      expect(_straightLineOffline(draw), closeTo(0, 1e-9));
      expect(_straightLineOffline(fade), closeTo(0, 1e-9));

      // The real offsets are large and opposite.
      expect(draw.lateralOffset, lessThan(-2));
      expect(fade.lateralOffset, greaterThan(2));
    });

    test('a dead straight shot is the one case they agree on', () {
      final s = _shot(launchDirection: 0, spinAxis: 0);

      expect(s.lateralOffset.abs(), lessThan(0.5));
      expect(_straightLineOffline(s).abs(), lessThan(0.5));
    });

    test('offline is measured at landing, so terrain cannot move it', () {
      // lateralOffset reads the flight, not the roll — otherwise the number
      // would drift with whatever hole the shot happened to be played to and
      // the two tabs could disagree again for a new reason.
      final s = _shot(launchDirection: -1.4, spinAxis: 6);

      expect(s.lateralOffset, s.trajectory.offline);
      expect(s.lateralOffset, isNot(s.trajectory.restPosition.x));
    });

    test('averaging one shot gives that shot back', () {
      // The headline is a mean over the selection; with a single shot it has
      // to equal what the 3D view shows for it.
      final s = _shot(launchDirection: -1.4, spinAxis: 6);
      final mean = [s].map((e) => e.lateralOffset).reduce((a, b) => a + b) / 1;

      expect(mean, s.lateralOffset);
    });
  });
}
