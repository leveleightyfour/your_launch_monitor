import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/features/launch_monitor/application/fitting_draft_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_context.dart';

void main() {
  test(
    'draft validates, retains previous steps, and converts metres to yards',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = fittingDraftProvider((
        id: 'trial',
        clubId: '7i',
        unitScale: .9144,
      ));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final draft = container.read(provider.notifier);
      expect(draft.next(), isFalse);
      draft.field('conditions', 'Same ball and mat');
      draft.goal(FittingGoal.approach);
      draft.field('target', 'NaN');
      expect(draft.next(), isFalse);
      draft.field('target', '137.16');
      draft.field('tolerance', '18.288');
      expect(draft.next(), isTrue);
      for (final side in ['A', 'B']) {
        expect(draft.next(), isFalse);
        for (final key in ['head', 'shaft', 'loft', 'length']) {
          draft.field('$key$side', '$key $side');
        }
        expect(draft.next(), isTrue);
      }
      draft.back();
      expect(container.read(provider).fields['headA'], 'head A');
      expect(draft.next(), isTrue);
      final result = draft.complete()!;
      expect(result.targetCarry, closeTo(150, 1e-9));
      expect(result.offlineTolerance, closeTo(20, 1e-9));
      expect(result.context.equipment!.head, 'head A');
    },
  );
}
