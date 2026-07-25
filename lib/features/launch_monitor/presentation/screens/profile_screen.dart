import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/shared/providers/accent_color_provider.dart';
import 'package:omni_sniffer/shared/providers/hole_setup_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(unitPrefsProvider);
    final notifier = ref.read(unitPrefsProvider.notifier);
    final accent = ref.watch(accentColorProvider);
    final hole = ref.watch(holeSetupProvider);
    final holeNotifier = ref.read(holeSetupProvider.notifier);
    final accentNotifier = ref.read(accentColorProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Profile',
              style: AppTextStyles.sans(size: 20, weight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            // Avatar + name
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border2, width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person,
                        size: 36,
                        color: AppColors.textDimmed,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Player',
                    style: AppTextStyles.sans(
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Member since 2025',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () {},
                    child: Text(
                      'Edit profile',
                      style: AppTextStyles.sans(size: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Divider(color: AppColors.border),
            const SizedBox(height: 8),
            _SectionHeader('Account'),
            _SettingsRow(
              icon: Icons.bluetooth,
              label: 'My devices',
              onTap: () {},
            ),
            _SettingsRow(
              icon: Icons.lock,
              label: 'Change password',
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _SectionHeader('Preferences'),
            _UnitToggleRow(
              icon: Icons.straighten,
              label: 'Distance',
              options: const ['m', 'yds'],
              selected: prefs.distance == DistanceUnit.meters ? 0 : 1,
              onSelect: (i) => notifier.setDistance(
                i == 0 ? DistanceUnit.meters : DistanceUnit.yards,
              ),
            ),
            _UnitToggleRow(
              icon: Icons.speed,
              label: 'Speed',
              options: const ['mph', 'km/h'],
              selected: prefs.speed == SpeedUnit.mph ? 0 : 1,
              onSelect: (i) =>
                  notifier.setSpeed(i == 0 ? SpeedUnit.mph : SpeedUnit.kmh),
            ),
            _UnitToggleRow(
              icon: Icons.scatter_plot,
              label: 'Dispersion',
              options: const ['Trackman', 'PGA'],
              selected: prefs.dispersionStandard == DispersionStandard.trackman
                  ? 0
                  : 1,
              onSelect: (i) => notifier.setDispersionStandard(
                i == 0 ? DispersionStandard.trackman : DispersionStandard.pga,
              ),
            ),
            _UnitToggleRow(
              icon: Icons.autorenew,
              label: 'Auto-reconnect',
              options: const ['Off', 'On'],
              selected: prefs.autoReconnect ? 1 : 0,
              onSelect: (i) => notifier.setAutoReconnect(i == 1),
            ),
            _AccentPickerRow(
              current: accent,
              onSelect: accentNotifier.setAccent,
            ),
            const SizedBox(height: 16),
            _SectionHeader('Target'),
            _UnitToggleRow(
              icon: Icons.golf_course,
              label: 'Play to a green',
              options: const ['Off', 'On'],
              selected: hole.enabled ? 1 : 0,
              onSelect: (i) => holeNotifier.setEnabled(i == 1),
            ),
            if (hole.enabled) ...[
              _NumberRow(
                icon: Icons.flag,
                label: 'Green distance',
                yards: hole.greenDistance,
                prefs: prefs,
                stepDisplay: 5,
                min: HoleSetup.minGreenDistance,
                max: HoleSetup.maxGreenDistance,
                onChanged: holeNotifier.setGreenDistance,
              ),
              _NumberRow(
                icon: Icons.swap_horiz,
                label: 'Green width',
                yards: hole.greenWidth,
                prefs: prefs,
                stepDisplay: 2,
                min: HoleSetup.minGreenSize,
                max: HoleSetup.maxGreenSize,
                onChanged: holeNotifier.setGreenWidth,
              ),
              _NumberRow(
                icon: Icons.swap_vert,
                label: 'Green depth',
                yards: hole.greenDepth,
                prefs: prefs,
                stepDisplay: 2,
                min: HoleSetup.minGreenSize,
                max: HoleSetup.maxGreenSize,
                onChanged: holeNotifier.setGreenDepth,
              ),
              _NumberRow(
                icon: Icons.open_with,
                label: 'Green offset',
                yards: hole.greenOffset,
                prefs: prefs,
                stepDisplay: 2,
                min: -HoleSetup.maxGreenOffset,
                max: HoleSetup.maxGreenOffset,
                signed: true,
                onChanged: holeNotifier.setGreenOffset,
              ),
              _NumberRow(
                icon: Icons.straighten,
                label: 'Fairway width',
                yards: hole.fairwayWidth,
                prefs: prefs,
                stepDisplay: 5,
                min: HoleSetup.minFairwayWidth,
                max: HoleSetup.maxFairwayWidth,
                onChanged: holeNotifier.setFairwayWidth,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Every shot plays from the tee. Where the ball lands decides '
                  'how it releases — a green checks, rough stops it dead.',
                  style: AppTextStyles.sans(
                    size: 12,
                    color: AppColors.textDimmed,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _SectionHeader('Support'),
            _SettingsRow(
              icon: Icons.help,
              label: 'Help & support',
              onTap: () {},
            ),
            _SettingsRow(icon: Icons.info, label: 'About', onTap: () {}),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: AppTextStyles.sans(
          size: 10,
          weight: FontWeight.w600,
          color: AppColors.textDimmed,
        ),
      ),
    );
  }
}

class _UnitToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;

  const _UnitToggleRow({
    required this.icon,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < options.length; i++)
                GestureDetector(
                  onTap: () => onSelect(i),
                  child: Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: i == selected
                          ? context.accentSubtle
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: i == selected
                            ? context.accent
                            : AppColors.border2,
                      ),
                    ),
                    child: Text(
                      options[i],
                      style: AppTextStyles.sans(
                        size: 12,
                        weight: i == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: i == selected
                            ? context.accent
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stepped number row ────────────────────────────────────────────────────────

/// A distance setting the user steps up and down. Values are stored in yards
/// and shown in whatever unit they've chosen.
class _NumberRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double yards;
  final UnitPrefs prefs;

  /// Step size in the *display* unit, so the numbers stay round either way.
  final double stepDisplay;
  final double min;
  final double max;

  /// Show an explicit sign and an L/R suffix — for the green offset.
  final bool signed;
  final ValueChanged<double> onChanged;

  const _NumberRow({
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
    return '${value.abs().round()} ${prefs.distLabel} '
        '${value < 0 ? 'L' : 'R'}';
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

// ── Accent colour picker ──────────────────────────────────────────────────────

class _AccentPickerRow extends StatelessWidget {
  final Color current;
  final ValueChanged<Color> onSelect;

  const _AccentPickerRow({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.palette, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Accent colour', style: AppTextStyles.sans(size: 14)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: appAccentSwatches.map((swatch) {
              final isSelected = swatch.color.toARGB32() == current.toARGB32();
              return GestureDetector(
                onTap: () => onSelect(swatch.color),
                child: Container(
                  width: 25,
                  height: 25,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: swatch.color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 11, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTextStyles.sans(size: 14))),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textDimmed,
            ),
          ],
        ),
      ),
    );
  }
}
