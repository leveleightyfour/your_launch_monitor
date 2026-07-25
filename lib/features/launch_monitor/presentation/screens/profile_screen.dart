import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'package:omni_sniffer/shared/app_version.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/hole_setup_controls.dart';
import 'package:omni_sniffer/shared/providers/accent_color_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/services/protocol_capture_export.dart';
import 'package:omni_sniffer/shared/theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(unitPrefsProvider);
    final notifier = ref.read(unitPrefsProvider.notifier);
    final accent = ref.watch(accentColorProvider);
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
            const HoleSetupControls(),
            const SizedBox(height: 16),
            _SectionHeader('Support'),
            _SettingsRow(
              icon: Icons.help,
              label: 'Help & support',
              onTap: () {},
            ),
            _SettingsRow(icon: Icons.info, label: 'About', onTap: () {}),
            Builder(
              builder: (context) => _SettingsRow(
                icon: Icons.bug_report,
                label: 'Export protocol capture',
                onTap: () => ProtocolCaptureExport.share(context),
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: _VersionLabel()),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// "Version 1.0.16+17 · Patch 4" — patch number comes from the Shorebird
/// updater when running a patched release build; plain version otherwise
/// (debug builds / unpatched installs).
class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  static Future<int?> _currentPatch() async {
    try {
      final updater = ShorebirdUpdater();
      if (!updater.isAvailable) return null;
      return (await updater.readCurrentPatch())?.number;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: _currentPatch(),
      builder: (context, snap) {
        final patch = snap.data;
        return Text(
          patch != null
              ? 'Version $appVersion · Patch $patch'
              : 'Version $appVersion',
          style: AppTextStyles.sans(size: 11, color: AppColors.textDimmed),
        );
      },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — mirrors the other Preferences rows visually.
          Row(
            children: [
              const Icon(Icons.palette, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Text('Accent colour', style: AppTextStyles.sans(size: 14)),
            ],
          ),
          const SizedBox(height: 10),
          // Swatches wrap to the next line when they don't all fit on one
          // (e.g. narrow iPhone widths).
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: appAccentSwatches.map((swatch) {
                final isSelected =
                    swatch.color.toARGB32() == current.toARGB32();
                return GestureDetector(
                  onTap: () => onSelect(swatch.color),
                  child: Container(
                    width: 25,
                    height: 25,
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
