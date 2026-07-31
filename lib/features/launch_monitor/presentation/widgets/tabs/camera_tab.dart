import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/camera_providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/impact_clip_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';
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

  /// The clip being scrubbed, or null while the live feed is showing.
  ImpactClip? _reviewing;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(cameraFeedProvider);
    final capture = ref.watch(impactClipProvider);
    final reviewing = _reviewing;

    return Column(
      children: [
        _CameraBar(feed: feed),
        Expanded(
          child: reviewing == null
              ? _CameraBody(feed: feed)
              : _ClipReview(clip: reviewing),
        ),
        if (capture.armed || capture.clips.isNotEmpty)
          _CaptureBar(
            capture: capture,
            reviewing: reviewing,
            onReview: (clip) => setState(() => _reviewing = clip),
            onBackToLive: () => setState(() => _reviewing = null),
          ),
      ],
    );
  }
}

// ── Capture status / review switch ───────────────────────────────────────────

class _CaptureBar extends StatelessWidget {
  final ImpactClipState capture;
  final ImpactClip? reviewing;
  final ValueChanged<ImpactClip> onReview;
  final VoidCallback onBackToLive;

  const _CaptureBar({
    required this.capture,
    required this.reviewing,
    required this.onReview,
    required this.onBackToLive,
  });

  @override
  Widget build(BuildContext context) {
    final latest = capture.latest;
    final (Color dot, String label) = capture.capturing
        ? (AppColors.severityWarning, 'Capturing the post-roll…')
        : capture.armed
        ? (context.accent, '${capture.bufferedFrames} frames buffered')
        : (AppColors.textDimmed, 'Not buffering');

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.sans(size: 12, color: AppColors.textMuted),
            ),
          ),
          const Spacer(),
          if (latest != null) ...[
            Flexible(
              child: Text(
                _clipSummary(latest),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTextStyles.sans(
                  size: 12,
                  color: AppColors.textDimmed,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _PillButton(
              label: reviewing == null ? 'Review' : 'Back to live',
              onTap: reviewing == null
                  ? () => onReview(latest)
                  : onBackToLive,
            ),
          ],
        ],
      ),
    );
  }

  static String _clipSummary(ImpactClip clip) =>
      'Shot ${clip.shotIndex + 1} · ${clip.frameCount} frames · '
      '${clip.effectiveFps.toStringAsFixed(0)} fps';
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.accentSubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.accentBorder),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.sans(
                size: 12,
                weight: FontWeight.w700,
                color: context.accent,
              ),
            ),
          ),
        ),
      ),
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
                        feed.selected == null
                            ? 'Select camera'
                            : _deviceLabel(feed.selected!),
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
            // Probing reopens every index, which would fight the live
            // capture, so a rescan means stopping first.
            onTap: feed.isBusy || feed.status == CameraFeedStatus.streaming
                ? null
                : () => notifier.refreshDevices(),
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
                _deviceLabel(device),
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
          detail: feed.selected == null
              ? (feed.error ?? 'The device did not respond.')
              : '${feed.selected!.name}\n'
                    '${feed.error ?? 'The device did not respond.'}',
          hint: _failureHint(feed.error),
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
        final frames = feed.frames;
        // Belt and braces: streaming without a frame source shouldn't
        // happen, and rendering null would take the whole tab down.
        if (frames == null) return const _Busy(message: 'Opening camera…');
        return _LiveView(frames: frames);
    }
  }
}

/// Device name plus its native size, so two identical webcams are still
/// tellable apart and it is obvious what the feed is actually running at.
String _deviceLabel(CameraDevice device) {
  final resolution = device.resolutionLabel;
  return resolution.isEmpty ? device.name : '${device.name}  ·  $resolution';
}

/// What to try next. A bare driver error is useless to the golfer, and the
/// wrong advice is worse than none, so the sentence is picked from the error
/// text. Matching on a message is loose by nature; it chooses which hint to
/// show, never what the code does.
String _failureHint(String? error) {
  final text = (error ?? '').toLowerCase();
  if (text.contains('native function') || text.contains('symbol')) {
    // Build-time, not runtime: dartcv leaves videoio out of the native
    // library unless pubspec asks for it, and the Dart bindings compile
    // either way.
    return 'The OpenCV build is missing its videoio module. Check the '
        'hooks/user_defines block in pubspec.yaml lists videoio, then '
        'rebuild.';
  }
  if (text.contains('holding') || text.contains('refused to open')) {
    return 'Close anything else using the camera — Teams, Zoom, OBS or the '
        'Windows Camera app will each hold it exclusively.';
  }
  if (text.contains('stopped sending')) {
    return 'The camera went quiet mid-session. If it was unplugged, plug it '
        'back in and rescan.';
  }
  return 'Check the camera still appears in the Windows Camera app, and that '
      'no other app is holding it.';
}

/// The live feed. Listens to frames directly rather than going through the
/// provider, so a new frame repaints this image and nothing else — the tab's
/// chrome does not rebuild thirty times a second.
class _LiveView extends StatelessWidget {
  final ValueListenable<ui.Image?> frames;

  const _LiveView({required this.frames});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: frames,
        builder: (context, image, _) {
          if (image == null) {
            return const _Busy(message: 'Waiting for the first frame…');
          }
          return Center(
            child: AspectRatio(
              aspectRatio: image.width / image.height,
              child: RawImage(image: image, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
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

  /// Optional third line, dimmer than [detail] — what to try next when the
  /// detail is a platform error the golfer can't act on directly.
  final String? hint;

  /// Optional (label, callback) pair rendered as a button under the text.
  final (String, VoidCallback)? action;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.hint,
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
              style: AppTextStyles.sans(
                size: 12,
                color: AppColors.textDimmed,
              ).copyWith(height: 1.4),
            ),
            if (hint != null) ...[
              const SizedBox(height: 10),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: AppTextStyles.sans(
                  size: 11,
                  color: AppColors.textDimmed,
                ).copyWith(height: 1.4),
              ),
            ],
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

// ── Clip review ──────────────────────────────────────────────────────────────

/// Frame-by-frame scrub through one captured clip.
///
/// A scrubber rather than a player because that is what the clip is for: the
/// interesting part of a golf swing is a handful of frames wide, and stepping
/// through them beats watching six seconds play at speed.
class _ClipReview extends StatefulWidget {
  final ImpactClip clip;

  const _ClipReview({required this.clip});

  @override
  State<_ClipReview> createState() => _ClipReviewState();
}

class _ClipReviewState extends State<_ClipReview> {
  late int _index = widget.clip.triggerIndex;

  @override
  void didUpdateWidget(_ClipReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A newer shot replaced the clip under us; start at its own marker
    // rather than holding a frame number that meant something else.
    if (!identical(oldWidget.clip, widget.clip)) {
      _index = widget.clip.triggerIndex;
    }
  }

  void _step(int delta) {
    setState(
      () => _index = (_index + delta).clamp(0, widget.clip.frameCount - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip.isEmpty) {
      return const _Message(
        icon: Icons.videocam_off,
        title: 'Empty clip',
        detail: 'No frames were buffered for this shot.',
      );
    }

    final index = _index.clamp(0, clip.frameCount - 1);
    final atTrigger = index == clip.triggerIndex;

    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              // gaplessPlayback keeps the previous frame on screen while the
              // next decodes, so scrubbing doesn't strobe through white.
              child: Image.memory(
                clip.frames[index].jpeg,
                gaplessPlayback: true,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
            color: AppColors.surface,
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  _BarButton(
                    icon: Icons.chevron_left,
                    label: 'Previous frame',
                    onTap: index > 0 ? () => _step(-1) : null,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: context.accent,
                        inactiveTrackColor: AppColors.border2,
                        thumbColor: context.accent,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        value: index.toDouble(),
                        min: 0,
                        max: (clip.frameCount - 1).toDouble(),
                        divisions: clip.frameCount > 1
                            ? clip.frameCount - 1
                            : null,
                        label: 'Frame ${index + 1}',
                        onChanged: (v) => setState(() => _index = v.round()),
                      ),
                    ),
                  ),
                  _BarButton(
                    icon: Icons.chevron_right,
                    label: 'Next frame',
                    onTap: index < clip.frameCount - 1
                        ? () => _step(1)
                        : null,
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'FRAME ${index + 1} / ${clip.frameCount}',
                    style: AppTextStyles.statLabel(),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    _signedSeconds(clip.offsetFromTrigger(index)),
                    style: AppTextStyles.statValue(
                      size: 14,
                      color: atTrigger
                          ? AppColors.severityWarning
                          : Colors.white,
                    ),
                  ),
                  const Spacer(),
                  _PillButton(
                    label: 'Jump to packet',
                    onTap: () =>
                        setState(() => _index = clip.triggerIndex),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Zero is when the launch monitor reported the shot, not the '
                'strike — impact is a little earlier, by however long the '
                'reading took to reach us.',
                style: AppTextStyles.sans(
                  size: 11,
                  color: AppColors.textDimmed,
                ).copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `-0.433 s`, `+0.100 s`, `0.000 s`. Milliseconds matter here — at 30fps
  /// one frame is 33ms, and the whole event of interest is a few frames.
  static String _signedSeconds(Duration offset) {
    final seconds = offset.inMicroseconds / Duration.microsecondsPerSecond;
    final sign = seconds > 0 ? '+' : '';
    return '$sign${seconds.toStringAsFixed(3)} s';
  }
}
