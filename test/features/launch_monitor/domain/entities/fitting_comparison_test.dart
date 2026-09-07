import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/fitting_comparison.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_context.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

const setupA = EquipmentSetup(
  name: 'A',
  head: 'Head A',
  shaft: 'Shaft A',
  loft: '10',
  length: '45 in',
);
const setupB = EquipmentSetup(
  name: 'B',
  head: 'Head B',
  shaft: 'Shaft B',
  loft: '10',
  length: '45 in',
);
ShotData sample(
  int i, {
  bool candidate = false,
  double gain = 10,
  double direction = 0,
  FittingPhase phase = FittingPhase.comparison,
  MeasurementSource source = MeasurementSource.measured,
  String club = 'dr',
  FittingGoal goal = FittingGoal.carry,
  double? target,
}) => ShotData(
  clubId: club,
  ballSpeed: 140 + (i % 5) * .4 + (candidate ? gain : 0),
  clubSpeed: 100,
  spinRate: 2500,
  spinAxis: 0,
  launchAngle: 14,
  launchDirection: direction,
  context: ShotContext(
    ballSource: source,
    clubSpeedSource: MeasurementSource.measured,
    intent: ShotIntent.stock,
    goal: goal,
    targetCarry: target,
    trialId: 'trial',
    equipment: candidate ? setupB : setupA,
    candidate: candidate,
    phase: phase,
    conditions: 'Same ball, tee and room',
  ),
);
List<ShotData> round({
  FittingPhase phase = FittingPhase.comparison,
  double gain = 10,
  double direction = 0,
}) => [
  for (var i = 0; i < 20; i++)
    sample(
      i,
      candidate: (i ~/ 5).isOdd,
      gain: gain,
      direction: (i ~/ 5).isOdd ? direction : 0,
      phase: phase,
    ),
];

void main() {
  test('no claim from a small sample', () {
    final r = compareFitting(round().take(8).toList(), 'trial');
    expect(r.comparison.enoughEvidence, isFalse);
    expect(r.verdict, contains('10 measured shots'));
  });
  test('a full A block then B block must be alternated', () {
    final shots = [for (var i = 0; i < 20; i++) sample(i, candidate: i >= 10)];
    expect(
      compareFitting(shots, 'trial').comparison.message,
      contains('Alternate'),
    );
  });
  test('simulated and unknown readings never count as fitting evidence', () {
    final shots = [
      for (var i = 0; i < 40; i++)
        sample(
          i,
          candidate: i.isOdd,
          source: i.isEven
              ? MeasurementSource.simulated
              : MeasurementSource.unknown,
        ),
    ];
    final r = compareFitting(shots, 'trial');
    expect(r.comparison.excluded, 40);
    expect(r.comparison.baseline, isNull);
    expect(r.comparison.candidate, isNull);
  });
  test('candidate advantage must repeat on separate confirmation shots', () {
    final comparison = compareFitting(round(), 'trial');
    expect(comparison.comparison.favourable, isTrue);
    expect(comparison.verdict, contains('separate confirmation'));
    final confirmed = compareFitting([
      ...round(),
      ...round(phase: FittingPhase.confirmation),
    ], 'trial');
    expect(confirmed.confirmation.favourable, isTrue);
    expect(confirmed.verdict, contains('repeated in both rounds'));
    expect(
      compareFitting([
        ...round(),
        ...round(phase: FittingPhase.confirmation, gain: 0),
      ], 'trial').verdict,
      contains('not confirmed'),
    );
  });
  test('equal results and carry at the expense of direction do not win', () {
    expect(
      compareFitting(round(gain: 0), 'trial').comparison.favourable,
      isFalse,
    );
    final r = compareFitting(round(direction: 10), 'trial');
    expect(r.comparison.favourable, isFalse);
    expect(r.comparison.message, contains('trade-offs'));
  });
  test('mixed clubs or objectives block the comparison', () {
    expect(
      compareFitting([
        ...round(),
        sample(22, club: '7i'),
      ], 'trial').incompatibility,
      isNotNull,
    );
    expect(
      compareFitting([
        ...round(),
        sample(22, goal: FittingGoal.approach, target: 160),
      ], 'trial').incompatibility,
      isNotNull,
    );
  });
  test('reversing stored shot order preserves evidence and decisions', () {
    final shots = round();
    final a = compareFitting(shots, 'trial').comparison;
    final b = compareFitting(shots.reversed.toList(), 'trial').comparison;
    expect(a.switches, b.switches);
    expect(a.improvement, closeTo(b.improvement!, 1e-9));
    expect(a.favourable, b.favourable);
  });
  test('metadata round trip preserves evidence, specs, phase and units', () {
    final original = sample(
      1,
      candidate: true,
      phase: FittingPhase.confirmation,
    ).context;
    final restored = ShotContext.decode(original.encode());
    expect(restored.toJson(), original.toJson());
    expect(
      sample(1).copyWith(context: restored).copyWith(dbId: 2).context.encode(),
      original.encode(),
    );
    for (final invalid in [null, '', '{', '{"v":999}']) {
      expect(ShotContext.decode(invalid).ballSource, MeasurementSource.unknown);
    }
  });
}
