import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/app_icons.dart';
import '../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../shared/theme.dart';
import '../../application/fitting_draft_provider.dart';
import '../../domain/entities/club.dart';
import '../../domain/entities/shot_context.dart';

class FittingSetupDialog extends ConsumerWidget {
  final List<Club> clubs;
  final UnitPrefs prefs;
  final FittingDraftKey draftKey;
  const FittingSetupDialog({
    super.key,
    required this.clubs,
    required this.prefs,
    required this.draftKey,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(fittingDraftProvider(draftKey));
    final controller = ref.watch(fittingDraftProvider(draftKey).notifier);
    final titles = [
      'Test conditions',
      'Baseline setup',
      'Candidate setup',
      'Review comparison',
    ];
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${draft.step + 1} of 4',
            style: AppTextStyles.caption(color: AppColors.textMuted),
          ),
          Text(titles[draft.step], style: AppTextStyles.subHeading()),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          key: ValueKey(draft.step),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (draft.step > 0)
                TextButton.icon(
                  onPressed: controller.back,
                  icon: const Icon(AppIcons.back),
                  label: const Text('Previous step'),
                ),
              if (draft.errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Check the highlighted fields to continue.',
                      style: AppTextStyles.label(color: AppColors.errorText),
                    ),
                  ),
                ),
              if (draft.step == 0)
                FittingConditionsForm(
                  clubs: clubs,
                  prefs: prefs,
                  draft: draft,
                  onClub: controller.club,
                  onIntent: controller.intent,
                  onGoal: controller.goal,
                  onField: controller.field,
                )
              else if (draft.step < 3)
                FittingEquipmentForm(
                  side: draft.step == 1 ? 'A' : 'B',
                  draft: draft,
                  onField: controller.field,
                )
              else
                FittingReview(draft: draft, prefs: prefs),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.start,
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () {
              if (draft.step < 3) {
                controller.next();
                return;
              }
              final capture = controller.complete();
              if (capture != null) context.pop(capture);
            },
            child: Text(draft.step == 3 ? 'Start comparison' : 'Continue'),
          ),
        ),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel comparison'),
        ),
      ],
    );
  }
}

class FittingConditionsForm extends StatelessWidget {
  final List<Club> clubs;
  final UnitPrefs prefs;
  final FittingDraft draft;
  final ValueChanged<String> onClub;
  final ValueChanged<ShotIntent> onIntent;
  final ValueChanged<FittingGoal> onGoal;
  final void Function(String, String) onField;
  const FittingConditionsForm({
    super.key,
    required this.clubs,
    required this.prefs,
    required this.draft,
    required this.onClub,
    required this.onIntent,
    required this.onGoal,
    required this.onField,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Keep the ball, lie and environment the same for both setups.',
        style: AppTextStyles.body(),
      ),
      const SizedBox(height: AppSpacing.s),
      DropdownButtonFormField<String>(
        initialValue: draft.clubId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Club (required)',
          errorText: draft.errors['club'],
        ),
        items: [
          for (final c in clubs.where((c) => c.id != 'pt'))
            DropdownMenuItem(value: c.id, child: Text(c.shortName)),
        ],
        onChanged: (v) {
          if (v != null) onClub(v);
        },
      ),
      const SizedBox(height: AppSpacing.s),
      Text('Shot intent', style: AppTextStyles.label()),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final i in [ShotIntent.stock, ShotIntent.partial])
            ChoiceChip(
              label: Text(
                i == ShotIntent.stock ? 'Stock / full swing' : 'Partial shot',
              ),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              selected: draft.intent == i,
              onSelected: (_) => onIntent(i),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.s),
      Text('Primary objective', style: AppTextStyles.label()),
      RadioGroup<FittingGoal>(
        groupValue: draft.goal,
        onChanged: (v) {
          if (v != null) onGoal(v);
        },
        child: Column(
          children: const [
            RadioListTile(
              value: FittingGoal.carry,
              title: Text('Carry'),
              subtitle: Text('Protect direction'),
            ),
            RadioListTile(
              value: FittingGoal.accuracy,
              title: Text('Accuracy'),
              subtitle: Text('Protect carry'),
            ),
            RadioListTile(
              value: FittingGoal.approach,
              title: Text('Approach'),
              subtitle: Text('Target distance and stopping'),
            ),
          ],
        ),
      ),
      if (draft.goal == FittingGoal.approach) ...[
        FittingTextField(
          field: 'target',
          label: 'Target carry (${prefs.distLabel})',
          draft: draft,
          onChanged: onField,
          numeric: true,
        ),
        FittingTextField(
          field: 'descent',
          label: 'Minimum landing angle (°)',
          draft: draft,
          onChanged: onField,
          numeric: true,
        ),
      ],
      FittingTextField(
        field: 'tolerance',
        label: 'Lateral corridor ± (${prefs.distLabel})',
        draft: draft,
        onChanged: onField,
        numeric: true,
      ),
      FittingTextField(
        field: 'conditions',
        label: 'Ball, lie / tee and environment',
        draft: draft,
        onChanged: onField,
      ),
    ],
  );
}

class FittingEquipmentForm extends StatelessWidget {
  final String side;
  final FittingDraft draft;
  final void Function(String, String) onField;
  const FittingEquipmentForm({
    super.key,
    required this.side,
    required this.draft,
    required this.onField,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Record the equipment as tested, including the units for length.',
        style: AppTextStyles.body(),
      ),
      for (final f in const [
        ('name', 'Setup name'),
        ('head', 'Head / model'),
        ('shaft', 'Shaft / weight / flex'),
        ('loft', 'Loft / adapter setting'),
        ('length', 'Playing length'),
        ('notes', 'Lie, swingweight, grip and feel'),
      ])
        FittingTextField(
          key: ValueKey('${f.$1}$side'),
          field: '${f.$1}$side',
          label: f.$2,
          draft: draft,
          onChanged: onField,
          optional: f.$1 == 'notes',
        ),
    ],
  );
}

class FittingTextField extends StatelessWidget {
  final String field;
  final String label;
  final FittingDraft draft;
  final void Function(String, String) onChanged;
  final bool optional;
  final bool numeric;
  const FittingTextField({
    super.key,
    required this.field,
    required this.label,
    required this.draft,
    required this.onChanged,
    this.optional = false,
    this.numeric = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.s),
    child: TextFormField(
      key: ValueKey(field),
      initialValue: draft.fields[field] ?? '',
      style: AppTextStyles.body(),
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textInputAction: TextInputAction.next,
      onChanged: (v) => onChanged(field, v),
      decoration: InputDecoration(
        labelText: '$label (${optional ? "optional" : "required"})',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorText: draft.errors[field],
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.textDimmed),
        ),
      ),
    ),
  );
}

class FittingReview extends StatelessWidget {
  final FittingDraft draft;
  final UnitPrefs prefs;
  const FittingReview({super.key, required this.draft, required this.prefs});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${draft.clubId} · ${draft.intent.name} · ${draft.goal.name}',
        style: AppTextStyles.body(),
      ),
      Text(
        draft.fields['conditions'] ?? '',
        style: AppTextStyles.label(color: AppColors.textMuted),
      ),
      Text(
        'Lateral corridor: ±${draft.fields['tolerance']} ${prefs.distLabel}',
        style: AppTextStyles.label(),
      ),
      if (draft.goal == FittingGoal.approach)
        Text(
          'Target: ${draft.fields['target']} ${prefs.distLabel} · '
          'Minimum landing angle: ${draft.fields['descent']}°',
          style: AppTextStyles.label(),
        ),
      for (final side in ['A', 'B'])
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$side: ${draft.fields['name$side']}',
                style: AppTextStyles.subHeading(),
              ),
              Text(
                ['head', 'shaft', 'loft', 'length', 'notes']
                    .map((k) => draft.fields['$k$side'] ?? '')
                    .where((v) => v.isNotEmpty)
                    .join('\n'),
                style: AppTextStyles.body(),
              ),
            ],
          ),
        ),
      const SizedBox(height: AppSpacing.s),
      Text(
        'Start with A. Alternate in short blocks and keep normal mishits. '
        'Each round needs at least 10 measured shots per setup and three setup switches. '
        'Use fresh shots for the confirmation round.',
        style: AppTextStyles.body(),
      ),
    ],
  );
}
