import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/fitting_comparison.dart';
import '../domain/entities/shot_data.dart';
import 'fitting_capture_provider.dart';
import 'providers.dart';

/// Scoped override lets saved sessions use the same review as live sessions.
final fittingReviewShotsProvider = Provider<List<ShotData>?>(
  (_) => null,
  dependencies: const [],
);
final fittingTrialSelectionProvider = StateProvider.autoDispose<String?>(
  (_) => null,
);

class FittingReviewData {
  final bool live;
  final List<String> trialIds;
  final Map<String, String> labels;
  final String? selected;
  final FittingComparison? comparison;
  const FittingReviewData({
    required this.live,
    required this.trialIds,
    required this.labels,
    this.selected,
    this.comparison,
  });
}

final fittingReviewProvider = Provider.autoDispose<FittingReviewData>((ref) {
  final explicit = ref.watch(fittingReviewShotsProvider);
  final shots =
      explicit ??
      ref.watch(launchMonitorProvider.select((s) => s.shots)) ??
      const <ShotData>[];
  final capture = ref.watch(fittingCaptureProvider);
  final ids = shots
      .map((s) => s.context.trialId)
      .whereType<String>()
      .toSet()
      .toList();
  if (explicit == null && capture != null && !ids.contains(capture.id)) {
    ids.insert(0, capture.id);
  }
  final requested = ref.watch(fittingTrialSelectionProvider);
  final selected = ids.contains(requested) ? requested : ids.firstOrNull;
  return FittingReviewData(
    live: explicit == null,
    trialIds: ids,
    selected: selected,
    labels: {
      for (final id in ids)
        id: id == capture?.id
            ? '${capture!.baseline.name} / ${capture.candidate.name}'
            : '${shots.firstWhere((s) => s.context.trialId == id).clubId}',
    },
    comparison: selected == null ? null : compareFitting(shots, selected),
  );
}, dependencies: [fittingReviewShotsProvider]);
