import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/shot_context.dart';
import 'fitting_capture_provider.dart';

typedef FittingDraftKey = ({String id, String? clubId, double unitScale});

class FittingDraft {
  final int step;
  final String? clubId;
  final ShotIntent intent;
  final FittingGoal goal;
  final Map<String, String> fields;
  final Map<String, String> errors;
  const FittingDraft({
    this.step = 0,
    this.clubId,
    this.intent = ShotIntent.stock,
    this.goal = FittingGoal.carry,
    this.fields = const {},
    this.errors = const {},
  });
  FittingDraft copyWith({
    int? step,
    String? clubId,
    ShotIntent? intent,
    FittingGoal? goal,
    Map<String, String>? fields,
    Map<String, String>? errors,
  }) => FittingDraft(
    step: step ?? this.step,
    clubId: clubId ?? this.clubId,
    intent: intent ?? this.intent,
    goal: goal ?? this.goal,
    fields: fields ?? this.fields,
    errors: errors ?? this.errors,
  );
}

final fittingDraftProvider = NotifierProvider.autoDispose
    .family<FittingDraftNotifier, FittingDraft, FittingDraftKey>(
      FittingDraftNotifier.new,
    );

class FittingDraftNotifier
    extends AutoDisposeFamilyNotifier<FittingDraft, FittingDraftKey> {
  @override
  FittingDraft build(FittingDraftKey arg) => FittingDraft(
    clubId: arg.clubId,
    fields: {
      'nameA': 'Baseline',
      'nameB': 'Candidate',
      'tolerance': (20 * arg.unitScale).toStringAsFixed(1),
      'descent': '40',
    },
  );
  void field(String key, String value) => state = state.copyWith(
    fields: Map.unmodifiable({...state.fields, key: value}),
    errors: Map.unmodifiable({...state.errors}..remove(key)),
  );
  void club(String value) => state = state.copyWith(clubId: value);
  void intent(ShotIntent value) => state = state.copyWith(intent: value);
  void goal(FittingGoal value) => state = state.copyWith(goal: value);
  void back() =>
      state = state.copyWith(step: (state.step - 1).clamp(0, 3), errors: {});
  bool next() {
    final errors = validateStep(state.step);
    if (errors.isNotEmpty) {
      state = state.copyWith(errors: errors);
      return false;
    }
    state = state.copyWith(step: (state.step + 1).clamp(0, 3), errors: {});
    return true;
  }

  Map<String, String> validateStep(int step) {
    final errors = <String, String>{};
    void required(String key) {
      if ((state.fields[key] ?? '').trim().isEmpty) {
        errors[key] = 'Complete this field';
      }
    }

    void number(String key, double min, double max) {
      final x = double.tryParse(state.fields[key] ?? '');
      if (x == null || !x.isFinite || x < min || x > max) {
        errors[key] = 'Use a number between $min and $max';
      }
    }

    if (step == 0) {
      if (state.clubId == null) errors['club'] = 'Choose a club';
      required('conditions');
      number('tolerance', 1, 100);
      if (state.goal == FittingGoal.approach) {
        number('target', 1, 400);
        number('descent', 1, 89);
      }
    } else if (step < 3) {
      final side = step == 1 ? 'A' : 'B';
      for (final key in ['name', 'head', 'shaft', 'loft', 'length']) {
        required('$key$side');
      }
    }
    return errors;
  }

  FittingCapture? complete() {
    for (var step = 0; step < 3; step++) {
      final errors = validateStep(step);
      if (errors.isNotEmpty) {
        state = state.copyWith(step: step, errors: errors);
        return null;
      }
    }
    String text(String key) => (state.fields[key] ?? '').trim();
    EquipmentSetup setup(String side) => EquipmentSetup(
      name: text('name$side'),
      head: text('head$side'),
      shaft: text('shaft$side'),
      loft: text('loft$side'),
      length: text('length$side'),
      notes: text('notes$side'),
    );
    return FittingCapture(
      id: arg.id,
      clubId: state.clubId!,
      baseline: setup('A'),
      candidate: setup('B'),
      intent: state.intent,
      goal: state.goal,
      targetCarry: state.goal == FittingGoal.approach
          ? double.parse(text('target')) / arg.unitScale
          : null,
      offlineTolerance: double.parse(text('tolerance')) / arg.unitScale,
      minimumDescent: state.goal == FittingGoal.approach
          ? double.parse(text('descent'))
          : 40,
      conditions: text('conditions'),
    );
  }
}
