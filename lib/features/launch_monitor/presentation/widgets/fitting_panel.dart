import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/app_icons.dart';
import '../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../shared/theme.dart';
import '../../../../shared/widgets/app_controls.dart';
import '../../application/clubs_notifier.dart';
import '../../application/fitting_capture_provider.dart';
import '../../application/fitting_review_provider.dart';
import '../../domain/entities/club.dart';
import '../../domain/entities/shot_context.dart';
import '../../domain/entities/shot_data.dart';
import 'fitting_round_view.dart';
import 'fitting_setup_dialog.dart';
import 'fitting_setup_row.dart';

/// `comparison` → `Comparison`, for enum names shown to the golfer.
String _cap(String raw) =>
    raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);

/// The bar across the top of the optimizer tab: the shot-intent chips the
/// feedback is judged against, and the chip that opens the equipment
/// comparison sheet — which turns accent while a comparison is recording so
/// the golfer never loses track of which setup is in play.
///
/// Same hairline-bordered strip as the dispersion tab's club filter, so the
/// tabs open with the same shape.
class FittingPanel extends ConsumerWidget {
  final List<ShotData>? shots;
  const FittingPanel({super.key, this.shots});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capture = ref.watch(fittingCaptureProvider);
    final active = ref.watch(activeClubProvider);
    final capturing = capture != null && capture.clubId == active?.id;
    final intent = ref.watch(shotIntentProvider);
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (shots == null && !capturing)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // The caps label is the first thing to go when a docked
                      // rail can't fit it beside both chips and the action.
                      if (constraints.maxWidth >= 240) ...[
                        const AppSectionLabel('Intent'),
                        const SizedBox(width: 8),
                      ],
                      for (final (i, label) in [
                        (ShotIntent.stock, 'Stock'),
                        (ShotIntent.partial, 'Partial'),
                      ]) ...[
                        AppChip(
                          label: label,
                          active: intent == i,
                          onTap: () =>
                              ref.read(shotIntentProvider.notifier).state = i,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          AppActionChip(
            icon: capturing ? AppIcons.dot : AppIcons.swap,
            emphasis: capturing,
            label: shots == null && capturing
                ? 'Recording ${capture.useCandidate ? "B" : "A"} · ${_cap(capture.phase.name)}'
                : 'Fitting comparison',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.surface,
              constraints: const BoxConstraints(maxWidth: 800),
              isScrollControlled: true,
              useSafeArea: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => ProviderScope(
                overrides: [
                  fittingReviewShotsProvider.overrideWithValue(shots),
                ],
                child: const FractionallySizedBox(
                  heightFactor: .92,
                  child: FittingSheet(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FittingSheet extends ConsumerWidget {
  const FittingSheet({super.key});

  Future<void> _startComparison(BuildContext context, WidgetRef ref) async {
    final clubs = ref.read(clubsProvider);
    final active = ref.read(activeClubProvider);
    final prefs = ref.read(unitPrefsProvider);
    final available = (clubs.isEmpty ? Club.catalog : clubs)
        .where((c) => c.id != 'pt')
        .toList();
    final selectedClub = available.any((c) => c.id == active?.id)
        ? active!.id
        : available.firstOrNull?.id;
    final draftKey = (
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      clubId: selectedClub,
      unitScale: prefs.dist(1),
    );
    final result = await showDialog<FittingCapture>(
      context: context,
      builder: (_) =>
          FittingSetupDialog(clubs: available, prefs: prefs, draftKey: draftKey),
    );
    if (result == null || !context.mounted) return;
    ref.read(fittingCaptureProvider.notifier).start(result);
    ref.read(activeClubProvider.notifier).state = available.firstWhere(
      (c) => c.id == result.clubId,
    );
    ref.read(fittingTrialSelectionProvider.notifier).state = result.id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(fittingReviewProvider);
    final capture = ref.watch(fittingCaptureProvider);
    final prefs = ref.watch(unitPrefsProvider);
    final active = ref.watch(activeClubProvider);
    final recording =
        review.live && capture != null && review.selected == capture.id;
    final comparison = review.comparison;
    final muted = AppTextStyles.sans(
      size: 13,
      color: AppColors.textMuted,
    ).copyWith(height: 1.45);

    return Column(
      children: [
        AppSheetHeader(
          title: 'Equipment comparison',
          onClose: () => context.pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Alternate A and B in short blocks. Keep ordinary mishits and use the same ball and conditions.',
                style: muted,
              ),
              if (review.live) ...[
                const SizedBox(height: 16),
                AppPrimaryButton(
                  icon: AppIcons.add,
                  label: 'New comparison',
                  onPressed: () => _startComparison(context, ref),
                ),
              ],
              if (review.trialIds.isNotEmpty) ...[
                const SizedBox(height: 20),
                AppSectionLabel(
                  'Comparison',
                  trailing: '${review.trialIds.length}',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < review.trialIds.length; i++)
                      AppChip(
                        label:
                            '${i + 1} · ${review.labels[review.trialIds[i]]}',
                        active: review.selected == review.trialIds[i],
                        onTap: () => ref
                            .read(fittingTrialSelectionProvider.notifier)
                            .state = review.trialIds[i],
                      ),
                  ],
                ),
              ],
              if (recording) ...[
                const SizedBox(height: 16),
                FittingCaptureControls(
                  capture: capture,
                  paused: active?.id != capture.clubId,
                  onSetup: (candidate) => ref
                      .read(fittingCaptureProvider.notifier)
                      .select(useCandidate: candidate),
                  onPhase: (phase) => ref
                      .read(fittingCaptureProvider.notifier)
                      .select(phase: phase),
                  onStop: () => ref.read(fittingCaptureProvider.notifier).stop(),
                ),
              ],
              if (comparison != null) ...[
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    comparison.verdict,
                    style: AppTextStyles.sans(
                      size: 14,
                      weight: FontWeight.w600,
                    ).copyWith(height: 1.4),
                  ),
                ),
                if (comparison.context != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_cap(comparison.context!.goal.name)} · ${_cap(comparison.context!.intent.name)}'
                    '${comparison.context!.conditions.isEmpty ? '' : ' · ${comparison.context!.conditions}'}',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FittingEquipmentDetails(
                  baseline:
                      comparison.baselineSetup ??
                      (recording ? capture.baseline : null),
                  candidate:
                      comparison.candidateSetup ??
                      (recording ? capture.candidate : null),
                ),
                FittingRoundView(
                  title: 'Comparison round',
                  round: comparison.comparison,
                  prefs: prefs,
                ),
                FittingRoundView(
                  title: 'Confirmation round',
                  round: comparison.confirmation,
                  prefs: prefs,
                ),
                const SizedBox(height: 20),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Start a comparison to record two setups and evaluate them over repeated shots.',
                    style: muted,
                  ),
                ),
              const FittingEvidenceNote(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The live recording card: which setup and round the next shot counts
/// toward. Accent-edged, because this is the golfer's own data in flight.
class FittingCaptureControls extends StatelessWidget {
  final FittingCapture capture;
  final bool paused;
  final ValueChanged<bool> onSetup;
  final ValueChanged<FittingPhase> onPhase;
  final VoidCallback onStop;
  const FittingCaptureControls({
    super.key,
    required this.capture,
    required this.paused,
    required this.onSetup,
    required this.onPhase,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final status = paused ? AppColors.textMuted : context.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: paused ? AppColors.border2 : context.accentBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: status, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  paused
                      ? 'Paused · select ${capture.clubId} to resume'
                      : 'Recording ${capture.clubId} · ${_cap(capture.intent.name)}',
                  style: AppTextStyles.sans(
                    size: 13,
                    weight: FontWeight.w600,
                    color: status,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const AppSectionLabel('Setup in play'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final side in [false, true])
                AppChip(
                  label:
                      '${side ? "B" : "A"} · ${side ? capture.candidate.name : capture.baseline.name}',
                  active: capture.useCandidate == side,
                  onTap: () => onSetup(side),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const AppSectionLabel('Round'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final phase in FittingPhase.values)
                AppChip(
                  label: _cap(phase.name),
                  active: capture.phase == phase,
                  onTap: () => onPhase(phase),
                ),
            ],
          ),
          const SizedBox(height: 4),
          AppTextAction(
            icon: AppIcons.stop,
            label: 'Stop recording comparison',
            onTap: onStop,
          ),
        ],
      ),
    );
  }
}

class FittingEquipmentDetails extends StatelessWidget {
  final EquipmentSetup? baseline;
  final EquipmentSetup? candidate;
  const FittingEquipmentDetails({super.key, this.baseline, this.candidate});

  @override
  Widget build(BuildContext context) => AppCollapsible(
    label: 'Tested equipment',
    children: [
      for (final (tag, setup) in [('A', baseline), ('B', candidate)])
        if (setup != null) FittingSetupRow.fromSetup(setup, tag: tag),
    ],
  );
}

class FittingEvidenceNote extends StatelessWidget {
  const FittingEvidenceNote({super.key});

  @override
  Widget build(BuildContext context) => AppCollapsible(
    label: 'How to interpret the results',
    children: [
      Text(
        'Launch inputs must be verified device measurements. Flight outcomes are simulated. '
        'The uncertainty range describes shot-to-shot sampling, not device or model accuracy. '
        'A repeated advantage supports comparing these tested setups; it does not prescribe an untested head or shaft.',
        style: AppTextStyles.sans(
          size: 12,
          color: AppColors.textMuted,
        ).copyWith(height: 1.45),
      ),
    ],
  );
}
