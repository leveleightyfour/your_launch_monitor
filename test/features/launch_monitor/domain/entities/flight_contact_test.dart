import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

ShotTrajectory flight(BallFlightModel model, {
  double speed = 160, double angle = 15, double spin = 3000,
  double direction = 0, double axis = 0,
  GroundModel Function(double, double)? groundAt,
  bool Function(double, double)? stopsAt,
}) => model.simulate(ballSpeedMph: speed, launchAngleDeg: angle,
    launchDirectionDeg: direction, spinRpm: spin, spinAxisDeg: axis,
    groundAt: groundAt, stopsAt: stopsAt);

void main() {
  const model = BallFlightModel.standard;
  test('restitution uses the published high-speed branch', () {
    expect(model.restitution(20), closeTo(0.1212, 1e-10));
    for (final speed in [20.001, 25.0, 30.0, 40.0, 60.0]) {
      expect(model.restitution(speed), closeTo(0.12, 1e-10));
      expect(model.restitution(-speed), model.restitution(speed));
      expect(model.restitution(speed, GroundModel.green), closeTo(0.06, 1e-10));
    }
  });

  test('non-finite launch values fail before integration', () {
    for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
      for (final result in [flight(model, speed: value), flight(model, angle: value),
        flight(model, spin: value), flight(model, direction: value),
        flight(model, axis: value)]) {
        expect(result.failure, FlightFailure.invalidInput);
        expect(result.points, isEmpty);
        expect(result.groundPoints, isEmpty);
      }
    }
    expect(flight(model, spin: -10).failure, FlightFailure.invalidInput);
    expect(flight(model, angle: 100).failure, FlightFailure.invalidInput);
    for (final step in [0.0, -1.0, double.nan, double.infinity]) {
      expect(flight(BallFlightModel(stepSeconds: step)).failure,
          FlightFailure.invalidInput);
    }
  });

  test('a timed-out flight cannot manufacture a touchdown', () {
    const vacuum = BallFlightModel(dragBase: 0, dragPerSpin: 0,
      dragAtLowSpeed: 0, liftMax: 0);
    var contacts = 0;
    final result = flight(vacuum, speed: 300, angle: 90, spin: 0,
      groundAt: (_, _) { contacts++; return GroundModel.fairway; });
    expect(result.failure, FlightFailure.timeLimit);
    expect(result.points, isEmpty);
    expect(result.groundPoints, isEmpty);
    expect(contacts, 0);
  });

  test('every ground contact queries turf at the interpolated landing point', () {
    final contacts = <Vec3>[];
    final result = flight(model, groundAt: (x, z) {
      contacts.add(Vec3(x, 0, z));
      return GroundModel.fairway;
    });
    final arrivals = [
      for (var i = 1; i < result.groundPoints.length; i++)
        if (result.groundPoints[i].t == result.groundPoints[i - 1].t &&
            result.groundPoints[i].specificEnergy !=
                result.groundPoints[i - 1].specificEnergy)
          result.groundPoints[i],
    ];
    expect(arrivals.length, result.bounces - 1);
    for (final arrival in arrivals) {
      expect(contacts.any((p) => (p.x - arrival.x).abs() < 1e-9 &&
          (p.z - arrival.z).abs() < 1e-9), isTrue);
    }
    // Contact handling consumes the remainder, retaining the regular 40 ms grid.
    final regular = result.groundPoints.where((p) => p.y > 0).toList();
    expect(regular, isNotEmpty);
    for (final p in regular) {
      final tick = (p.t - result.flightTime) / 0.04;
      expect(tick, closeTo(tick.roundToDouble(), 1e-7));
    }
  });

  test('contact correction converges in time and distance', () {
    final coarse = flight(const BallFlightModel(stepSeconds: 0.005));
    final fine = flight(const BallFlightModel(stepSeconds: 0.0025));
    expect(coarse.restPosition.z, closeTo(fine.restPosition.z, 0.15));
    expect(coarse.groundTime, closeTo(fine.groundTime, 0.03));
  });

  test('device metadata never distorts the path, apex or terrain outcome', () {
    ShotData shot({double? run, double? apex}) => ShotData(ballSpeed: 150,
      spinRate: 3000, spinAxis: 10, launchDirection: 2, launchAngle: 14,
      clubSpeed: 100, run: run, apex: apex);
    final baseline = shot();
    for (final run in [0.0, -10.0, 500.0, double.nan]) {
      final reported = shot(run: run, apex: 80);
      expect(reported.trajectory.restPosition.z, baseline.trajectory.restPosition.z);
      expect(reported.trajectory.restPosition.x, baseline.trajectory.restPosition.x);
      expect(reported.apexHeight, baseline.apexHeight);
      expect(reported.rollDistance, baseline.rollDistance);
      expect(reported.reportedApexHeight, 80);
      expect(reported.reportedRollDistance, run.isFinite ? run : null);
    }
  });
}
