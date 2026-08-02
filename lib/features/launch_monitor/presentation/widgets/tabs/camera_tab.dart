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
  /// The shot being scrubbed, or null while the live feeds are showing.
  ShotClips? _reviewing;

  /// The review in [_reviewing] opened itself off a fresh capture, so it
  /// starts looping; a review the golfer opened by hand starts paused at
  /// the trigger, ready to scrub.
  bool _autoPlayReview = false;

  /// The second pane is open — either the golfer added it this session or
  /// slot 1 has a remembered camera from a previous one.
  bool _secondPaneOpen = false;

  @override
  void initState() {
    super.initState();
    _secondPaneOpen = ref
        .read(unitPrefsProvider)
        .cameraSlots[1]
        .deviceName
        .isNotEmpty;
    // Enumerating touches provider state, which isn't allowed while this
    // widget is mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var slot = 0; slot < kCameraSlotCount; slot++) {
        if (slot > 0 && !_secondPaneOpen) continue;
        final feed = ref.read(cameraFeedProvider(slot));
        if (feed.status == CameraFeedStatus.idle && feed.devices.isEmpty) {
          ref.read(cameraFeedProvider(slot).notifier).refreshDevices();
        }
      }
    });
  }

  void _setAllPreviewsPaused(bool paused) {
    for (var slot = 0; slot < kCameraSlotCount; slot++) {
      ref.read(cameraFeedProvider(slot).notifier).setPreviewPaused(paused);
    }
  }

  @override
  void dispose() {
    // The providers outlive this widget, so a paused preview would stay
    // paused for the next visit to the tab.
    if (_reviewing != null) _setAllPreviewsPaused(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capture = ref.watch(impactClipProvider);

    // A finished capture opens itself, looping. The golfer's hands are on a
    // club, not the mouse — the replay appearing unprompted right after the
    // swing is the point of having cameras on the rig. The next shot simply
    // replaces it; Back to live dismisses it.
    ref.listen<ShotClips?>(impactClipProvider.select((s) => s.latest), (
      previous,
      next,
    ) {
      if (next == null || next.shotIndex == previous?.shotIndex) return;
      debugPrint('[review] auto-opening shot ${next.shotIndex + 1}');
      _setAllPreviewsPaused(true);
      setState(() {
        _reviewing = next;
        _autoPlayReview = true;
      });
    });

    final reviewing = _reviewing;
    return Column(
      children: [
        Expanded(
          child: reviewing == null
              ? _buildFeeds(context)
              : _ShotReview(
                  // Keyed per shot so a newer capture opens at its own
                  // trigger rather than inheriting a stale playhead.
                  key: ValueKey('review-${reviewing.shotIndex}'),
                  shot: reviewing,
                  autoPlay: _autoPlayReview,
                ),
        ),
        if (capture.armed || capture.clips.isNotEmpty)
          _CaptureBar(
            capture: capture,
            isReviewing: reviewing != null,
            onReview: (shot) {
              debugPrint('[review] tapped, shot ${shot.shotIndex + 1}');
              _setAllPreviewsPaused(true);
              setState(() {
                _reviewing = shot;
                _autoPlayReview = false;
              });
            },
            onBackToLive: () {
              _setAllPreviewsPaused(false);
              setState(() => _reviewing = null);
            },
          ),
      ],
    );
  }

  Widget _buildFeeds(BuildContext context) {
    final feedA = ref.watch(cameraFeedProvider(0));
    final panes = <Widget>[
      Expanded(
        child: _FeedPane(
          slot: 0,
          feed: feedA,
          caption: _secondPaneOpen ? kCameraSlotLabels[0] : null,
          trailing: _secondPaneOpen
              ? null
              : _BarButton(
                  icon: Icons.video_call,
                  label: 'Add second camera',
                  onTap: () {
                    setState(() => _secondPaneOpen = true);
                    ref.read(cameraFeedProvider(1).notifier).refreshDevices();
                  },
                ),
        ),
      ),
    ];
    if (_secondPaneOpen) {
      final feedB = ref.watch(cameraFeedProvider(1));
      panes.add(
        Expanded(
          child: _FeedPane(
            slot: 1,
            feed: feedB,
            caption: kCameraSlotLabels[1],
            trailing: _BarButton(
              icon: Icons.close,
              label: 'Remove second camera',
              onTap: () {
                ref.read(cameraFeedProvider(1).notifier).stop();
                setState(() => _secondPaneOpen = false);
              },
            ),
          ),
        ),
      );
    }
    if (panes.length == 1) return panes.first;
    // Side by side where there is width for two pictures; stacked where
    // there isn't — a portrait window gives each angle the full width.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panes[0],
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.border,
              ),
              panes[1],
            ],
          );
        }
        return Column(
          children: [
            panes[0],
            const Divider(height: 1, color: AppColors.border),
            panes[1],
          ],
        );
      },
    );
  }
}

/// One camera slot as a standalone view, for a split-view pane.
///
/// Just the toolbar and the picture — capture status and clip review stay on
/// the full Camera tab, because in a quarter-width pane those controls would
/// crowd out the video this pane exists to show. With two cameras in
/// adjacent panes, each pane is one angle.
class CameraSlotView extends ConsumerStatefulWidget {
  final int slot;

  const CameraSlotView({super.key, required this.slot});

  @override
  ConsumerState<CameraSlotView> createState() => _CameraSlotViewState();
}

class _CameraSlotViewState extends ConsumerState<CameraSlotView> {
  /// The shot this pane is replaying, or null while the live feed shows.
  /// Set automatically when a capture completes — in a split-view pane
  /// there is no capture bar, so without this a shot would come and go
  /// with nothing on screen reacting at all.
  ShotClips? _replaying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final feed = ref.read(cameraFeedProvider(widget.slot));
      if (feed.status == CameraFeedStatus.idle && feed.devices.isEmpty) {
        ref.read(cameraFeedProvider(widget.slot).notifier).refreshDevices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(cameraFeedProvider(widget.slot));

    ref.listen<ShotClips?>(impactClipProvider.select((s) => s.latest), (
      previous,
      next,
    ) {
      if (next == null || next.shotIndex == previous?.shotIndex) return;
      final clip = next.angles[widget.slot];
      if (clip == null || clip.isEmpty) return;
      setState(() => _replaying = next);
    });

    final caption = widget.slot < kCameraSlotLabels.length
        ? kCameraSlotLabels[widget.slot]
        : null;

    final replaying = _replaying;
    final clip = replaying?.angles[widget.slot];
    if (replaying != null && clip != null && !clip.isEmpty) {
      return Column(
        children: [
          _CameraBar(slot: widget.slot, feed: feed, caption: caption),
          Expanded(
            child: _PaneReplay(
              key: ValueKey('replay-${replaying.shotIndex}-${widget.slot}'),
              clip: clip,
              shotIndex: replaying.shotIndex,
              onLive: () => setState(() => _replaying = null),
            ),
          ),
        ],
      );
    }

    return _FeedPane(slot: widget.slot, feed: feed, caption: caption);
  }
}

/// One camera slot: its toolbar and its picture.
class _FeedPane extends StatelessWidget {
  final int slot;
  final CameraFeedState feed;

  /// Angle name shown in the bar once a second pane exists — with one
  /// camera the label would be noise.
  final String? caption;

  /// Extra control on the bar's right (add/remove second camera).
  final Widget? trailing;

  const _FeedPane({
    required this.slot,
    required this.feed,
    this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CameraBar(slot: slot, feed: feed, caption: caption, trailing: trailing),
        Expanded(child: _CameraBody(slot: slot, feed: feed)),
      ],
    );
  }
}

// ── Capture status / review switch ───────────────────────────────────────────

String _slotShort(int slot) => slot < kCameraSlotShortLabels.length
    ? kCameraSlotShortLabels[slot]
    : 'C$slot';

class _CaptureBar extends StatelessWidget {
  final ImpactClipState capture;
  final bool isReviewing;
  final ValueChanged<ShotClips> onReview;
  final VoidCallback onBackToLive;

  const _CaptureBar({
    required this.capture,
    required this.isReviewing,
    required this.onReview,
    required this.onBackToLive,
  });

  @override
  Widget build(BuildContext context) {
    final latest = capture.latest;
    final armedSlots = capture.armedSlots.toList()..sort();

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // With one camera the status is one dot and one number. With two,
          // each angle gets its own dot and measured rate — the readout that
          // says "the face-on camera is being starved" before its clip ever
          // comes out short.
          if (capture.armed && !capture.capturing && armedSlots.length > 1)
            Flexible(child: _buildAngleHealth(context, armedSlots))
          else
            Flexible(child: _buildSimpleStatus(context)),
          const Spacer(),
          if (latest != null) ...[
            if (!isReviewing)
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
              label: isReviewing ? 'Back to live' : 'Review',
              onTap: isReviewing ? onBackToLive : () => onReview(latest),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleStatus(BuildContext context) {
    final (Color dot, String label) = capture.capturing
        ? (AppColors.severityWarning, 'Capturing the post-roll…')
        : capture.armed
        ? (context.accent, '${capture.bufferedFrames} frames buffered')
        : (AppColors.textDimmed, 'Not buffering');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(dot),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sans(size: 12, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildAngleHealth(BuildContext context, List<int> armedSlots) {
    final children = <Widget>[];
    for (final slot in armedSlots) {
      final fps = capture.anglesFps[slot];
      if (children.isNotEmpty) children.add(_separator());
      children.add(_dot(_healthColor(context, fps)));
      children.add(const SizedBox(width: 5));
      children.add(
        Text(
          '${_slotShort(slot)} ${fps == null ? '—' : fps.toStringAsFixed(0)}',
          style: AppTextStyles.sans(size: 12, color: AppColors.textMuted),
        ),
      );
    }
    children.add(_separator());
    children.add(
      Flexible(
        child: Text(
          '${capture.bufferedFrames} buffered',
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.sans(size: 12, color: AppColors.textDimmed),
        ),
      ),
    );
    return Tooltip(
      message:
          'Measured frames per second reaching the clip buffer, per angle. '
          'A low number usually means the camera is sharing USB bandwidth.',
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  static Widget _dot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  static Widget _separator() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7),
    child: Text(
      '·',
      style: AppTextStyles.sans(size: 12, color: AppColors.textDimmed),
    ),
  );

  /// Absolute thresholds rather than a fraction of the requested rate,
  /// because DirectShow's granted rate is unreliable. 24fps covers a swing
  /// well enough to review; below 10 the clip will read as a slideshow.
  static Color _healthColor(BuildContext context, double? fps) {
    if (fps == null) return AppColors.textDimmed;
    if (fps >= 24) return context.accent;
    if (fps >= 10) return AppColors.severityWarning;
    return AppColors.severityCritical;
  }

  static String _clipSummary(ShotClips shot) {
    final clip = shot.primary;
    final angles = shot.angleCount > 1 ? ' · ${shot.angleCount} angles' : '';
    return 'Shot ${shot.shotIndex + 1}$angles · ${clip.frameCount} frames · '
        '${clip.effectiveFps.toStringAsFixed(0)} fps';
  }
}

/// Low chip for the loop speeds, in the hole builder's palette grammar:
/// card surface, accent border when active, no label text beyond the value.
class _SpeedChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Overrides the loop-speed wording, so the same chip can serve the
  /// review's angle switcher without claiming to be a speed.
  final String? tooltip;

  const _SpeedChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final message = tooltip ?? (active ? 'Stop looping' : 'Loop at $label');
    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        selected: active,
        label: tooltip ?? 'Loop at $label',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? context.accentSubtle : AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? context.accent : AppColors.border,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Text(
              label,
              style: AppTextStyles.sans(
                size: 12,
                weight: FontWeight.w700,
                color: active ? context.accent : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  final int slot;
  final CameraFeedState feed;
  final String? caption;
  final Widget? trailing;

  const _CameraBar({
    required this.slot,
    required this.feed,
    this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cameraFeedProvider(slot).notifier);
    final canPick = feed.devices.isNotEmpty && !feed.isBusy;

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (caption != null) ...[
            Text(caption!.toUpperCase(), style: AppTextStyles.statLabel()),
            const SizedBox(width: 8),
          ],
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
              icon: Icons.rotate_90_degrees_cw,
              label: 'Rotate view 90°',
              onTap: () {
                final slots = ref.read(unitPrefsProvider).cameraSlots;
                final current = slot < slots.length
                    ? slots[slot].rotationQuarterTurns
                    : 0;
                ref
                    .read(cameraFeedProvider(slot).notifier)
                    .setRotation(current + 1);
              },
            ),
            _BarButton(
              icon: Icons.aspect_ratio,
              label: 'Capture resolution',
              onTap: () => _showModePicker(context, ref, slot),
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
                : () => notifier.refreshDevices(force: true),
          ),
          if (trailing != null) trailing!,
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
            final isSel = device.index == feed.selected?.index;
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
                ref.read(cameraFeedProvider(slot).notifier).select(device);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

void _showModePicker(BuildContext context, WidgetRef ref, int slot) {
  final slots = ref.read(unitPrefsProvider).cameraSlots;
  final pref = slot < slots.length ? slots[slot] : const CameraSlotPref();
  final current = CaptureMode(pref.width, pref.height, pref.fps);
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
              ref.read(cameraFeedProvider(slot).notifier).setMode(mode);
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
  final int slot;
  final CameraFeedState feed;

  const _CameraBody({required this.slot, required this.feed});

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
            () => ref
                .read(cameraFeedProvider(slot).notifier)
                .refreshDevices(force: true),
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
            () => ref
                .read(cameraFeedProvider(slot).notifier)
                .refreshDevices(force: true),
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
  if (text.contains('other slot')) {
    return 'Each angle needs its own device. If both cameras are the same '
        'model, check the resolution shown beside each entry to tell them '
        'apart.';
  }
  if (text.contains('timeout')) {
    return 'The camera scan stalled inside a driver. Unplug and replug the '
        'camera — and if both cameras share one USB hub, move one to a '
        'different port.';
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

// ── Shot review ──────────────────────────────────────────────────────────────

/// Owned decode pipeline for one angle of the review.
///
/// Decoded here rather than with `Image.memory`, which was what wedged the
/// UI: every rebuild built a fresh MemoryImage, so playback pushed thirty
/// distinct decodes a second through Flutter's image cache and evicted the
/// cache continuously. Owning the decode means one in flight at a time, no
/// cache, and explicit disposal. If decoding falls behind, the pending index
/// is overwritten rather than queued — skip to the newest frame instead of
/// working through a backlog and drifting further behind.
class _AngleDecoder {
  final ImpactClip clip;

  /// Fired after a decoded frame lands in [shown]; the review rebuilds.
  final VoidCallback onFrame;

  ui.Image? shown;
  int shownIndex = -1;

  int? _pending;
  bool _decoding = false;
  bool _disposed = false;

  _AngleDecoder({required this.clip, required this.onFrame});

  void request(int index) {
    if (_disposed) return;
    if (index == shownIndex && shown != null) return;
    _pending = index;
    if (_decoding) return;
    _decoding = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    while (!_disposed && _pending != null) {
      final target = _pending!;
      _pending = null;
      final ui.Image image;
      try {
        image = await _decodeJpeg(clip.frames[target].jpeg);
      } catch (error) {
        debugPrint('[review] frame $target would not decode: $error');
        continue;
      }
      if (_disposed) {
        image.dispose();
        break;
      }
      final previous = shown;
      shown = image;
      shownIndex = target;
      onFrame();
      // Freed after the frame that replaced it has actually been painted.
      // Counting generations was not enough: two decodes can land inside one
      // rendered frame, and then the image being disposed is still the one
      // on screen.
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => previous.dispose(),
        );
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

  void dispose() {
    _disposed = true;
    shown?.dispose();
    shown = null;
    shownIndex = -1;
  }
}

/// A split-view pane's automatic replay: one angle of the latest shot,
/// looping at real speed until the golfer taps Live or the next shot
/// replaces it.
///
/// Deliberately not the full review — a quarter-width pane has no room for
/// a scrubber and export sheets, and the full Camera tab already auto-opens
/// those. This is the glanceable version: swing, look up, watch it loop.
class _PaneReplay extends StatefulWidget {
  final ImpactClip clip;
  final int shotIndex;
  final VoidCallback onLive;

  const _PaneReplay({
    super.key,
    required this.clip,
    required this.shotIndex,
    required this.onLive,
  });

  @override
  State<_PaneReplay> createState() => _PaneReplayState();
}

class _PaneReplayState extends State<_PaneReplay>
    with SingleTickerProviderStateMixin {
  late final _AngleDecoder _decoder = _AngleDecoder(
    clip: widget.clip,
    onFrame: () {
      if (mounted) setState(() {});
    },
  );

  late final _ticker = createTicker(_onTick);

  @override
  void initState() {
    super.initState();
    _decoder.request(widget.clip.triggerIndex);
    if (widget.clip.duration > Duration.zero) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _decoder.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final span = widget.clip.duration;
    if (span <= Duration.zero) return;
    // Same time-seek as the review loop; requests for an unchanged index
    // are dropped by the decoder, so the per-vsync tick costs nothing
    // between frames.
    final offset = Duration(
      microseconds: elapsed.inMicroseconds % span.inMicroseconds,
    );
    _decoder.request(widget.clip.indexAtOffset(offset));
  }

  @override
  Widget build(BuildContext context) {
    final shown = _decoder.shown;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: shown == null
                ? const SizedBox.shrink()
                : AspectRatio(
                    aspectRatio: shown.width / shown.height,
                    child: RawImage(image: shown, fit: BoxFit.contain),
                  ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(140),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Shot ${widget.shotIndex + 1} · replay',
                style: AppTextStyles.sans(
                  size: 11,
                  weight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: _PillButton(label: 'Live', onTap: widget.onLive),
          ),
        ],
      ),
    );
  }
}

/// One way of exporting a multi-angle shot, picked off the layout sheet.
class _ExportChoice {
  final String title;
  final IconData icon;
  final CompositeLayout? layout;
  final int? slot;
  final bool separate;

  const _ExportChoice({
    required this.title,
    required this.icon,
    this.layout,
    this.slot,
    this.separate = false,
  });
}

/// Frame-by-frame scrub through every angle of one shot, on a shared clock.
///
/// The playhead is a trigger-relative time, not a frame number: zero is the
/// BLE packet on every angle, so the down-the-line and face-on views show
/// the same instant of the swing however differently their cameras were
/// pacing. An angle without a frame at the current instant holds its nearest
/// one — cameras start and stop buffering at slightly different moments, and
/// a black flash at the edges would read as a glitch.
class _ShotReview extends StatefulWidget {
  final ShotClips shot;

  /// Start looping at full speed instead of paused at the trigger — set
  /// when the review opened itself off a fresh capture.
  final bool autoPlay;

  const _ShotReview({super.key, required this.shot, this.autoPlay = false});

  @override
  State<_ShotReview> createState() => _ShotReviewState();
}

class _ShotReviewState extends State<_ShotReview>
    with SingleTickerProviderStateMixin {
  /// Loop rates offered. Quarter speed is the slowest worth having at 30fps —
  /// below that the gaps between frames read as a slideshow rather than
  /// slow motion, and stepping is the better tool.
  static const _speeds = [1.0, 0.5, 0.25];

  /// Speed choices offered at export, mirroring the review loop. A slowed
  /// file is the same frames under a slower header rate — nothing is
  /// interpolated, players simply hold each frame longer.
  static const _exportSpeeds = [
    (1.0, 'Full speed', '1×'),
    (0.5, 'Half speed', '0.5×'),
    (0.25, 'Quarter speed', '0.25×'),
  ];

  /// Angles that actually captured frames, lowest slot first.
  late List<int> _slots;

  final Map<int, _AngleDecoder> _decoders = {};

  /// The one angle on screen, or null for every angle at once.
  int? _solo;

  /// The shared playhead, as a signed offset from the trigger packet.
  Duration _pos = Duration.zero;

  /// Playback rate, or null when paused.
  double? _speed;

  /// Where playback resumed from. The ticker's elapsed time restarts at zero
  /// each start, so the position it advances has to be anchored separately —
  /// otherwise changing speed would fling the playhead back.
  Duration _anchor = Duration.zero;

  late final _ticker = createTicker(_onTick);
  final _watchdog = EventLoopWatchdog('review');

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _adoptShot();
    final shot = widget.shot;
    debugPrint(
      '[review] opening shot ${shot.shotIndex + 1}: ${shot.angleCount} '
      'angle(s), ${(shot.byteSize / (1024 * 1024)).toStringAsFixed(1)}MB',
    );
    if (widget.autoPlay) {
      // After the first frame, not during mount — the ticker and setState
      // want a built element under them.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _speed == null && _slots.isNotEmpty) _toggleLoop(1.0);
      });
    }
  }

  void _adoptShot() {
    for (final decoder in _decoders.values) {
      decoder.dispose();
    }
    _decoders.clear();
    _slots = [
      for (final slot in widget.shot.slots)
        if (!widget.shot.angles[slot]!.isEmpty) slot,
    ];
    for (final slot in _slots) {
      _decoders[slot] = _AngleDecoder(
        clip: widget.shot.angles[slot]!,
        onFrame: () {
          if (mounted) setState(() {});
        },
      );
    }
    if (_solo != null && !_slots.contains(_solo)) _solo = null;
    _pos = _clampToWindow(Duration.zero);
    _syncFrames();
  }

  @override
  void didUpdateWidget(_ShotReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A newer shot replaced this one under the same element; start over at
    // its own trigger rather than holding a playhead that meant something
    // else.
    if (!identical(oldWidget.shot, widget.shot)) {
      _pause();
      setState(_adoptShot);
    }
  }

  @override
  void dispose() {
    _watchdog.stop();
    _ticker.dispose();
    for (final decoder in _decoders.values) {
      decoder.dispose();
    }
    super.dispose();
  }

  // ── Shared clock ───────────────────────────────────────────────────────────

  List<int> get _displayedSlots {
    final solo = _solo;
    return solo != null && _slots.contains(solo) ? [solo] : _slots;
  }

  Duration _startRel(ImpactClip clip) =>
      clip.frames.first.at.difference(widget.shot.capturedAt);

  /// The union of the displayed angles' windows, trigger-relative. Union
  /// rather than intersection so the scrubber can reach every captured
  /// frame; angles missing a moment simply hold their nearest frame.
  (Duration, Duration) _window() {
    Duration? start;
    Duration? end;
    for (final slot in _displayedSlots) {
      final clip = widget.shot.angles[slot]!;
      final s = _startRel(clip);
      final e = clip.frames.last.at.difference(widget.shot.capturedAt);
      if (start == null || s < start) start = s;
      if (end == null || e > end) end = e;
    }
    return (start ?? Duration.zero, end ?? Duration.zero);
  }

  Duration _clampToWindow(Duration value) {
    final (start, end) = _window();
    if (value < start) return start;
    if (value > end) return end;
    return value;
  }

  int _indexFor(ImpactClip clip) => clip.indexAtOffset(_pos - _startRel(clip));

  void _syncFrames() {
    for (final slot in _displayedSlots) {
      final clip = widget.shot.angles[slot]!;
      _decoders[slot]!.request(_indexFor(clip));
    }
  }

  void _seek(Duration pos) {
    final clamped = _clampToWindow(pos);
    if (clamped != _pos) setState(() => _pos = clamped);
    _syncFrames();
  }

  /// Steps to the nearest frame boundary in [direction] across every
  /// displayed angle — in two-up view, one press lands on whichever camera
  /// has the next frame, so no captured instant is skipped over.
  void _step(int direction) {
    _pause();
    Duration? best;
    for (final slot in _displayedSlots) {
      final clip = widget.shot.angles[slot]!;
      final rel = _startRel(clip);
      final index = _indexFor(clip);
      final here = rel + clip.offsetFromStart(index);
      Duration? candidate;
      if (direction > 0) {
        if (index + 1 < clip.frameCount) {
          candidate = rel + clip.offsetFromStart(index + 1);
        }
      } else {
        if (here < _pos) {
          candidate = here;
        } else if (index > 0) {
          candidate = rel + clip.offsetFromStart(index - 1);
        }
      }
      if (candidate == null) continue;
      if (direction > 0) {
        if (candidate > _pos && (best == null || candidate < best)) {
          best = candidate;
        }
      } else {
        if (candidate < _pos && (best == null || candidate > best)) {
          best = candidate;
        }
      }
    }
    if (best != null) _seek(best);
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  /// Starts looping at [speed], or stops if that speed is already running.
  void _toggleLoop(double speed) {
    if (_speed == speed) {
      _pause();
      return;
    }
    _ticker.stop();
    setState(() {
      _speed = speed;
      _anchor = _pos;
    });
    _ticker.start();
    _watchdog.start();
  }

  void _pause() {
    _ticker.stop();
    _watchdog.stop();
    if (_speed != null) setState(() => _speed = null);
  }

  void _onTick(Duration elapsed) {
    final speed = _speed;
    final (start, end) = _window();
    final span = end - start;
    if (speed == null || span <= Duration.zero) return;

    // Seek by time, not by frame count: the cameras' spacing is never quite
    // even — and in two-up view they don't even share a rate — so time is
    // the only clock both angles agree on.
    final played = (elapsed.inMicroseconds * speed).round();
    final offsetUs =
        ((_anchor - start).inMicroseconds + played) % span.inMicroseconds;
    final next = start + Duration(microseconds: offsetUs);
    if (next != _pos) {
      setState(() => _pos = next);
      _syncFrames();
    }
  }

  void _setSolo(int? slot) {
    if (_solo == slot) return;
    setState(() {
      _solo = slot;
      _pos = _clampToWindow(_pos);
      // Looping continues, re-anchored so the switch doesn't jump the
      // playhead into a window the new selection may not cover.
      _anchor = _pos;
    });
    if (_speed != null) {
      _ticker.stop();
      _ticker.start();
    }
    _syncFrames();
  }

  static String _speedLabel(double speed) =>
      speed == 1.0 ? '1×' : '${speed.toString().replaceFirst('0.', '.')}×';

  // ── Export ─────────────────────────────────────────────────────────────────

  void _pickExport() {
    if (_exporting) return;
    _pause();
    if (_slots.length < 2) {
      _pickSpeed(
        _ExportChoice(
          title: 'Export',
          icon: Icons.save_alt,
          slot: _slots.first,
        ),
      );
      return;
    }

    final choices = [
      const _ExportChoice(
        title: 'Side by side',
        icon: Icons.view_column,
        layout: CompositeLayout.sideBySide,
      ),
      const _ExportChoice(
        title: 'Stacked',
        icon: Icons.view_agenda,
        layout: CompositeLayout.stacked,
      ),
      const _ExportChoice(
        title: 'Separate files',
        icon: Icons.filter_none,
        separate: true,
      ),
      for (final slot in _slots)
        _ExportChoice(
          title: '${_slotShort(slot)} only',
          icon: Icons.videocam,
          slot: slot,
        ),
    ];

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
                  'Export Layout',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ...choices.map(
            (choice) => ListTile(
              leading: Icon(choice.icon, size: 18, color: AppColors.textMuted),
              title: Text(
                choice.title,
                style: AppTextStyles.sans(size: 14, color: Colors.white),
              ),
              tileColor: Colors.transparent,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _pickSpeed(choice);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _pickSpeed(_ExportChoice choice) {
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
                unawaited(_runExport(choice, speed, label));
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _soloBaseName(int slot) => _slots.length > 1
      ? 'impact-${_slotShort(slot).toLowerCase()}'
      : 'impact';

  Future<void> _runExport(
    _ExportChoice choice,
    double speed,
    String speedLabel,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    final at = speed == 1.0 ? '' : ' at $speedLabel';
    try {
      if (choice.layout != null) {
        final result = await ClipExportService.exportComposite(
          shot: widget.shot,
          layout: choice.layout!,
          baseName: 'impact',
          speed: speed,
        );
        _showResult(messenger, result, at);
      } else if (choice.separate) {
        final paths = <String>[];
        for (final slot in _slots) {
          final result = await ClipExportService.export(
            clip: widget.shot.angles[slot]!,
            baseName: _soloBaseName(slot),
            speed: speed,
          );
          paths.add(result.path);
        }
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              'Exported ${paths.length} files$at\n${paths.join('\n')}',
            ),
          ),
        );
      } else {
        final slot = choice.slot ?? _slots.first;
        final result = await ClipExportService.export(
          clip: widget.shot.angles[slot]!,
          baseName: _soloBaseName(slot),
          speed: speed,
        );
        _showResult(messenger, result, at);
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showResult(
    ScaffoldMessengerState messenger,
    ClipExportResult result,
    String at,
  ) {
    if (!mounted) return;
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
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) {
      return const _Message(
        icon: Icons.videocam_off,
        title: 'Empty clip',
        detail: 'No frames were buffered for this shot.',
      );
    }

    final (start, end) = _window();
    final spanMs = (end - start).inMilliseconds;
    final posMs = (_pos - start).inMilliseconds.clamp(0, spanMs);
    final atTrigger = _displayedSlots.any((slot) {
      final clip = widget.shot.angles[slot]!;
      return _indexFor(clip) == clip.triggerIndex;
    });

    return Column(
      children: [
        Expanded(child: _buildPanes()),
        // Two rows in the hole builder's compact grammar — small square icon
        // buttons and low chips — so the video keeps the height.
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
            color: AppColors.surface,
          ),
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    _BarButton(
                      icon: Icons.chevron_left,
                      label: 'Previous frame',
                      onTap: posMs > 0 ? () => _step(-1) : null,
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
                          value: posMs.toDouble(),
                          min: 0,
                          max: spanMs > 0 ? spanMs.toDouble() : 1,
                          label: _signedSeconds(_pos),
                          onChanged: spanMs > 0
                              ? (v) {
                                  _pause();
                                  _seek(
                                    start +
                                        Duration(milliseconds: v.round()),
                                  );
                                }
                              : null,
                        ),
                      ),
                    ),
                    _BarButton(
                      icon: Icons.chevron_right,
                      label: 'Next frame',
                      onTap: posMs < spanMs ? () => _step(1) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message:
                          'Time from when the launch monitor reported the '
                          'shot. Impact is slightly earlier — by however '
                          'long the reading took to reach the app.',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_displayedSlots.length == 1) ...[
                            Flexible(
                              child: Text(
                                _frameCounter(_displayedSlots.first),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.statLabel(),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _signedSeconds(_pos),
                            style: AppTextStyles.statValue(
                              size: 13,
                              color: atTrigger
                                  ? AppColors.severityWarning
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_slots.length > 1) ...[
                    _SpeedChip(
                      label: 'Both',
                      active: _solo == null,
                      tooltip: 'Show every angle',
                      onTap: () => _setSolo(null),
                    ),
                    const SizedBox(width: 5),
                    for (final slot in _slots) ...[
                      _SpeedChip(
                        label: _slotShort(slot),
                        active: _solo == slot,
                        tooltip: 'Show ${_slotShort(slot)} only',
                        onTap: () => _setSolo(slot),
                      ),
                      const SizedBox(width: 5),
                    ],
                    const SizedBox(width: 4),
                  ],
                  // Tapping the running speed stops it, so a separate Stop
                  // control earns no space here.
                  for (final speed in _speeds) ...[
                    _SpeedChip(
                      label: _speedLabel(speed),
                      active: _speed == speed,
                      onTap: () => _toggleLoop(speed),
                    ),
                    const SizedBox(width: 5),
                  ],
                  _BarButton(
                    icon: Icons.save_alt,
                    label: _exporting ? 'Exporting…' : 'Export clip',
                    onTap: _exporting ? null : _pickExport,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _frameCounter(int slot) {
    final clip = widget.shot.angles[slot]!;
    return '${_indexFor(clip) + 1}/${clip.frameCount}';
  }

  Widget _buildPanes() {
    final slots = _displayedSlots;
    if (slots.length == 1) return _pane(slots.first, captioned: false);

    final panes = [for (final slot in slots) _pane(slot, captioned: true)];
    // Side by side where there is width for two pictures; stacked where
    // there isn't — a portrait window gives each angle the full width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final row = constraints.maxWidth >= 520;
        final children = <Widget>[];
        for (final pane in panes) {
          if (children.isNotEmpty) {
            children.add(
              row
                  ? const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border,
                    )
                  : const Divider(height: 1, color: AppColors.border),
            );
          }
          children.add(Expanded(child: pane));
        }
        return row
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Column(children: children);
      },
    );
  }

  Widget _pane(int slot, {required bool captioned}) {
    final clip = widget.shot.angles[slot]!;
    final shown = _decoders[slot]!.shown;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            // The previous frame stays up until the next one has decoded,
            // so scrubbing never strobes through black.
            child: shown == null
                ? const SizedBox.shrink()
                : AspectRatio(
                    aspectRatio: shown.width / shown.height,
                    child: RawImage(image: shown, fit: BoxFit.contain),
                  ),
          ),
          if (captioned)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_slotShort(slot)} · ${_frameCounter(slot)}',
                  style: AppTextStyles.sans(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
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
