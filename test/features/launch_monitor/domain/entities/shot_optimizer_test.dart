import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_context.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_optimizer.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

const measured = ShotContext(
  ballSource: MeasurementSource.measured,
  clubSpeedSource: MeasurementSource.measured,
  intent: ShotIntent.stock,
);
ShotData shot({
  String club = 'dr',
  double ball = 150,
  double speed = 100,
  double spin = 2500,
  double launch = 12,
  double direction = 0,
  double axis = 0,
  double? path,
  double? face,
  double? loft,
  double? attack,
  double? impactX,
  double? impactY,
  ShotContext context = measured,
}) => ShotData(
  clubId: club,
  ballSpeed: ball,
  clubSpeed: speed,
  spinRate: spin,
  launchAngle: launch,
  launchDirection: direction,
  spinAxis: axis,
  swingPath: path,
  faceAngle: face,
  dynamicLoft: loft,
  angleOfAttack: attack,
  horizontalImpact: impactX,
  verticalImpact: impactY,
  context: context,
);

void main() {
  final optimizer = ShotOptimizer();
  ShotAnalysis analyze(ShotData s) => optimizer.analyze(
    s,
    Club.catalog.firstWhere((c) => c.id == s.clubId).type,
    clubId: s.clubId,
  );

  test(
    'legacy, invalid and unavailable launch data never pass as efficient',
    () {
      for (final s in [
        shot(context: const ShotContext()),
        shot(ball: double.nan),
        shot(
          context: measured.copyWith(ballSource: MeasurementSource.unavailable),
        ),
        shot(ball: 0),
        shot(spin: -100),
      ]) {
        final result = analyze(s);
        expect(result.assessed, isFalse);
        expect(result.carryGap, isNull);
        expect(result.recommendations, isEmpty);
      }
    },
  );
  test('estimated club speed cannot create a contact-efficiency diagnosis', () {
    final s = shot(
      ball: 120,
      speed: 100,
      context: measured.copyWith(clubSpeedSource: MeasurementSource.estimated),
    );
    final result = analyze(s);
    expect(result.diagnostics.any((d) => d.metric == 'smashFactor'), isFalse);
    expect(result.limitations.join(' '), contains('not verified'));
  });
  test(
    'reference stock iron and wedge shots do not trigger critical contact warnings',
    () {
      // Fixed external reference inputs, deliberately independent of getRange.
      for (final s in [
        shot(club: '7i', ball: 120, speed: 90, launch: 16.3, spin: 7097),
        shot(club: '9i', ball: 109, speed: 85, launch: 20.4, spin: 8647),
        shot(club: 'pw', ball: 102, speed: 83, launch: 24.2, spin: 9304),
        shot(club: 'sw', ball: 88, speed: 78, launch: 28.6, spin: 10400),
      ]) {
        expect(
          analyze(s).diagnostics.where((d) => d.metric == 'smashFactor'),
          isEmpty,
          reason: s.clubId,
        );
      }
    },
  );
  test(
    'partial wedges never inherit stock launch spin or smash requirements',
    () {
      final result = analyze(
        shot(
          club: 'sw',
          ball: 45,
          speed: 45,
          spin: 3500,
          launch: 40,
          context: measured.copyWith(intent: ShotIntent.partial),
        ),
      );
      expect(result.diagnostics, isEmpty);
      expect(result.carryGap, isNull);
    },
  );
  test(
    'small smash deficits are not critical, and contact evidence is merged',
    () {
      final slight = analyze(shot(ball: 139, speed: 100));
      expect(
        slight.diagnostics
            .firstWhere((d) => d.metric == 'smashFactor')
            .severity,
        Severity.medium,
      );
      final severe = analyze(
        shot(ball: 105, speed: 100, impactX: 20, impactY: 0),
      );
      expect(
        severe.recommendations.where((r) => r.action == 'check_contact'),
        hasLength(1),
      );
      expect(
        severe.diagnostics.where((d) => d.metric == 'impactLocation'),
        isEmpty,
      );
      expect(
        severe.diagnostics.every((d) => d.estimatedYardsLost == null),
        isTrue,
      );
    },
  );
  test('speed reference windows are continuous across former bucket edges', () {
    for (final edge in [90.0, 105.0]) {
      for (final metric in ['launchAngle', 'spinRate']) {
        final a = OptimalRanges.getRange(
          ClubType.wood,
          metric,
          clubId: 'dr',
          clubSpeed: edge - .001,
        );
        final b = OptimalRanges.getRange(
          ClubType.wood,
          metric,
          clubId: 'dr',
          clubSpeed: edge + .001,
        );
        expect((a.$1 - b.$1).abs(), lessThan(.1));
        expect((a.$2 - b.$2).abs(), lessThan(.1));
      }
    }
  });
  test(
    'an uncalibrated spin-loft residual does not diagnose inconsistency',
    () {
      final result = analyze(
        shot(
          club: '7i',
          ball: 120,
          speed: 85,
          launch: 18,
          spin: 7000,
          loft: 25,
          attack: -4,
        ),
      );
      expect(
        result.diagnostics.any((d) => d.metric == 'spinLoftMismatch'),
        isFalse,
      );
    },
  );
  test('high spin never recommends striking lower on a driver', () {
    final result = analyze(
      shot(
        spin: 6000,
        impactX: 0,
        impactY: -10,
        context: const ShotContext(
          ballSource: MeasurementSource.measured,
          clubSpeedSource: MeasurementSource.measured,
          intent: ShotIntent.stock,
          goal: FittingGoal.accuracy,
        ),
      ),
    );
    final advice = result.recommendations.firstWhere(
      (r) => r.action == 'review_spin',
    );
    expect(advice.description, contains('striking lower can add spin'));
  });
  test(
    'equal face/path pointing away from target still flags a directional miss',
    () {
      final result = analyze(shot(direction: 10, path: 10, face: 10));
      expect(
        result.diagnostics.map((d) => d.metric),
        contains('launchDirection'),
      );
      expect(
        result.diagnostics.map((d) => d.metric),
        contains('lateralOffset'),
      );
      expect(
        result.diagnostics.map((d) => d.metric),
        isNot(contains('pathFaceAngleAlignment')),
      );
    },
  );
  test('signed face-to-path and lateral diagnostics mirror correctly', () {
    final a = analyze(shot(direction: 8, axis: 15, path: -3, face: 4));
    final b = analyze(shot(direction: -8, axis: -15, path: 3, face: -4));
    final da = a.diagnostics.firstWhere(
      (d) => d.metric == 'pathFaceAngleAlignment',
    );
    final db = b.diagnostics.firstWhere(
      (d) => d.metric == 'pathFaceAngleAlignment',
    );
    expect(da.measured, -db.measured);
  });
  test(
    'gain uses the same flight model without adding ball speed or removing curvature',
    () {
      final s = shot(ball: 130, launch: 5, spin: 4500, axis: 12, direction: 2);
      final result = analyze(s);
      expect(result.carryGap, isNotNull);
      expect(result.carryGap, closeTo(result.optimalCarry! - s.carry, 1e-9));
      var independentlyReachable = s.carry;
      for (double launch = 8; launch <= 22; launch++) {
        for (double spin = 1800; spin <= 4200; spin += 200) {
          final flight = BallFlightModel.standard.simulate(
            ballSpeedMph: s.ballSpeed,
            launchAngleDeg: launch,
            launchDirectionDeg: s.launchDirection,
            spinRpm: spin,
            spinAxisDeg: s.spinAxis,
          );
          if (flight.carry > independentlyReachable) {
            independentlyReachable = flight.carry;
          }
        }
      }
      expect(
        result.optimalCarry!,
        lessThanOrEqualTo(independentlyReachable + .01),
      );
      expect(identical(analyze(s), result), isTrue);
    },
  );
  test('approach feedback evaluates target and chosen landing requirement', () {
    final result = analyze(
      shot(
        club: '7i',
        ball: 100,
        speed: 75,
        launch: 10,
        spin: 3500,
        context: const ShotContext(
          ballSource: MeasurementSource.measured,
          clubSpeedSource: MeasurementSource.measured,
          intent: ShotIntent.stock,
          goal: FittingGoal.approach,
          targetCarry: 175,
          minimumDescent: 45,
        ),
      ),
    );
    expect(
      result.diagnostics.map((d) => d.metric),
      containsAll(['carryDistance', 'descentAngle']),
    );
    expect(result.carryGap, isNull);
  });
  test('putting is explicitly not assessed', () {
    expect(analyze(shot(club: 'pt')).assessed, isFalse);
  });
}
