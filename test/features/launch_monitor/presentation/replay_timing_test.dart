import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';

/// Trackman tour averages, same fixtures the flight model is validated
/// against. Here they check the *replay*, not the physics: what the eye sees
/// has to match how long the shot really took.
class _Ref {
  final String name;
  final double ballSpeed;
  final double launchAngle;
  final double spin;

  /// Measured hang time, seconds.
  final double hang;

  const _Ref(this.name, this.ballSpeed, this.launchAngle, this.spin, this.hang);
}

const _references = [
  _Ref('PGA driver', 167, 10.9, 2686, 6.4),
  _Ref('LPGA driver', 140, 13.2, 2611, 5.7),
  _Ref('3-wood', 158, 9.2, 3655, 6.2),
  _Ref('5-iron', 135, 14.3, 5361, 6.2),
  _Ref('7-iron', 120, 16.3, 7097, 6.1),
  _Ref('9-iron', 109, 20.4, 8647, 5.8),
  _Ref('pitching wedge', 102, 24.2, 9316, 5.6),
];

ShotTrajectory _flight(_Ref r) => BallFlightModel.standard.simulate(
      ballSpeedMph: r.ballSpeed,
      launchAngleDeg: r.launchAngle,
      launchDirectionDeg: 0,
      spinRpm: r.spin,
      spinAxisDeg: 0,
    );

void main() {
  group('the replay runs at real time', () {
    for (final ref in _references) {
      test('${ref.name} hangs for as long as it really does', () {
        final flight = _flight(ref);
        final onScreen = airborneReplaySeconds(flight.flightTime);

        // Nothing between the physics and the screen.
        expect(
          onScreen,
          closeTo(flight.flightTime, 1e-9),
          reason: '${ref.name} replay $onScreen vs simulated '
              '${flight.flightTime}',
        );

        // ...and the physics itself is within the model's own hang-time
        // tolerance of the measured value, so the screen is too.
        expect(
          (onScreen - ref.hang).abs(),
          lessThan(0.6),
          reason: '${ref.name} on screen $onScreen vs measured ${ref.hang}',
        );
      });
    }

    test('no club is stretched, and none is systematically long', () {
      // The old 1.15 multiplier put the mean bias at +13%. Guard the aggregate
      // as well as the per-club numbers: a stretch reintroduced anywhere shows
      // up here even if it stays inside the per-club tolerance.
      var total = 0.0;
      for (final ref in _references) {
        final onScreen = airborneReplaySeconds(_flight(ref).flightTime);
        total += (onScreen - ref.hang) / ref.hang;
      }

      expect((total / _references.length).abs(), lessThan(0.04));
    });

    test('long clubs stay distinguishable', () {
      // A 7 s ceiling used to collapse driver, 3-wood and 5-iron onto the same
      // duration. They have different hang times and must look like it.
      final driver = airborneReplaySeconds(_flight(_references[0]).flightTime);
      final wood = airborneReplaySeconds(_flight(_references[2]).flightTime);
      final iron = airborneReplaySeconds(_flight(_references[3]).flightTime);

      expect(driver, isNot(closeTo(wood, 0.01)));
      expect(driver, greaterThan(6.0));
      expect(wood, greaterThan(6.0));
      expect(iron, greaterThan(6.0));
    });
  });

  group('the clamp only guards bad data', () {
    test('every playable shot passes through untouched', () {
      // A stubbed chip through a towering drive.
      for (final t in [0.9, 1.5, 3.0, 5.0, 6.5, 8.0]) {
        expect(airborneReplaySeconds(t), closeTo(t, 1e-9));
      }
    });

    test('a missing or unusable flight time still yields something playable',
        () {
      expect(airborneReplaySeconds(null), 3.0);
      expect(airborneReplaySeconds(0), 0.3);
      expect(airborneReplaySeconds(999), 12.0);
    });
  });
}
