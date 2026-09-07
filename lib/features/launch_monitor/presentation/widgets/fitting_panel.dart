import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/app_icons.dart';
import '../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../shared/theme.dart';
import '../../application/clubs_notifier.dart';
import '../../application/fitting_capture_provider.dart';
import '../../application/fitting_review_provider.dart';
import '../../domain/entities/club.dart';
import '../../domain/entities/shot_context.dart';
import '../../domain/entities/shot_data.dart';
import 'fitting_round_view.dart';
import 'fitting_setup_dialog.dart';

class FittingPanel extends ConsumerWidget {
  final List<ShotData>? shots;
  const FittingPanel({super.key, this.shots});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capture = ref.watch(fittingCaptureProvider);
    final active = ref.watch(activeClubProvider);
    final capturing = capture != null && capture.clubId == active?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      child: Wrap(
        spacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (shots == null && !capturing)
            DropdownButton<ShotIntent>(
              value: ref.watch(shotIntentProvider),
              icon: const Icon(AppIcons.chevronDown),
              items: const [
                DropdownMenuItem(
                  value: ShotIntent.stock,
                  child: Text('Stock / full swing'),
                ),
                DropdownMenuItem(
                  value: ShotIntent.partial,
                  child: Text('Partial shot'),
                ),
              ],
              onChanged: (v) {
                if (v != null) ref.read(shotIntentProvider.notifier).state = v;
              },
            ),
          TextButton.icon(
            icon: const Icon(AppIcons.swap),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            label: Text(
              shots == null && capturing
                  ? '${capture.useCandidate ? "B" : "A"} · ${capture.phase.name}'
                  : 'Fitting comparison',
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.surface,
              constraints: const BoxConstraints(maxWidth: 800),
              isScrollControlled: true,
              useSafeArea: true,
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(fittingReviewProvider);
    final capture = ref.watch(fittingCaptureProvider);
    final prefs = ref.watch(unitPrefsProvider);
    final active = ref.watch(activeClubProvider);
    final recording =
        review.live && capture != null && review.selected == capture.id;
    final comparison = review.comparison;
    final sections = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text('Equipment comparison', style: AppTextStyles.heading()),
          ),
          IconButton(
            tooltip: 'Close comparison',
            onPressed: () => context.pop(),
            icon: const Icon(AppIcons.close),
          ),
        ],
      ),
      Text(
        'Alternate A and B in short blocks. Keep ordinary mishits and use the same ball and conditions.',
        style: AppTextStyles.body(),
      ),
      if (review.live)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
          child: OutlinedButton.icon(
            icon: const Icon(AppIcons.add),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () async {
              final clubs = ref.read(clubsProvider);
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
                builder: (_) => FittingSetupDialog(
                  clubs: available,
                  prefs: prefs,
                  draftKey: draftKey,
                ),
              );
              if (result == null || !context.mounted) return;
              ref.read(fittingCaptureProvider.notifier).start(result);
              ref.read(activeClubProvider.notifier).state = available
                  .firstWhere((c) => c.id == result.clubId);
              ref.read(fittingTrialSelectionProvider.notifier).state =
                  result.id;
            },
            label: const Text('New comparison'),
          ),
        ),
      if (review.trialIds.isNotEmpty)
        DropdownButton<String>(
          isExpanded: true,
          icon: const Icon(AppIcons.chevronDown),
          value: review.selected,
          items: [
            for (var i = 0; i < review.trialIds.length; i++)
              DropdownMenuItem(
                value: review.trialIds[i],
                child: Text(
                  'Comparison ${i + 1} · ${review.labels[review.trialIds[i]]}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) =>
              ref.read(fittingTrialSelectionProvider.notifier).state = id,
        ),
      if (recording)
        FittingCaptureControls(
          capture: capture,
          paused: active?.id != capture.clubId,
          onSetup: (candidate) => ref
              .read(fittingCaptureProvider.notifier)
              .select(useCandidate: candidate),
          onPhase: (phase) =>
              ref.read(fittingCaptureProvider.notifier).select(phase: phase),
          onStop: () => ref.read(fittingCaptureProvider.notifier).stop(),
        ),
      if (comparison != null) ...[
        const Divider(height: AppSpacing.l, color: AppColors.border2),
        Semantics(
          liveRegion: true,
          child: Text(comparison.verdict, style: AppTextStyles.body()),
        ),
        if (comparison.context != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '${comparison.context!.goal.name} · ${comparison.context!.intent.name}\n'
              '${comparison.context!.conditions}',
              style: AppTextStyles.label(color: AppColors.textMuted),
            ),
          ),
        FittingEquipmentDetails(
          baseline:
              comparison.baselineSetup ?? (recording ? capture.baseline : null),
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
      ] else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
          child: Text(
            'Start a comparison to record two setups and evaluate them over repeated shots.',
            style: AppTextStyles.body(),
          ),
        ),
      const FittingEvidenceNote(),
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.m),
      itemCount: sections.length,
      itemBuilder: (_, i) => sections[i],
    );
  }
}

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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        paused
            ? 'Paused: select ${capture.clubId} to resume.'
            : 'Recording ${capture.clubId} · ${capture.intent.name}',
        style: AppTextStyles.label(),
      ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final side in [false, true])
            ChoiceChip(
              label: Text(
                '${side ? "B" : "A"}: ${side ? capture.candidate.name : capture.baseline.name}',
              ),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              selected: capture.useCandidate == side,
              onSelected: (_) => onSetup(side),
            ),
        ],
      ),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final phase in FittingPhase.values)
            ChoiceChip(
              label: Text(phase.name),
              selected: capture.phase == phase,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onPhase(phase),
            ),
        ],
      ),
      TextButton(
        onPressed: onStop,
        child: const Text('Stop recording comparison'),
      ),
    ],
  );
}

class FittingEquipmentDetails extends StatelessWidget {
  final EquipmentSetup? baseline;
  final EquipmentSetup? candidate;
  const FittingEquipmentDetails({super.key, this.baseline, this.candidate});
  @override
  Widget build(BuildContext context) => _AppExpansionTile(
    title: Text('Tested equipment', style: AppTextStyles.label()),
    children: [
      for (final entry in [('A', baseline), ('B', candidate)])
        if (entry.$2 != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${entry.$1}: ${entry.$2!.name} · ${entry.$2!.head}\n'
                '${entry.$2!.shaft} · loft ${entry.$2!.loft} · length ${entry.$2!.length}\n${entry.$2!.notes}',
                style: AppTextStyles.body(),
              ),
            ),
          ),
    ],
  );
}

class FittingEvidenceNote extends StatelessWidget {
  const FittingEvidenceNote({super.key});
  @override
  Widget build(BuildContext context) => _AppExpansionTile(
    title: Text('How to interpret the results', style: AppTextStyles.label()),
    children: [
      Text(
        'Launch inputs must be verified device measurements. Flight outcomes are simulated. '
        'The uncertainty range describes shot-to-shot sampling, not device or model accuracy. '
        'A repeated advantage supports comparing these tested setups; it does not prescribe an untested head or shaft.',
        style: AppTextStyles.body(color: AppColors.textMuted),
      ),
    ],
  );
}

/// [ExpansionTile] whose chevron is a Lucide glyph instead of the stock
/// [Icons.expand_more].
///
/// Material glyphs are tree-shaken per release build, and a Shorebird patch
/// ships code only — so a framework default this app never used at release
/// time is missing from the icon font on patched devices and renders as a
/// blank box. Every icon the app draws must therefore come from [AppIcons].
class _AppExpansionTile extends StatefulWidget {
  final Widget title;
  final List<Widget> children;
  const _AppExpansionTile({required this.title, required this.children});

  @override
  State<_AppExpansionTile> createState() => _AppExpansionTileState();
}

class _AppExpansionTileState extends State<_AppExpansionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: widget.title,
    trailing: AnimatedRotation(
      turns: _expanded ? 0.5 : 0,
      duration: kThemeAnimationDuration,
      child: const Icon(AppIcons.chevronDown),
    ),
    onExpansionChanged: (open) => setState(() => _expanded = open),
    children: widget.children,
  );
}
