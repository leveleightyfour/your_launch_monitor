import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/camera_providers.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Desktop-only tab that streams an attached camera into the window.
///
/// The device list comes from whatever the OS enumerates, so any driverless
/// (UVC) camera plugged into the rig shows up alongside a built-in webcam
/// without extra setup.
class CameraTab extends ConsumerStatefulWidget {
  const CameraTab({super.key});

  @override
  ConsumerState<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends ConsumerState<CameraTab> {
  @override
  void initState() {
    super.initState();
    // Enumerating touches provider state, which isn't allowed while this
    // widget is mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(cameraFeedProvider).status == CameraFeedStatus.idle &&
          ref.read(cameraFeedProvider).devices.isEmpty) {
        ref.read(cameraFeedProvider.notifier).refreshDevices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(cameraFeedProvider);

    return Column(
      children: [
        _CameraBar(feed: feed),
        Expanded(child: _CameraBody(feed: feed)),
      ],
    );
  }
}

// ── Toolbar: device picker, refresh, stop ────────────────────────────────────

class _CameraBar extends ConsumerWidget {
  final CameraFeedState feed;

  const _CameraBar({required this.feed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cameraFeedProvider.notifier);
    final canPick = feed.devices.isNotEmpty && !feed.isBusy;

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              enabled: canPick,
              label: feed.selected == null
                  ? 'Select camera'
                  : 'Change camera. Current: ${feed.selected!.name}',
              child: GestureDetector(
                onTap: canPick ? () => _showPicker(context, ref) : null,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.videocam,
                      size: 14,
                      color: feed.status == CameraFeedStatus.streaming
                          ? context.accent
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        feed.selected?.name ?? 'Select camera',
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: canPick ? Colors.white : AppColors.textDimmed,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: canPick
                          ? AppColors.textMuted
                          : AppColors.textDimmed,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (feed.status == CameraFeedStatus.streaming)
            _BarButton(
              icon: Icons.stop_circle_outlined,
              label: 'Stop camera',
              onTap: () => notifier.stop(),
            ),
          _BarButton(
            icon: Icons.refresh,
            label: 'Rescan for cameras',
            onTap: feed.isBusy ? null : () => notifier.refreshDevices(),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Select Camera',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ...feed.devices.map((device) {
            final isSel = device.name == feed.selected?.name;
            return ListTile(
              leading: Icon(
                Icons.videocam,
                size: 18,
                color: isSel ? context.accent : AppColors.textMuted,
              ),
              title: Text(
                device.name,
                style: AppTextStyles.sans(
                  size: 14,
                  weight: isSel ? FontWeight.w600 : FontWeight.w400,
                  color: isSel ? context.accent : Colors.white,
                ),
              ),
              trailing: isSel
                  ? Icon(Icons.check, color: context.accent, size: 18)
                  : null,
              tileColor: Colors.transparent,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                ref.read(cameraFeedProvider.notifier).select(device);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BarButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 32,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? AppColors.textDimmed : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Body: preview, or the reason there isn't one ─────────────────────────────

class _CameraBody extends ConsumerWidget {
  final CameraFeedState feed;

  const _CameraBody({required this.feed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (feed.status) {
      case CameraFeedStatus.listing:
        return const _Busy(message: 'Looking for cameras…');
      case CameraFeedStatus.opening:
        return const _Busy(message: 'Opening camera…');
      case CameraFeedStatus.unsupported:
        return const _Message(
          icon: Icons.videocam_off,
          title: 'Camera not available here',
          detail:
              'The camera feed is wired up for Windows desktop. This platform '
              'has no camera backend built in.',
        );
      case CameraFeedStatus.noDevices:
        return _Message(
          icon: Icons.usb_off,
          title: 'No camera detected',
          detail: 'Plug in a USB camera, then rescan.',
          action: (
            'Rescan',
            () => ref.read(cameraFeedProvider.notifier).refreshDevices(),
          ),
        );
      case CameraFeedStatus.failed:
        return _Message(
          icon: Icons.error_outline,
          title: 'Camera failed to start',
          detail: feed.error ?? 'The device did not respond.',
          action: (
            'Try again',
            () => ref.read(cameraFeedProvider.notifier).refreshDevices(),
          ),
        );
      case CameraFeedStatus.idle:
        return const _Message(
          icon: Icons.videocam,
          title: 'No camera selected',
          detail: 'Pick a camera above to stream it into the window.',
        );
      case CameraFeedStatus.streaming:
        final controller = feed.controller;
        // Belt and braces: streaming without a controller shouldn't happen,
        // but previewing a null/disposed one would take the whole tab down.
        if (controller == null || !controller.value.isInitialized) {
          return const _Busy(message: 'Opening camera…');
        }
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        );
    }
  }
}

class _Busy extends StatelessWidget {
  final String message;

  const _Busy({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTextStyles.sans(size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  /// Optional (label, callback) pair rendered as a button under the text.
  final (String, VoidCallback)? action;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AppColors.textDimmed),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.sans(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTextStyles.sans(size: 11, color: AppColors.textDimmed),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: action!.$2,
                child: Text(
                  action!.$1,
                  style: AppTextStyles.sans(size: 12, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
