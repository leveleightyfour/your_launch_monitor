import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/shared/providers/hole_setup_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Editors for the hole shots are played into — used both in Profile and in a
/// sheet from the 3D flight view, where you actually see what you're changing.
class HoleSetupControls extends ConsumerWidget {
  /// Show the explanatory footnote. Off in the sheet, where space is tight.
  final bool showFootnote;

  const HoleSetupControls({super.key, this.showFootnote = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(unitPrefsProvider);
    final hole = ref.watch(holeSetupProvider);
    final notifier = ref.read(holeSetupProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToggleRow(
          icon: Icons.golf_course,
          label: 'Play to a green',
          value: hole.enabled,
          onChanged: notifier.setEnabled,
        ),
        // The dimensions stay editable with the hole switched off. Hiding them
        // made the whole feature look like it didn't exist.
        HoleNumberRow(
          icon: Icons.flag,
          label: 'Green distance',
          yards: hole.greenDistance,
          prefs: prefs,
          stepDisplay: 5,
          min: HoleSetup.minGreenDistance,
          max: HoleSetup.maxGreenDistance,
          onChanged: notifier.setGreenDistance,
        ),
        HoleNumberRow(
          icon: Icons.swap_horiz,
          label: 'Green width',
          yards: hole.greenWidth,
          prefs: prefs,
          stepDisplay: 2,
          min: HoleSetup.minGreenSize,
          max: HoleSetup.maxGreenSize,
          onChanged: notifier.setGreenWidth,
        ),
        HoleNumberRow(
          icon: Icons.swap_vert,
          label: 'Green depth',
          yards: hole.greenDepth,
          prefs: prefs,
          stepDisplay: 2,
          min: HoleSetup.minGreenSize,
          max: HoleSetup.maxGreenSize,
          onChanged: notifier.setGreenDepth,
        ),
        HoleNumberRow(
          icon: Icons.open_with,
          label: 'Green offset',
          yards: hole.greenOffset,
          prefs: prefs,
          stepDisplay: 2,
          min: -HoleSetup.maxGreenOffset,
          max: HoleSetup.maxGreenOffset,
          signed: true,
          onChanged: notifier.setGreenOffset,
        ),
        HoleNumberRow(
          icon: Icons.straighten,
          label: 'Fairway width',
          yards: hole.fairwayWidth,
          prefs: prefs,
          stepDisplay: 5,
          min: HoleSetup.minFairwayWidth,
          max: HoleSetup.maxFairwayWidth,
          onChanged: notifier.setFairwayWidth,
        ),
        if (showFootnote)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Every shot plays from the tee. Where the ball lands decides how '
              'it releases — a green checks, rough stops it dead.',
              style: AppTextStyles.sans(size: 12, color: AppColors.textDimmed),
            ),
          ),
      ],
    );
  }
}

/// Opens the hole editor over the current screen.
Future<void> showHoleSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Hole',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Flexible(
              child: SingleChildScrollView(
                child: HoleSetupControls(showFootnote: false),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Rows ─────────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTextStyles.sans(size: 14))),
          for (var i = 0; i < 2; i++)
            GestureDetector(
              onTap: () => onChanged(i == 1),
              child: Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: (i == 1) == value
                      ? context.accentSubtle
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (i == 1) == value
                        ? context.accent
                        : AppColors.border2,
                  ),
                ),
                child: Text(
                  i == 0 ? 'Off' : 'On',
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: (i == 1) == value
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: (i == 1) == value
                        ? context.accent
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A distance setting the user steps up and down. Values are stored in yards
/// and shown in whatever unit they've chosen.
class HoleNumberRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double yards;
  final UnitPrefs prefs;

  /// Step size in the *display* unit, so the numbers stay round either way.
  final double stepDisplay;
  final double min;
  final double max;

  /// Show an explicit side rather than a sign — for the green offset.
  final bool signed;
  final ValueChanged<double> onChanged;

  const HoleNumberRow({
    super.key,
    required this.icon,
    required this.label,
    required this.yards,
    required this.prefs,
    required this.stepDisplay,
    required this.min,
    required this.max,
    required this.onChanged,
    this.signed = false,
  });

  String get _text {
    final value = prefs.dist(yards);
    if (!signed) return '${value.round()} ${prefs.distLabel}';
    if (value.abs() < 0.5) return 'Centre';
    return '${value.abs().round()} ${prefs.distLabel} ${value < 0 ? 'L' : 'R'}';
  }

  void _step(double direction) {
    final next = prefs.toYards(prefs.dist(yards) + stepDisplay * direction);
    onChanged(next.clamp(min, max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTextStyles.sans(size: 14))),
          _StepButton(icon: Icons.remove, onTap: () => _step(-1)),
          Container(
            constraints: const BoxConstraints(minWidth: 78),
            alignment: Alignment.center,
            child: Text(_text, style: AppTextStyles.mono(size: 13)),
          ),
          _StepButton(icon: Icons.add, onTap: () => _step(1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border2),
        ),
        child: Icon(icon, size: 15, color: context.accent),
      ),
    );
  }
}
