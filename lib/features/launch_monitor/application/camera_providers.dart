/// Live camera feed for the desktop Camera tab.
///
/// The feed is held here rather than in the tab's widget state on purpose:
/// the camera has to survive tab switches. Today that only avoids a visible
/// re-open every time the golfer flips between Camera and Dispersion; it
/// matters more for what comes next.
///
/// Planned: capture the three seconds *before* the launch monitor reports a
/// shot and the three seconds after. The pre-roll half can't be recorded on
/// demand — by the time the BLE packet lands, the impact is already in the
/// past — so it has to come out of a buffer that is always filling while the
/// session is live. Note that `camera_windows` implements neither
/// `startImageStream` nor concurrent recordings, so that buffer will have to
/// be built from continuously rolling `startVideoRecording` segments that get
/// trimmed on a shot, not from a frame-level ring buffer.
library;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

// ── Feed state ───────────────────────────────────────────────────────────────

enum CameraFeedStatus {
  /// Nothing attempted yet — the tab hasn't been opened.
  idle,

  /// Enumerating attached cameras.
  listing,

  /// No camera plugin for this platform (mobile, Linux, macOS).
  unsupported,

  /// The platform answered, but nothing is plugged in.
  noDevices,

  /// A device was picked and is being opened.
  opening,

  /// Frames are flowing; [CameraFeedState.controller] is safe to preview.
  streaming,

  /// Enumeration or open failed; see [CameraFeedState.error].
  failed,
}

@immutable
class CameraFeedState {
  final CameraFeedStatus status;

  /// Every camera the platform reported, in enumeration order.
  final List<CameraDescription> devices;

  /// The device being shown, or the one that failed to open.
  final CameraDescription? selected;

  /// Non-null only while [status] is [CameraFeedStatus.streaming] — at any
  /// other point it is either absent or mid-teardown, and previewing it
  /// throws.
  final CameraController? controller;

  final String? error;

  const CameraFeedState({
    this.status = CameraFeedStatus.idle,
    this.devices = const [],
    this.selected,
    this.controller,
    this.error,
  });

  bool get isBusy =>
      status == CameraFeedStatus.listing || status == CameraFeedStatus.opening;
}

// ── Notifier ─────────────────────────────────────────────────────────────────

final cameraFeedProvider =
    NotifierProvider<CameraFeedNotifier, CameraFeedState>(
      CameraFeedNotifier.new,
    );

class CameraFeedNotifier extends Notifier<CameraFeedState> {
  CameraController? _controller;
  bool _disposed = false;

  /// Guards against a slow open finishing after the user has moved on and
  /// picked a different camera — the stale open must not claim the preview.
  int _openGeneration = 0;

  @override
  CameraFeedState build() {
    ref.onDispose(() {
      _disposed = true;
      // Fire-and-forget: Riverpod's teardown is synchronous, and a released
      // camera device is the only thing that matters here.
      final controller = _controller;
      _controller = null;
      controller?.dispose();
    });
    return const CameraFeedState();
  }

  /// Presets tried in order until one opens.
  ///
  /// On Windows a preset is not a target size, it is a *ceiling*: the plugin
  /// scans the camera's native modes and takes the largest whose height is
  /// at or below the preset's cap (low 240, medium 480, high 720, veryHigh
  /// 1080, ultraHigh 2160, max unlimited), skipping anything under 15 fps.
  /// A camera whose smallest mode is taller than the cap matches nothing and
  /// fails with "Failed to initialize video preview".
  ///
  /// So the ladder climbs. 720p first, because impact happens in a couple of
  /// milliseconds and frame rate is worth more than pixels — but a camera
  /// that offers nothing that small needs the cap *raised*, not lowered.
  /// Stepping down would only tighten a ceiling that already matched
  /// nothing, which is exactly how a 1080p-only camera failed three times
  /// over.
  static const _resolutionLadder = [
    ResolutionPreset.high,
    ResolutionPreset.veryHigh,
    ResolutionPreset.ultraHigh,
    ResolutionPreset.max,
  ];

  /// Both halves of a [CameraException]. The code alone ("camera_error") says
  /// nothing; the description carries the platform's actual complaint.
  static String _describe(Object error) {
    if (error is! CameraException) return error.toString();
    final detail = error.description;
    return detail == null || detail.isEmpty
        ? error.code
        : '${error.code} — $detail';
  }

  /// Enumerates attached cameras. When [autoOpen] is set and the camera
  /// remembered in preferences is among them, it reopens without the golfer
  /// having to pick it again.
  ///
  /// Safe to call while a camera is live: a rescan looks for newly plugged-in
  /// devices, so it leaves a working feed alone unless that very device has
  /// gone away.
  Future<void> refreshDevices({bool autoOpen = true}) async {
    if (_disposed) return;
    final streaming = _controller;

    // Only show the busy state when there is no picture to interrupt.
    if (streaming == null) {
      state = CameraFeedState(
        status: CameraFeedStatus.listing,
        devices: state.devices,
        selected: state.selected,
      );
    }

    final List<CameraDescription> devices;
    try {
      devices = await availableCameras();
    } on MissingPluginException {
      // No federated implementation for this platform.
      await _failWith(
        const CameraFeedState(status: CameraFeedStatus.unsupported),
      );
      return;
    } on UnimplementedError {
      await _failWith(
        const CameraFeedState(status: CameraFeedStatus.unsupported),
      );
      return;
    } on CameraException catch (e) {
      await _failWith(
        CameraFeedState(
          status: CameraFeedStatus.failed,
          error: e.description ?? e.code,
        ),
      );
      return;
    }
    if (_disposed) return;

    final selected = state.selected;
    final stillAttached =
        selected != null && devices.any((d) => d.name == selected.name);

    // The live camera survived the rescan — keep it, just refresh the list.
    if (streaming != null && stillAttached) {
      state = CameraFeedState(
        status: CameraFeedStatus.streaming,
        devices: devices,
        selected: selected,
        controller: streaming,
      );
      return;
    }
    // It didn't: the device was unplugged out from under us.
    if (streaming != null) {
      _openGeneration++;
      await _releaseController();
      if (_disposed) return;
    }

    if (devices.isEmpty) {
      state = const CameraFeedState(status: CameraFeedStatus.noDevices);
      return;
    }

    state = CameraFeedState(status: CameraFeedStatus.idle, devices: devices);

    if (!autoOpen) return;
    final remembered = ref.read(unitPrefsProvider).cameraDeviceName;
    final match = devices.where((d) => d.name == remembered).firstOrNull;
    if (match != null) await select(match);
  }

  /// Releases any open camera and lands on [failure]. Enumeration failing
  /// means we can no longer trust the device we are holding.
  Future<void> _failWith(CameraFeedState failure) async {
    _openGeneration++;
    await _releaseController();
    if (_disposed) return;
    state = failure;
  }

  /// Opens [device] and starts the preview, replacing whatever was open.
  Future<void> select(CameraDescription device) async {
    if (_disposed) return;
    final generation = ++_openGeneration;

    await _releaseController();
    if (_disposed || generation != _openGeneration) return;

    state = CameraFeedState(
      status: CameraFeedStatus.opening,
      devices: state.devices,
      selected: device,
    );

    Object? lastError;
    for (final preset in _resolutionLadder) {
      final controller = CameraController(
        device,
        preset,
        // Swing video is analysed frame by frame; a microphone track would
        // only add a permission prompt and bytes.
        enableAudio: false,
      );

      try {
        await controller.initialize();
      } catch (error) {
        // Every failure is logged, not just the last one: which presets a
        // camera refuses is the diagnosis when it won't open at all.
        lastError = error;
        debugPrint(
          '[camera] "${device.name}" at ${preset.name} failed: '
          '${_describe(error)}',
        );
        await controller.dispose();
        continue;
      }

      // A newer select() landed while this one was opening, or the provider
      // went away: drop this camera rather than leaving it held open.
      if (_disposed || generation != _openGeneration) {
        await controller.dispose();
        return;
      }

      final size = controller.value.previewSize;
      final dims = size == null
          ? ''
          : ' at ${size.width.toInt()}x${size.height.toInt()}';
      debugPrint(
        '[camera] opened "${device.name}" on ${preset.name}$dims',
      );

      _controller = controller;
      state = CameraFeedState(
        status: CameraFeedStatus.streaming,
        devices: state.devices,
        selected: device,
        controller: controller,
      );
      ref.read(unitPrefsProvider.notifier).setCameraDeviceName(device.name);
      return;
    }

    // Every preset refused.
    if (_disposed || generation != _openGeneration) return;
    state = CameraFeedState(
      status: CameraFeedStatus.failed,
      devices: state.devices,
      selected: device,
      error: lastError == null ? null : _describe(lastError),
    );
  }

  /// Closes the camera, releasing it back to the OS, and forgets the choice
  /// so the tab doesn't silently reopen it next time.
  Future<void> stop() async {
    _openGeneration++;
    await _releaseController();
    if (_disposed) return;
    state = CameraFeedState(
      status: CameraFeedStatus.idle,
      devices: state.devices,
    );
    ref.read(unitPrefsProvider.notifier).setCameraDeviceName(null);
  }

  Future<void> _releaseController() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    // Drop the controller out of state before disposing it — a frame that
    // previews a disposed controller throws.
    if (!_disposed) {
      state = CameraFeedState(
        status: state.status,
        devices: state.devices,
        selected: state.selected,
      );
    }
    await controller.dispose();
  }
}
