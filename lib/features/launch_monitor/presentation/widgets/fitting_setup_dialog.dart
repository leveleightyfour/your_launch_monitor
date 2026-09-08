import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/app_icons.dart';
import '../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../shared/theme.dart';
import '../../../../shared/widgets/app_controls.dart';
import '../../application/fitting_draft_provider.dart';
import '../../domain/entities/club.dart';
import '../../domain/entities/shot_context.dart';
import 'fitting_setup_row.dart';

String _cap(String raw) =>
    raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);

/// Four-step setup for a new comparison. A panel rather than a stock alert:
/// surface ground, hairline edge, caps step counter, one accent action.
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

  static const _titles = [
    'Test conditions',
    'Baseline setup',
    'Candidate setup',
    'Review comparison',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(fittingDraftProvider(draftKey));
    final controller = ref.watch(fittingDraftProvider(draftKey).notifier);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionLabel('Step ${draft.step + 1} of 4'),
                  const SizedBox(height: 4),
                  Text(
                    _titles[draft.step],
                    style: AppTextStyles.sans(
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border),
            Flexible(
              child: SingleChildScrollView(
                key: ValueKey(draft.step),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (draft.step > 0)
                      AppTextAction(
                        icon: AppIcons.chevronLeft,
                        label: 'Previous step',
                        onTap: controller.back,
                      ),
                    if (draft.errors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            'Check the highlighted fields to continue.',
                            style: AppTextStyles.sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: AppColors.severityCritical,
                            ),
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
            const Divider(color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  AppPrimaryButton(
                    label: draft.step == 3 ? 'Start comparison' : 'Continue',
                    onPressed: () {
                      if (draft.step < 3) {
                        controller.next();
                        return;
                      }
                      final capture = controller.complete();
                      if (capture != null) context.pop(capture);
                    },
                  ),
                  const SizedBox(height: 4),
                  AppTextAction(
                    label: 'Cancel comparison',
                    onTap: () => context.pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
        style: AppTextStyles.sans(
          size: 13,
          color: AppColors.textMuted,
        ).copyWith(height: 1.45),
      ),
      const SizedBox(height: 16),
      const AppSectionLabel('Club', trailing: 'required'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in clubs.where((c) => c.id != 'pt'))
            AppChip(
              label: c.shortName,
              color: c.color,
              active: draft.clubId == c.id,
              onTap: () => onClub(c.id),
            ),
        ],
      ),
      if (draft.errors['club'] != null) _FieldError(draft.errors['club']!),
      const SizedBox(height: 16),
      const AppSectionLabel('Shot intent'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, label) in [
            (ShotIntent.stock, 'Stock / full swing'),
            (ShotIntent.partial, 'Partial shot'),
          ])
            AppChip(
              label: label,
              active: draft.intent == i,
              onTap: () => onIntent(i),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const AppSectionLabel('Primary objective'),
      const SizedBox(height: 8),
      for (final (goal, title, subtitle) in const [
        (FittingGoal.carry, 'Carry', 'Protect direction'),
        (FittingGoal.accuracy, 'Accuracy', 'Protect carry'),
        (FittingGoal.approach, 'Approach', 'Target distance and stopping'),
      ])
        AppOptionRow(
          title: title,
          subtitle: subtitle,
          selected: draft.goal == goal,
          onTap: () => onGoal(goal),
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

class _FieldError extends StatelessWidget {
  final String message;
  const _FieldError(this.message);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      message,
      style: AppTextStyles.sans(size: 11, color: AppColors.severityCritical),
    ),
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
        style: AppTextStyles.sans(
          size: 13,
          color: AppColors.textMuted,
        ).copyWith(height: 1.45),
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
    padding: const EdgeInsets.only(top: 14),
    child: AppField(
      fieldKey: ValueKey(field),
      label: label,
      hint: optional ? 'optional' : 'required',
      initialValue: draft.fields[field] ?? '',
      errorText: draft.errors[field],
      numeric: numeric,
      onChanged: (v) => onChanged(field, v),
    ),
  );
}

class FittingReview extends StatelessWidget {
  final FittingDraft draft;
  final UnitPrefs prefs;
  const FittingReview({super.key, required this.draft, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final muted = AppTextStyles.sans(
      size: 12,
      color: AppColors.textMuted,
    ).copyWith(height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionLabel('Test conditions'),
        const SizedBox(height: 4),
        Text(
          '${draft.clubId} · ${_cap(draft.intent.name)} · ${_cap(draft.goal.name)}',
          style: AppTextStyles.sans(size: 13, weight: FontWeight.w600),
        ),
        if ((draft.fields['conditions'] ?? '').isNotEmpty)
          Text(draft.fields['conditions']!, style: muted),
        Text(
          'Lateral corridor ±${draft.fields['tolerance']} ${prefs.distLabel}',
          style: muted,
        ),
        if (draft.goal == FittingGoal.approach)
          Text(
            'Target ${draft.fields['target']} ${prefs.distLabel} · '
            'minimum landing angle ${draft.fields['descent']}°',
            style: muted,
          ),
        const SizedBox(height: 16),
        const AppSectionLabel('Setups'),
        const SizedBox(height: 8),
        for (final side in ['A', 'B'])
          FittingSetupRow(
            tag: side,
            name: draft.fields['name$side'] ?? '',
            details: [
              for (final k in ['head', 'shaft', 'loft', 'length', 'notes'])
                if ((draft.fields['$k$side'] ?? '').isNotEmpty)
                  draft.fields['$k$side']!,
            ],
          ),
        const SizedBox(height: 6),
        Text(
          'Start with A. Alternate in short blocks and keep normal mishits. '
          'Each round needs at least 10 measured shots per setup and three setup switches. '
          'Use fresh shots for the confirmation round.',
          style: AppTextStyles.sans(
            size: 12,
            color: AppColors.textMuted,
          ).copyWith(height: 1.45),
        ),
      ],
    );
  }
}
