import 'package:flutter/material.dart';
import 'package:omni_sniffer/shared/theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            _SectionHeader('Support'),
            _SettingsRow(
              icon: Icons.help,
              label: 'Help & support',
              onTap: () {},
            ),
            _SettingsRow(
              icon: Icons.info,
              label: 'About',
              onTap: () {},
            ),
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
            Expanded(
              child: Text(label, style: AppTextStyles.sans(size: 14)),
            ),
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
