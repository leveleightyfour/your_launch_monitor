/// Validation against a real session, exported by the Square Golf app itself.
///
/// Every other reference in this suite is a tour average with a spin axis of
/// zero, so until now nothing had ever checked what the model does with a
/// curving shot. These twenty-three are one player's range session on
/// 29 Jul 2026 — hybrid, 7-iron and pitching wedge, spin axes from 14.8 left
/// to 5.7 right — and they carry the app's own carry, apex, offline and
/// landing angle alongside the launch conditions, so the model can be scored
/// against them directly.
///
/// The app writes L and R rather than signs. They map straight onto this
/// model's convention: L is negative, R is positive. Thirteen of the fourteen
/// shots with a meaningful axis curve the way their axis says, which is what
/// makes that mapping safe to assert rather than assume.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

const M = 0.9144; // yards -> metres

class R {
  final String club; final int i;
  final double bs, ld, la, spin, axis, apex, carry, total, offline, land;
  const R(this.club,this.i,this.bs,this.ld,this.la,this.spin,this.axis,
          this.apex,this.carry,this.total,this.offline,this.land);
}

// Square Golf app export, 29 Jul. L -> negative, R -> positive.
const rows = <R>[
  R('7Hy',0,135.7,-3.5,11.6,6673,-6.8,28.4,176.5,179.6,-22.8,44.6),
  R('7Hy',1,131.2,-8.5, 9.0,5829,-3.6,21.2,172.3,178.9,-31.0,38.4),
  R('7Hy',2,121.3, 5.9,18.2,6127, 1.7,32.1,157.9,160.0, 19.0,48.8),
  R('7Hy',3,137.2, 1.0,14.0,6761,-0.7,33.9,177.7,179.5,  1.9,48.6),
  R('7i',0,102.5,-0.2,19.1,7112, 5.3,22.1,124.5,127.0,  5.1,44.1),
  R('7i',1,113.2,-2.1,15.5,6972,-0.8,23.3,141.7,144.7, -6.2,43.2),
  R('7i',2,108.4, 0.8,17.2,7517, 0.0,22.9,132.5,134.7,  1.7,44.1),
  R('7i',3,101.8,-0.8,17.0,7446,-2.1,19.3,122.2,125.2, -3.7,41.2),
  R('7i',4,122.0,-5.4,17.1,5886,-9.4,30.2,160.6,163.6,-29.3,46.8),
  R('7i',5,111.2,-3.0,16.5,7670,-7.2,23.4,136.0,138.1,-16.0,44.1),
  R('7i',6,113.7, 0.9,18.1,7090, 1.5,27.3,142.1,143.9,  4.1,46.9),
  R('7i',7,114.9,-0.3,15.6,7826, 4.2,24.2,141.1,143.1,  4.8,44.4),
  R('7i',8,117.4, 0.0,16.5,8152, 5.1,26.8,144.0,145.3,  7.1,46.5),
  R('7i',9,113.1, 0.0,14.9,7168, 0.2,22.3,140.7,143.8,  0.3,42.4),
  R('7i',10,112.1,0.4,14.3,7782, 2.0,20.9,136.7,139.5,  3.3,41.5),
  R('7i',11,119.2,-0.8,15.8,6918,-9.2,26.6,150.6,153.1,-15.1,45.4),
  R('7i',12,120.0,-1.8,13.1,7232,-2.5,23.2,150.5,153.8, -8.1,42.0),
  R('7i',13,115.5, 3.7,16.3,8285, 5.7,25.6,141.1,142.5, 16.9,45.7),
  R('7i',14,116.7,-0.4,15.0,7219, 0.3,24.3,145.9,148.5, -0.6,43.9),
  R('7i',15,114.2,-1.3,15.7,6391,-3.7,24.2,146.3,150.1, -8.2,43.0),
  R('PW',0,97.5,-3.9,16.7,8093,-0.2,17.3,115.0,117.8, -7.9,39.5),
  R('PW',1,104.0,-4.0,8.7,5352,-14.8,8.9,117.3,133.1,-18.9,24.1),
  R('PW',2,95.8,-0.8,24.7,10125,-8.5,26.1,111.0,110.9,-10.4,49.3),
];

void main() {
  ShotTrajectory sim(R r) => BallFlightModel.standard.simulate(
        ballSpeedMph: r.bs,
        launchAngleDeg: r.la,
        launchDirectionDeg: r.ld,
        spinRpm: r.spin,
        spinAxisDeg: r.axis,
      );

  group('shape, against real curving shots', () {
    test('a left axis draws and a right axis cuts, every time', () {
      // The sign the whole shape hangs on. If the convention ever inverts
      // again this is the test that says so, in the player's own numbers.
      for (final r in rows) {
        if (r.axis.abs() < 1.0) continue;
        final curve = sim(r).curve * M;
        expect(curve.sign, r.axis.sign,
            reason: '${r.club} #${r.i}: axis ${r.axis} curved $curve');
      }
    });

    test('offline lands within a metre or so of the measured value', () {
      // Across shots finishing 29 m left and 17 m right. This is the first
      // measurement the curvature has ever been held to.
      var sum = 0.0, sumSq = 0.0;
      for (final r in rows) {
        final d = sim(r).offline * M - r.offline;
        sum += d;
        sumSq += d * d;
      }
      final bias = sum / rows.length;
      final rms = math.sqrt(sumSq / rows.length);

      expect(bias.abs(), lessThan(1.0), reason: 'offline bias $bias m');
      expect(rms, lessThan(2.0), reason: 'offline RMS $rms m');
    });

    test('the big curves are as big as they were measured', () {
      // The gentle ones would pass on luck; these would not.
      //
      // The bound is set by PW #1 at 3.2 m, which is the session's thinnest
      // strike — 8.7 degrees of launch on 5352 rpm, carrying 117 m and running
      // to 133. It is also the worst carry miss at 8.4 m short. Low, low-spin
      // strikes are where this model is weakest, and that shows up in the
      // shape as well as the distance. Every full shot is inside 1.6 m.
      for (final r in rows.where((r) => r.offline.abs() > 12)) {
        final off = sim(r).offline * M;
        expect((off - r.offline).abs(), lessThan(3.5),
            reason: '${r.club} #${r.i}: ours $off vs ${r.offline}');
      }
    });
  });

  group('distance, against the same session', () {
    test('carry runs long, and by a known amount', () {
      // A standing +2.5% bias, not noise. Pinned so a refit has to move it
      // deliberately rather than by accident.
      var sum = 0.0;
      for (final r in rows) {
        sum += sim(r).carry * M - r.carry;
      }
      final bias = sum / rows.length;

      expect(bias, greaterThan(2.0));
      expect(bias, lessThan(5.5), reason: 'carry bias drifted to $bias m');
    });

    test('apex sits low and the descent shallow, consistently', () {
      // Both point the same way — the ball is flying flatter than measured —
      // so they are recorded together as one symptom.
      var apex = 0.0, land = 0.0;
      for (final r in rows) {
        final t = sim(r);
        apex += t.apex * M - r.apex;
        land += t.descentAngle - r.land;
      }

      expect(apex / rows.length, lessThan(0));
      expect(land / rows.length, lessThan(0));
    });
  });
}
