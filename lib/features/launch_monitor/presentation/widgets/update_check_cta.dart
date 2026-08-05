import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/shared/providers/shorebird_update_provider.dart';
import 'package:omni_sniffer/shared/services/shorebird_update_service.dart';
import 'package:omni_sniffer/shared/theme.dart';
import 'package:omni_sniffer/shared/app_icons.dart';

/// Home-screen Shorebird update control: manual check, download progress, and
/// a restart prompt once a patch is ready. Renders nothing where OTA patching
/// isn't possible — a check button that can only no-op is clutter.
class UpdateCheckCta extends ConsumerWidget {
  const UpdateCheckCta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(shorebirdUpdateProvider);
    if (!service.isAvailable) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        switch (service.phase) {
          case UpdatePhase.checking:
            return const _Progress('Checking for updates…');
          case UpdatePhase.downloading:
            return const _Progress('Downloading update…');
          case UpdatePhase.readyToRestart:
            final n = service.nextPatchNumber;
            final verb = service.quitOnlyRestart ? 'Quit' : 'Restart';
            return _Chip(
              icon: AppIcons.appUpdate,
              label: n != null ? '$verb to update ($n)' : '$verb to update',
              color: context.accent,
              onTap: () => _confirmRestart(context, service),
            );
          case UpdatePhase.idle:
          case UpdatePhase.failed:
            return _Chip(
              icon: AppIcons.refresh,
              label: service.phase == UpdatePhase.failed
                  ? 'Check failed — retry'
                  : 'Check for updates',
              color: AppColors.textMuted,
              onTap: service.checkNow,
            );
        }
      },
    );
  }

  Future<void> _confirmRestart(
    BuildContext context,
    ShorebirdUpdateService service,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Update ready',
          style: AppTextStyles.sans(size: 17, weight: FontWeight.w600),
        ),
        content: Text(
          service.quitOnlyRestart
              ? 'The app will close. Reopen it to finish applying the update.'
              : 'The app will restart to apply the update. Continue?',
          style: AppTextStyles.sans(size: 13, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Later',
              style: AppTextStyles.sans(color: AppColors.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              service.quitOnlyRestart ? 'Quit now' : 'Restart now',
              style: AppTextStyles.sans(
                weight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await service.restartToUpdate();
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.sans(size: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final String label;

  const _Progress(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.sans(size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
