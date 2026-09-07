import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/shot_context.dart';

class FittingCapture {
  final String id;
  final String clubId;
  final EquipmentSetup baseline;
  final EquipmentSetup candidate;
  final ShotIntent intent;
  final FittingGoal goal;
  final double? targetCarry;
  final double offlineTolerance;
  final double minimumDescent;
  final String conditions;
  final bool useCandidate;
  final FittingPhase phase;
  const FittingCapture({
    required this.id,
    required this.clubId,
    required this.baseline,
    required this.candidate,
    required this.intent,
    required this.goal,
    this.targetCarry,
    required this.offlineTolerance,
    required this.minimumDescent,
    required this.conditions,
    this.useCandidate = false,
    this.phase = FittingPhase.comparison,
  });
  FittingCapture select({bool? useCandidate, FittingPhase? phase}) =>
      FittingCapture(
        id: id,
        clubId: clubId,
        baseline: baseline,
        candidate: candidate,
        intent: intent,
        goal: goal,
        targetCarry: targetCarry,
        offlineTolerance: offlineTolerance,
        minimumDescent: minimumDescent,
        conditions: conditions,
        useCandidate: useCandidate ?? this.useCandidate,
        phase: phase ?? this.phase,
      );
  ShotContext get context => ShotContext(
    intent: intent,
    goal: goal,
    targetCarry: targetCarry,
    offlineTolerance: offlineTolerance,
    minimumDescent: minimumDescent,
    trialId: id,
    equipment: useCandidate ? candidate : baseline,
    candidate: useCandidate,
    phase: phase,
    conditions: conditions,
  );
}

final fittingCaptureProvider =
    NotifierProvider<FittingCaptureNotifier, FittingCapture?>(
      FittingCaptureNotifier.new,
    );
final shotIntentProvider = StateProvider<ShotIntent>((_) => ShotIntent.stock);

/// Session-lived: capture must continue while another session tab is visible.
class FittingCaptureNotifier extends Notifier<FittingCapture?> {
  @override
  FittingCapture? build() => null;
  void start(FittingCapture capture) => state = capture;
  void stop() => state = null;
  void select({bool? useCandidate, FittingPhase? phase}) =>
      state = state?.select(useCandidate: useCandidate, phase: phase);
}
