import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/camera_providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/impact_clip_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/services/clip_export_service.dart';
import 'package:omni_sniffer/shared/services/event_loop_watchdog.dart';
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
  void dispose() {
    // The provider outlives this widget, so a paused preview would stay
    // paused for the next visit to the tab.
    if (_reviewing != null) {
      ref.read(cameraFeedProvider.notifier).setPreviewPaused(false);
    }
    super.dispose();
  }

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
            onReview: (clip) {
              // Logged at the tap, before any widget builds: if this appears
              // and "[review] opening" does not, the fault is in the switch
              // to the review widget rather than anywhere inside it.
              debugPrint('[review] tapped, shot ${clip.shotIndex + 1}');
              ref.read(cameraFeedProvider.notifier).setPreviewPaused(true);
              setState(() => _reviewing = clip);
            },
            onBackToLive: () {
              ref.read(cameraFeedProvider.notifier).setPreviewPaused(false);
              setState(() => _reviewing = null);
            },
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

  /// Drawn in the accent by default. Muted marks the off state of a group
  /// where one member is chosen at a time.
  final bool muted;

  /// Announced as a selected control when it belongs to such a group.
  final bool? selected;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.muted = false,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: muted ? AppColors.card : context.accentSubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: muted ? AppColors.border2 : context.accentBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.sans(
                size: 12,
                weight: FontWeight.w700,
                color: muted ? AppColors.textMuted : context.accent,
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
          if (feed.status == CameraFeedStatus.streaming) ...[
            _BarButton(
              icon: Icons.aspect_ratio,
              label: 'Capture resolution',
              onTap: () => _showModePicker(context, ref),
            ),
            _BarButton(
              icon: Icons.stop_circle_outlined,
              label: 'Stop camera',
              onTap: () => notifier.stop(),
            ),
          ],
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

void _showModePicker(BuildContext context, WidgetRef ref) {
  final prefs = ref.read(unitPrefsProvider);
  final current = CaptureMode(prefs.cameraWidth, prefs.cameraHeight);
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text(
                'Capture Resolution',
                style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'A camera that cannot manage the size you pick gives its nearest '
            'mode instead. Larger frames cost frame rate and memory per clip.',
            style: AppTextStyles.sans(
              size: 11,
              color: AppColors.textDimmed,
            ).copyWith(height: 1.35),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        ...CaptureMode.candidates.map((mode) {
          final isSel = mode == current;
          return ListTile(
            leading: Icon(
              mode.isAuto ? Icons.auto_awesome : Icons.aspect_ratio,
              size: 18,
              color: isSel ? context.accent : AppColors.textMuted,
            ),
            title: Text(
              mode.label,
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
              ref.read(cameraFeedProvider.notifier).setMode(mode);
            },
          );
        }),
        const SizedBox(height: 8),
      ],
    ),
  );
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

class _ClipReviewState extends State<_ClipReview>
    with SingleTickerProviderStateMixin {
  /// Loop rates offered. Quarter speed is the slowest worth having at 30fps —
  /// below that the gaps between frames read as a slideshow rather than
  /// slow motion, and stepping is the better tool.
  static const _speeds = [1.0, 0.5, 0.25];

  late int _index = widget.clip.triggerIndex;

  /// Playback rate, or null when paused.
  double? _speed;

  /// The decoded frame on screen.
  ///
  /// Decoded here rather than with `Image.memory`, which was what wedged the
  /// UI: every rebuild built a fresh MemoryImage, so playback pushed thirty
  /// distinct decodes a second through Flutter's image cache and evicted the
  /// cache continuously. Owning the decode means one at a time, no cache, and
  /// explicit disposal.
  ui.Image? _shown;

  /// Index waiting to be decoded. Overwritten rather than queued: if decoding
  /// falls behind the loop, the right behaviour is to skip to the newest
  /// frame, not to work through a backlog and drift further behind.
  int? _pending;
  bool _decoding = false;

  late final _ticker = createTicker(_onTick);

  final _watchdog = EventLoopWatchdog('review');

  /// Where in the clip playback resumed from. The ticker's own elapsed time
  /// restarts at zero each time it starts, so the offset it is measured
  /// against has to be remembered separately — otherwise changing speed
  /// would fling the playhead back to wherever the last run began.
  Duration _clipAnchor = Duration.zero;

  @override
  void initState() {
    super.initState();
    final clip = widget.clip;
    debugPrint(
      '[review] opening shot ${clip.shotIndex + 1}: ${clip.frameCount} frames, '
      '${(clip.byteSize / (1024 * 1024)).toStringAsFixed(1)}MB, '
      'starting at ${clip.triggerIndex}',
    );
    final first = Stopwatch()..start();
    _requestFrame(_index);
    // Reported separately from the rolling figures: if the freeze happens on
    // the way in rather than during playback, this is the line that shows it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        '[review] first frame on screen after ${first.elapsedMilliseconds}ms',
      );
    });
  }

  @override
  void dispose() {
    _watchdog.stop();
    _ticker.dispose();
    _shown?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ClipReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A newer shot replaced the clip under us; start at its own marker
    // rather than holding a frame number that meant something else.
    if (!identical(oldWidget.clip, widget.clip)) {
      _pause();
      _setIndex(widget.clip.triggerIndex);
    }
  }

  /// Moves the playhead and asks for that frame.
  void _setIndex(int next) {
    final clamped = next.clamp(0, widget.clip.frameCount - 1);
    if (clamped != _index) setState(() => _index = clamped);
    _requestFrame(clamped);
  }

  /// Decodes done, and frames skipped because a newer one was requested
  /// first. A high skip count means decoding cannot keep up with playback.
  int _decodes = 0;
  int _skipped = 0;
  int _decodeUs = 0;
  final _decodeReport = Stopwatch();

  void _requestFrame(int index) {
    if (_pending != null && _pending != index) _skipped++;
    _pending = index;
    if (_decoding) return;
    _decoding = true;
    unawaited(_drainDecodes());
  }

  Future<void> _drainDecodes() async {
    if (!_decodeReport.isRunning) _decodeReport.start();
    while (mounted && _pending != null) {
      final target = _pending!;
      _pending = null;
      final ui.Image image;
      final timer = Stopwatch()..start();
      try {
        image = await _decodeJpeg(widget.clip.frames[target].jpeg);
      } catch (error) {
        debugPrint('[review] frame $target would not decode: $error');
        continue;
      }
      _decodes++;
      _decodeUs += timer.elapsedMicroseconds;
      if (_decodeReport.elapsed >= const Duration(seconds: 1)) {
        final seconds = _decodeReport.elapsedMicroseconds / 1000000;
        debugPrint(
          '[review] ${(_decodes / seconds).toStringAsFixed(1)} decodes/s · '
          '${(_decodeUs / _decodes / 1000).toStringAsFixed(1)}ms each · '
          '$_skipped skipped · speed ${_speed ?? 'paused'}',
        );
        _decodeReport.reset();
        _decodes = 0;
        _skipped = 0;
        _decodeUs = 0;
      }
      if (!mounted) {
        image.dispose();
        break;
      }
      final previous = _shown;
      setState(() => _shown = image);
      // Freed after the frame that replaced it has actually been painted.
      // Counting generations was not enough: two decodes can land inside one
      // rendered frame, and then the image being disposed is still the one on
      // screen.
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }
    _decoding = false;
  }

  static Future<ui.Image> _decodeJpeg(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// Starts looping at [speed], or stops if that speed is already running.
  void _toggleLoop(double speed) {
    if (_speed == speed) {
      _pause();
      return;
    }
    _ticker.stop();
    setState(() {
      _speed = speed;
      _clipAnchor = widget.clip.offsetFromStart(_index);
    });
    _ticker.start();
    _watchdog.start();
    _requestFrame(_index);
  }

  void _pause() {
    _ticker.stop();
    _watchdog.stop();
    if (_speed != null) setState(() => _speed = null);
  }

  void _onTick(Duration elapsed) {
    final speed = _speed;
    final span = widget.clip.duration;
    if (speed == null || span <= Duration.zero) return;

    // Seek by time, not by frame count: the camera's spacing is never quite
    // even, so advancing a fixed number of frames per tick would drift off
    // real time across six seconds.
    final played = (elapsed.inMicroseconds * speed).round();
    final offset = Duration(
      microseconds:
          (_clipAnchor.inMicroseconds + played) % span.inMicroseconds,
    );
    final next = widget.clip.indexAtOffset(offset);
    if (next != _index) _setIndex(next);
  }

  void _step(int delta) {
    _pause();
    _setIndex(_index + delta);
  }

  static String _speedLabel(double speed) =>
      speed == 1.0 ? '1×' : '${speed.toString().replaceFirst('0.', '.')}×';

  bool _exporting = false;

  /// Speed choices offered at export, mirroring the review loop. A slowed
  /// file is the same frames under a slower header rate — nothing is
  /// interpolated, players simply hold each frame longer.
  static const _exportSpeeds = [
    (1.0, 'Full speed', '1×'),
    (0.5, 'Half speed', '0.5×'),
    (0.25, 'Quarter speed', '0.25×'),
  ];

  void _pickExportSpeed() {
    if (_exporting) return;
    _pause();
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
                  'Export Speed',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ..._exportSpeeds.map((option) {
            final (speed, name, label) = option;
            return ListTile(
              leading: Icon(
                speed == 1.0 ? Icons.play_arrow : Icons.slow_motion_video,
                size: 18,
                color: AppColors.textMuted,
              ),
              title: Text(
                '$name ($label)',
                style: AppTextStyles.sans(size: 14, color: Colors.white),
              ),
              tileColor: Colors.transparent,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _export(speed, label);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _export(double speed, String speedLabel) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ClipExportService.export(
        clip: widget.clip,
        baseName: 'impact',
        speed: speed,
      );
      if (!mounted) return;
      final at = speed == 1.0 ? '' : ' at $speedLabel';
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            result.format == ClipExportFormat.video
                ? 'Exported ${result.videoLabel}$at · ${result.sizeLabel}'
                      '\n${result.path}'
                : 'No video writer available '
                      '(${result.fallbackReason}). Exported '
                      '${result.frameCount} frames · '
                      '${result.sizeLabel}\n${result.path}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
    final shown = _shown;

    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              // The previous frame stays up until the next one has decoded,
              // so scrubbing never strobes through black.
              child: shown == null
                  ? const SizedBox.shrink()
                  : AspectRatio(
                      aspectRatio: shown.width / shown.height,
                      child: RawImage(image: shown, fit: BoxFit.contain),
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
                        onChanged: (v) {
                          _pause();
                          _setIndex(v.round());
                        },
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
                ],
              ),
              const SizedBox(height: 8),
              // A Wrap rather than a Row: docked in a split pane there is not
              // room for six controls across, and these should stack onto a
              // second line rather than overflow.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('LOOP', style: AppTextStyles.statLabel()),
                  ),
                  for (final speed in _speeds)
                    _PillButton(
                      label: _speedLabel(speed),
                      muted: _speed != speed,
                      selected: _speed == speed,
                      onTap: () => _toggleLoop(speed),
                    ),
                  if (_speed != null)
                    _PillButton(label: 'Stop', muted: true, onTap: _pause),
                  _PillButton(
                    label: 'Jump to packet',
                    onTap: () {
                      _pause();
                      _setIndex(clip.triggerIndex);
                    },
                  ),
                  _PillButton(
                    label: _exporting ? 'Exporting…' : 'Export',
                    muted: _exporting,
                    onTap: _exporting ? () {} : _pickExportSpeed,
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
