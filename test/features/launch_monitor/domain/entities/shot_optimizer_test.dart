import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_optimizer.dart';

ShotData _shot({
  String? clubId,
  double ballSpeed = 150,
  double spinRate = 2500,
  double launchAngle = 12,
  double clubSpeed = 100,
  double? angleOfAttack,
  double? dynamicLoft,
  double? swingPath,
  double? faceAngle,
  double? horizontalImpact,
  double? verticalImpact,
}) {
  return ShotData(
    clubId: clubId,
    ballSpeed: ballSpeed,
    spinRate: spinRate,
    spinAxis: 0,
    launchDirection: 0,
    launchAngle: launchAngle,
    clubSpeed: clubSpeed,
    angleOfAttack: angleOfAttack,
    dynamicLoft: dynamicLoft,
    swingPath: swingPath,
    faceAngle: faceAngle,
    horizontalImpact: horizontalImpact,
    verticalImpact: verticalImpact,
  );
}

void main() {
  final optimizer = ShotOptimizer();

  group('OptimalRanges', () {
    test('driver spin window tightens as club speed increases', () {
      expect(
        OptimalRanges.getRange(ClubType.wood, 'spinRate',
            clubSpeed: 85, clubId: 'dr'),
        (2500.0, 3200.0),
      );
      expect(
        OptimalRanges.getRange(ClubType.wood, 'spinRate',
            clubSpeed: 95, clubId: 'dr'),
        (2200.0, 2800.0),
      );
      expect(
        OptimalRanges.getRange(ClubType.wood, 'spinRate',
            clubSpeed: 110, clubId: 'dr'),
        (2000.0, 2600.0),
      );
    });

    test('iron spin follows the 1000 rpm per club-number rule', () {
      expect(
        OptimalRanges.getRange(ClubType.iron, 'spinRate', clubId: '7i'),
        (6500.0, 7500.0),
      );
      expect(
        OptimalRanges.getRange(ClubType.iron, 'spinRate', clubId: '4i'),
        (3500.0, 4500.0),
      );
      // Unknown iron falls back to a safe window.
      expect(
        OptimalRanges.getRange(ClubType.iron, 'spinRate'),
        (5000.0, 7500.0),
      );
    });

    test('named wedges use their fixed spin windows', () {
      expect(
        OptimalRanges.getRange(ClubType.wedge, 'spinRate', clubId: 'sw'),
        (9500.0, 11500.0),
      );
      expect(
        OptimalRanges.getRange(ClubType.wedge, 'spinRate', clubId: 'pw'),
        (8500.0, 10500.0),
      );
    });

    test('degree wedges scale spin window with loft', () {
      final (min56, max56) =
          OptimalRanges.getRange(ClubType.wedge, 'spinRate', clubId: '56deg');
      expect(min56, 9600.0);
      expect(max56, 11600.0);

      // Higher loft → higher spin target.
      final (min60, _) =
          OptimalRanges.getRange(ClubType.wedge, 'spinRate', clubId: '60deg');
      expect(min60, greaterThan(min56));
    });
  });

  group('ShotOptimizer.analyze', () {
    test('putter shots produce no diagnostics or recommendations', () {
      final analysis = optimizer.analyze(
        _shot(clubId: 'pt', ballSpeed: 10, clubSpeed: 8, spinRate: 100,
            launchAngle: 2),
        ClubType.putter,
        clubId: 'pt',
      );
      expect(analysis.diagnostics, isEmpty);
      expect(analysis.recommendations, isEmpty);
    });

    test('optimal driver shot has no diagnostics and no carry gap', () {
      final analysis = optimizer.analyze(
        _shot(clubId: 'dr', angleOfAttack: 4),
        ClubType.wood,
        clubId: 'dr',
      );
      expect(analysis.diagnostics, isEmpty);
      expect(analysis.carryGap, isNull);
      expect(analysis.optimalCarry, isNotNull);
      expect(analysis.summary, contains('optimal'));
    });

    test('low smash factor is critical and yards lost scale with speed', () {
      // smash = 130/100 = 1.30, min optimal 1.45 → deficit 0.15.
      final analysis = optimizer.analyze(
        _shot(clubId: 'dr', ballSpeed: 130),
        ClubType.wood,
        clubId: 'dr',
      );
      final diag = analysis.diagnostics
          .firstWhere((d) => d.metric == 'smashFactor');
      expect(diag.severity, Severity.critical);
      // 0.15 smash × 100 mph × 1.9 yds per ball mph ≈ 28.5 yds.
      expect(diag.estimatedYardsLost, closeTo(28.5, 0.5));
      expect(
        analysis.recommendations.first.action,
        'improve_center_contact',
      );
      // A flagged shot reports its carry gap.
      expect(analysis.carryGap, isNotNull);
    });

    test('launch angle severity scales with deviation', () {
      // Driver moderate band wants 10–14°; 4° is 6° low → critical.
      final analysis = optimizer.analyze(
        _shot(clubId: 'dr', launchAngle: 4),
        ClubType.wood,
        clubId: 'dr',
      );
      final diag = analysis.diagnostics
          .firstWhere((d) => d.metric == 'launchAngle');
      expect(diag.severity, Severity.critical);
    });

    test('spin rate within 10% of the window is not flagged', () {
      // 7i window is 6500–7500; 6000 is ~7.7% below → tolerated.
      final analysis = optimizer.analyze(
        _shot(clubId: '7i', ballSpeed: 120, clubSpeed: 85, spinRate: 6000,
            launchAngle: 18),
        ClubType.iron,
        clubId: '7i',
      );
      expect(
        analysis.diagnostics.where((d) => d.metric == 'spinRate'),
        isEmpty,
      );
    });

    test('spin rate well below the window is flagged', () {
      // 5500 is ~15% below the 7i window → flagged.
      final analysis = optimizer.analyze(
        _shot(clubId: '7i', ballSpeed: 120, clubSpeed: 85, spinRate: 5500,
            launchAngle: 18),
        ClubType.iron,
        clubId: '7i',
      );
      final diag =
          analysis.diagnostics.firstWhere((d) => d.metric == 'spinRate');
      expect(diag.severity, Severity.high);
    });

    test('hitting down on the driver is diagnosed and recommended against',
        () {
      final analysis = optimizer.analyze(
        _shot(clubId: 'dr', angleOfAttack: -4),
        ClubType.wood,
        clubId: 'dr',
      );
      final diag = analysis.diagnostics
          .firstWhere((d) => d.metric == 'attackAngle');
      expect(diag.severity, Severity.high);
      expect(
        analysis.recommendations.map((r) => r.action),
        contains('hit_up_on_driver'),
      );
    });

    test('mini driver gets the tee-club attack angle treatment', () {
      final analysis = optimizer.analyze(
        _shot(clubId: 'mdr', spinRate: 2600, angleOfAttack: -2),
        ClubType.miniDriver,
        clubId: 'mdr',
      );
      expect(
        analysis.diagnostics.map((d) => d.metric),
        contains('attackAngle'),
      );
      expect(
        analysis.recommendations.map((r) => r.action),
        contains('hit_up_on_driver'),
      );
    });

    test('picking a fairway wood is flagged with a strike-down tip', () {
      final analysis = optimizer.analyze(
        _shot(clubId: '3w', ballSpeed: 140, clubSpeed: 95, spinRate: 3000,
            launchAngle: 15, angleOfAttack: 2),
        ClubType.wood,
        clubId: '3w',
      );
      final diag = analysis.diagnostics
          .firstWhere((d) => d.metric == 'attackAngle');
      expect(diag.possibleRootCauses, contains('picking_the_ball'));
      expect(
        analysis.recommendations.map((r) => r.action),
        contains('strike_down_through_the_ball'),
      );
    });

    test('digging a wedge is flagged with a shallow-out tip', () {
      final analysis = optimizer.analyze(
        _shot(clubId: 'sw', ballSpeed: 80, clubSpeed: 60, spinRate: 10000,
            launchAngle: 30, angleOfAttack: -11),
        ClubType.wedge,
        clubId: 'sw',
      );
      final diag = analysis.diagnostics
          .firstWhere((d) => d.metric == 'attackAngle');
      expect(diag.possibleRootCauses, contains('digging'));
      expect(
        analysis.recommendations.map((r) => r.action),
        contains('shallow_the_attack_angle'),
      );
    });

    test('spin loft mismatch produces a stabilize-delivery recommendation',
        () {
      // Spin loft = 25 - (-4) = 29° → expected ≈ 29 × 342 ≈ 9,918 rpm,
      // measured 7,000 rpm is > 15% off.
      final analysis = optimizer.analyze(
        _shot(clubId: '7i', ballSpeed: 120, clubSpeed: 85, spinRate: 7000,
            launchAngle: 18, dynamicLoft: 25, angleOfAttack: -4),
        ClubType.iron,
        clubId: '7i',
      );
      expect(
        analysis.diagnostics.map((d) => d.metric),
        contains('spinLoftMismatch'),
      );
      expect(
        analysis.recommendations.map((r) => r.action),
        contains('stabilize_delivery'),
      );
    });

    test('diagnostics are sorted most severe first', () {
      final analysis = optimizer.analyze(
        _shot(
          clubId: 'dr',
          ballSpeed: 130, // critical smash
          launchAngle: 8, // medium-low launch
          angleOfAttack: -1, // medium attack angle
        ),
        ClubType.wood,
        clubId: 'dr',
      );
      final severities =
          analysis.diagnostics.map((d) => d.severity.index).toList();
      expect(severities, orderedEquals([...severities]..sort()));
      expect(analysis.diagnostics.first.severity, Severity.critical);
    });

    test('recommendations are deduplicated by action', () {
      final analysis = optimizer.analyze(
        _shot(clubId: 'dr', ballSpeed: 130, launchAngle: 4),
        ClubType.wood,
        clubId: 'dr',
      );
      final actions = analysis.recommendations.map((r) => r.action).toList();
      expect(actions.toSet().length, actions.length);
      // Sorted by priority.
      final priorities =
          analysis.recommendations.map((r) => r.priority).toList();
      expect(priorities, orderedEquals([...priorities]..sort()));
    });

    test('fairway wood optimal carry is lower than driver at equal speed',
        () {
      final driver = optimizer.analyze(
        _shot(clubId: 'dr', ballSpeed: 130),
        ClubType.wood,
        clubId: 'dr',
      );
      final threeWood = optimizer.analyze(
        _shot(clubId: '3w', ballSpeed: 130, spinRate: 3000, launchAngle: 16),
        ClubType.wood,
        clubId: '3w',
      );
      expect(driver.optimalCarry, isNotNull);
      expect(threeWood.optimalCarry, isNotNull);
      expect(threeWood.optimalCarry!, lessThan(driver.optimalCarry!));
    });

    test('zero club speed yields no optimal carry estimate', () {
      final analysis = optimizer.analyze(
        _shot(clubId: '7i', clubSpeed: 0, ballSpeed: 0, spinRate: 7000,
            launchAngle: 18),
        ClubType.iron,
        clubId: '7i',
      );
      expect(analysis.optimalCarry, isNull);
      expect(analysis.carryGap, isNull);
    });
  });
}
