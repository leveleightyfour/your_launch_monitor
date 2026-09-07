import 'dart:convert';

/// Unknown is deliberate: older recordings did not preserve device validity.
enum MeasurementSource { unknown, measured, estimated, simulated, unavailable }

enum ShotIntent { unknown, stock, partial }

enum FittingGoal { carry, accuracy, approach }

enum FittingPhase { comparison, confirmation }

class EquipmentSetup {
  final String name;
  final String head;
  final String shaft;
  final String loft;
  final String length;
  final String notes;
  const EquipmentSetup({
    required this.name,
    required this.head,
    required this.shaft,
    required this.loft,
    required this.length,
    this.notes = '',
  });
  Map<String, dynamic> toJson() => {
    'name': name,
    'head': head,
    'shaft': shaft,
    'loft': loft,
    'length': length,
    'notes': notes,
  };
  factory EquipmentSetup.fromJson(Map<String, dynamic> j) => EquipmentSetup(
    name: j['name'] as String,
    head: j['head'] as String,
    shaft: j['shaft'] as String,
    loft: j['loft'] as String,
    length: j['length'] as String,
    notes: j['notes'] as String? ?? '',
  );
}

/// Immutable snapshot captured at impact, persisted with the shot. Distances
/// are yards. Fitting outcomes are modelled, even when launch data is measured.
class ShotContext {
  final MeasurementSource ballSource;
  final MeasurementSource clubSpeedSource;
  final ShotIntent intent;
  final FittingGoal goal;
  final double? targetCarry;
  final double offlineTolerance;
  final double minimumDescent;
  final String? trialId;
  final EquipmentSetup? equipment;
  final bool candidate;
  final FittingPhase phase;
  final String conditions;

  const ShotContext({
    this.ballSource = MeasurementSource.unknown,
    this.clubSpeedSource = MeasurementSource.unknown,
    this.intent = ShotIntent.unknown,
    this.goal = FittingGoal.carry,
    this.targetCarry,
    this.offlineTolerance = 20,
    this.minimumDescent = 40,
    this.trialId,
    this.equipment,
    this.candidate = false,
    this.phase = FittingPhase.comparison,
    this.conditions = '',
  });

  ShotContext copyWith({
    MeasurementSource? ballSource,
    MeasurementSource? clubSpeedSource,
    ShotIntent? intent,
  }) => ShotContext(
    ballSource: ballSource ?? this.ballSource,
    clubSpeedSource: clubSpeedSource ?? this.clubSpeedSource,
    intent: intent ?? this.intent,
    goal: goal,
    targetCarry: targetCarry,
    offlineTolerance: offlineTolerance,
    minimumDescent: minimumDescent,
    trialId: trialId,
    equipment: equipment,
    candidate: candidate,
    phase: phase,
    conditions: conditions,
  );

  Map<String, dynamic> toJson() => {
    'v': 1,
    'ballSource': ballSource.name,
    'clubSpeedSource': clubSpeedSource.name,
    'intent': intent.name,
    'goal': goal.name,
    'targetCarry': targetCarry,
    'offlineTolerance': offlineTolerance,
    'minimumDescent': minimumDescent,
    'trialId': trialId,
    'equipment': equipment?.toJson(),
    'candidate': candidate,
    'phase': phase.name,
    'conditions': conditions,
  };
  String encode() => jsonEncode(toJson());
  static ShotContext decode(String? value) {
    if (value == null || value.isEmpty) return const ShotContext();
    try {
      final j = jsonDecode(value) as Map<String, dynamic>;
      if (j['v'] != 1) return const ShotContext();
      return ShotContext(
        ballSource: MeasurementSource.values.byName(j['ballSource'] as String),
        clubSpeedSource: MeasurementSource.values.byName(
          j['clubSpeedSource'] as String,
        ),
        intent: ShotIntent.values.byName(j['intent'] as String),
        goal: FittingGoal.values.byName(j['goal'] as String),
        targetCarry: (j['targetCarry'] as num?)?.toDouble(),
        offlineTolerance: (j['offlineTolerance'] as num).toDouble(),
        minimumDescent: (j['minimumDescent'] as num).toDouble(),
        trialId: j['trialId'] as String?,
        equipment: j['equipment'] == null
            ? null
            : EquipmentSetup.fromJson(j['equipment'] as Map<String, dynamic>),
        candidate: j['candidate'] as bool,
        phase: FittingPhase.values.byName(j['phase'] as String),
        conditions: j['conditions'] as String? ?? '',
      );
    } catch (_) {
      // Never promote damaged or future metadata to trusted measurements.
      return const ShotContext();
    }
  }
}
