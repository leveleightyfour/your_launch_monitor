import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/sessions_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

/// How much history feeds the bag's Distances and Dispersion tabs.
enum BagScopeKind { lastFive, allTime, single }

/// The selected scope. The in-progress session counts as the most recent
/// session, selectable as [liveSessionId] when scoping to a single one.
class BagScope {
  static const liveSessionId = 'live';

  final BagScopeKind kind;
  final String? sessionId;
  final String? sessionName;

  const BagScope.lastFive()
    : kind = BagScopeKind.lastFive,
      sessionId = null,
      sessionName = null;

  const BagScope.allTime()
    : kind = BagScopeKind.allTime,
      sessionId = null,
      sessionName = null;

  const BagScope.single(this.sessionId, this.sessionName)
    : kind = BagScopeKind.single;
}

final bagScopeProvider = StateProvider<BagScope>(
  (ref) => const BagScope.lastFive(),
);

/// Whether fenced outlier shots count toward the distance stats.
final bagIncludeOutliersProvider = StateProvider<bool>((ref) => false);

/// Every shot feeding the bag tabs under the selected scope, live session
/// first, then saved sessions most recent first.
final bagShotsProvider = Provider<List<ShotData>>((ref) {
  final live = ref.watch(launchMonitorProvider.select((s) => s.shots));
  final past = ref.watch(sessionsProvider);
  final scope = ref.watch(bagScopeProvider);

  switch (scope.kind) {
    case BagScopeKind.allTime:
      return [...live, for (final s in past) ...s.shots];
    case BagScopeKind.lastFive:
      final shots = <ShotData>[...live];
      var sessionsTaken = live.isEmpty ? 0 : 1;
      for (final s in past) {
        if (sessionsTaken >= 5) break;
        shots.addAll(s.shots);
        sessionsTaken++;
      }
      return shots;
    case BagScopeKind.single:
      if (scope.sessionId == BagScope.liveSessionId) return live;
      return [
        for (final s in past)
          if (s.id == scope.sessionId) ...s.shots,
      ];
  }
});
