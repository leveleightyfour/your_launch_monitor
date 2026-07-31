/// Live camera feed for the desktop Camera tab, captured through OpenCV.
///
/// **Why not the `camera` plugin.** `camera_windows` drives Media Foundation,
/// and on a plain UVC webcam its media-type search comes up empty and fails
/// with "Failed to initialize video preview" at every resolution preset —
/// flutter/flutter#140014, open and unresolved. It also reverted frame
/// streaming in 0.2.6, so it could never expose the frames the capture below
/// is built toward. OpenCV's VideoCapture takes the DirectShow path instead
/// and hands us decoded frames in Dart.
///
/// `camera`'s `availableCameras()` is still used, for device *names* only —
/// OpenCV addresses cameras by bare integer index and has no enumeration API.
///
/// **Planned:** capture the three seconds before the launch monitor reports a
/// shot and the three seconds after. The pre-roll can't be recorded on demand
/// — by the time the BLE packet lands the impact is already past — so it has
/// to come out of a buffer that is always filling while the session is live.
/// Frames arrive here one at a time, which is exactly the shape a ring buffer
/// needs; that was the deciding reason for this backend.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show availableCameras;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'package:omni_sniffer/features/launch_monitor/application/impact_clip_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

// ── OpenCV constants ─────────────────────────────────────────────────────────
//
// Given by value rather than by binding name. These are fixed in OpenCV's own
// headers (videoio.hpp, imgproc.hpp) and so are stable across binding
// versions and renames, which the Dart-side names are not.

/// `cv::CAP_ANY` — let OpenCV choose the backend.
const _capAny = 0;

/// `cv::CAP_DSHOW` — DirectShow. Named explicitly on Windows because the
/// default would pick Media Foundation, which is the stack that fails.
const _capDshow = 700;

const _propFrameWidth = 3; // cv::CAP_PROP_FRAME_WIDTH
const _propFrameHeight = 4; // cv::CAP_PROP_FRAME_HEIGHT
const _propFps = 5; // cv::CAP_PROP_FPS
const _propFourcc = 6; // cv::CAP_PROP_FOURCC

/// MJPG as a FOURCC integer: 'M' | 'J'<<8 | 'P'<<16 | 'G'<<24.
///
/// Asking for this matters more than the resolution does. Uncompressed YUY2
/// saturates USB long before 1080p, so a camera asked for a large frame in
/// its default format hands back a slideshow — a few frames a second — rather
/// than refusing. Requesting MJPG first is what makes the size request
/// achievable.
const _fourccMjpg = 1196444237;

/// `cv::COLOR_BGR2RGBA` — OpenCV decodes to BGR; Flutter uploads RGBA.
const _colorBgr2Rgba = 2;

/// How many device indices to look past the number the OS named, in case
/// OpenCV's enumeration order runs longer than Media Foundation's.
const _probeOvershoot = 2;

int get _backend =>
    defaultTargetPlatform == TargetPlatform.windows ? _capDshow : _capAny;

// ── Capture mode ─────────────────────────────────────────────────────────────

/// A frame size to ask the camera for.
@immutable
class CaptureMode {
  final int width;
  final int height;

  const CaptureMode(this.width, this.height);

  /// Take whatever the camera opens on. For most UVC devices that is 640x480,
  /// whatever the sensor is capable of.
  static const auto = CaptureMode(0, 0);

  bool get isAuto => width <= 0 || height <= 0;

  String get label => isAuto ? 'Camera default' : '$width×$height';

  /// Offered in the picker. A camera that cannot do the requested size snaps
  /// to its nearest supported mode rather than failing, so an over-ambitious
  /// choice costs nothing but a smaller frame than asked for.
  static const candidates = [
    auto,
    CaptureMode(640, 480),
    CaptureMode(1280, 720),
    CaptureMode(1920, 1080),
  ];

  @override
  bool operator ==(Object other) =>
      other is CaptureMode && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

// ── Devices ──────────────────────────────────────────────────────────────────

@immutable
class CameraDevice {
  /// The index OpenCV opens this camera by.
  final int index;

  /// The OS's name for it, or `Camera <index>` when enumeration gave nothing.
  final String name;

  /// Native frame size reported when probed. Zero when the driver declined
  /// to say before a frame was pulled.
  final int width;
  final int height;

  const CameraDevice({
    required this.index,
    required this.name,
    this.width = 0,
    this.height = 0,
  });

  /// `1920×1080`, or empty when the probe learned nothing.
  String get resolutionLabel => width > 0 && height > 0 ? '$width×$height' : '';
}

// ── Feed state ───────────────────────────────────────────────────────────────

enum CameraFeedStatus {
  /// Nothing attempted yet — the tab hasn't been opened.
  idle,

  /// Probing device indices.
  listing,

  /// The probe ran and found nothing to open.
  noDevices,

  /// A device was picked and is being opened.
  opening,

  /// Frames are flowing; [CameraFeedState.frames] is publishing them.
  streaming,

  /// Probing or opening failed; see [CameraFeedState.error].
  failed,
}

@immutable
class CameraFeedState {
  final CameraFeedStatus status;
  final List<CameraDevice> devices;
  final CameraDevice? selected;

  /// The live frame, replaced in place as each one decodes. Deliberately a
  /// listenable rather than part of this state: at 30fps, rebuilding every
  /// provider watcher per frame would repaint the whole tab thirty times a
  /// second to change one picture.
  final ValueListenable<ui.Image?>? frames;

  final String? error;

  const CameraFeedState({
    this.status = CameraFeedStatus.idle,
    this.devices = const [],
    this.selected,
    this.frames,
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
  cv.VideoCapture? _capture;
  bool _disposed = false;

  final ValueNotifier<ui.Image?> _frame = ValueNotifier<ui.Image?>(null);

  /// The frame two generations back. A frame is only disposed once another
  /// has replaced the one after it, so the image the widget tree is currently
  /// painting is never freed under it.
  ui.Image? _retired;

  /// Guards against a slow open finishing after the user picked a different
  /// camera — the stale open must not claim the preview.
  int _openGeneration = 0;

  /// Set while the tab is showing a captured clip instead of the feed.
  bool _previewPaused = false;

  @override
  CameraFeedState build() {
    ref.onDispose(() {
      _disposed = true;
      _openGeneration++;
      final capture = _capture;
      _capture = null;
      capture?.release();
      capture?.dispose();
      _frame.value?.dispose();
      _retired?.dispose();
      _frame.dispose();
    });
    return const CameraFeedState();
  }

  /// Finds attached cameras. OpenCV has no enumeration call, so this asks the
  /// OS for names and then confirms each index by opening it — the only way
  /// to know an index actually yields a camera.
  ///
  /// Safe to call while streaming: it leaves a working feed alone.
  Future<void> refreshDevices({bool autoOpen = true}) async {
    if (_disposed) return;
    if (_capture != null) return; // Already streaming; nothing to re-probe.

    state = CameraFeedState(
      status: CameraFeedStatus.listing,
      devices: state.devices,
      selected: state.selected,
    );

    // Names are a nicety — an unnamed camera is still perfectly openable.
    List<String> names = const [];
    try {
      names = (await availableCameras()).map((d) => d.name).toList();
    } catch (error) {
      debugPrint('[camera] name enumeration unavailable: $error');
    }
    if (_disposed) return;

    final List<CameraDevice> found;
    try {
      found = await _probe(names);
    } catch (error, stack) {
      // Logged as well as surfaced: a failure on the very first probe means
      // no per-index line ever prints, which reads as total silence.
      debugPrint('[camera] probe failed: $error\n$stack');
      if (_disposed) return;
      state = CameraFeedState(
        status: CameraFeedStatus.failed,
        error: '$error',
      );
      return;
    }
    if (_disposed) return;

    if (found.isEmpty) {
      state = const CameraFeedState(status: CameraFeedStatus.noDevices);
      return;
    }

    state = CameraFeedState(status: CameraFeedStatus.idle, devices: found);

    if (!autoOpen) return;
    final remembered = ref.read(unitPrefsProvider).cameraDeviceName;
    for (final device in found) {
      if (device.name == remembered) {
        await select(device);
        return;
      }
    }
  }

  /// Opens each candidate index just long enough to learn whether a camera
  /// answers on it, and at what size.
  Future<List<CameraDevice>> _probe(List<String> names) async {
    final found = <CameraDevice>[];
    final limit = names.length + _probeOvershoot;
    for (var index = 0; index < limit; index++) {
      final capture = cv.VideoCapture.fromDevice(index, apiPreference: _backend);
      if (!capture.isOpened) {
        capture.dispose();
        continue;
      }
      final width = capture.get(_propFrameWidth).round();
      final height = capture.get(_propFrameHeight).round();
      capture.release();
      capture.dispose();

      found.add(
        CameraDevice(
          index: index,
          name: index < names.length ? names[index] : 'Camera $index',
          width: width,
          height: height,
        ),
      );
      debugPrint('[camera] probe $index: ${found.last.name} '
          '${found.last.resolutionLabel}');
    }
    return found;
  }

  CaptureMode _preferredMode() {
    final prefs = ref.read(unitPrefsProvider);
    return CaptureMode(prefs.cameraWidth, prefs.cameraHeight);
  }

  /// Requests a different capture mode, reopening the live camera on it.
  Future<void> setMode(CaptureMode mode) async {
    if (_disposed) return;
    ref
        .read(unitPrefsProvider.notifier)
        .setCameraMode(mode.width, mode.height);
    final device = state.selected;
    if (device == null || _capture == null) return;
    await select(device);
  }

  /// Opens [device] and starts pumping frames, replacing whatever was open.
  Future<void> select(CameraDevice device) async {
    if (_disposed) return;
    final generation = ++_openGeneration;

    _releaseCapture();
    if (_disposed || generation != _openGeneration) return;

    state = CameraFeedState(
      status: CameraFeedStatus.opening,
      devices: state.devices,
      selected: device,
    );

    final cv.VideoCapture capture;
    try {
      capture = cv.VideoCapture.fromDevice(device.index, apiPreference: _backend);
    } catch (error) {
      _fail(device, '$error', generation);
      return;
    }

    if (!capture.isOpened) {
      capture.dispose();
      _fail(
        device,
        'The device is attached but refused to open. Another app may be '
        'holding it.',
        generation,
      );
      return;
    }

    if (_disposed || generation != _openGeneration) {
      capture.release();
      capture.dispose();
      return;
    }

    // VideoCapture opens a device on its *default* mode, not its best one,
    // so a mode has to be asked for explicitly.
    final requested = _preferredMode();
    if (!requested.isAuto) {
      // FOURCC before size: DirectShow settles the pixel format first, and a
      // large frame requested in an uncompressed format is granted as a
      // slideshow rather than refused.
      capture.set(_propFourcc, _fourccMjpg.toDouble());
      capture.set(_propFrameWidth, requested.width.toDouble());
      capture.set(_propFrameHeight, requested.height.toDouble());
    }

    // What the driver actually granted, which may be the nearest mode it has
    // rather than the one asked for. Note DirectShow reports 0 for fps; the
    // rate a clip actually achieves is the number worth trusting.
    final width = capture.get(_propFrameWidth).round();
    final height = capture.get(_propFrameHeight).round();
    final fps = capture.get(_propFps);
    debugPrint(
      '[camera] opened "${device.name}" index ${device.index} — '
      'requested ${requested.label}, got ${width}x$height '
      '@ ${fps.toStringAsFixed(1)}fps',
    );

    // Carry the granted size on the device so the UI shows the truth rather
    // than the probe's guess or the request.
    device = CameraDevice(
      index: device.index,
      name: device.name,
      width: width,
      height: height,
    );

    _capture = capture;
    ref.read(impactClipProvider.notifier).setArmed(true);
    state = CameraFeedState(
      status: CameraFeedStatus.streaming,
      devices: state.devices,
      selected: device,
      frames: _frame,
    );
    ref.read(unitPrefsProvider.notifier).setCameraDeviceName(device.name);

    unawaited(_pump(capture, device, generation));
  }

  /// Reads frames until the camera is replaced or closed. `readAsync` hands
  /// the blocking grab to the native side, so this loop never stalls the UI
  /// isolate despite having no explicit throttle — the camera's own frame
  /// rate paces it.
  Future<void> _pump(
    cv.VideoCapture capture,
    CameraDevice device,
    int generation,
  ) async {
    var consecutiveFailures = 0;
    while (!_disposed &&
        generation == _openGeneration &&
        identical(_capture, capture)) {
      final (ok, frame) = await capture.readAsync();
      if (_disposed || generation != _openGeneration) {
        frame.dispose();
        return;
      }
      if (!ok || frame.isEmpty) {
        frame.dispose();
        // A dropped frame now and then is normal; a run of them means the
        // camera has gone away, most often unplugged mid-session.
        if (++consecutiveFailures >= 30) {
          _fail(device, 'The camera stopped sending frames.', generation);
          _releaseCapture();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        continue;
      }
      consecutiveFailures = 0;

      try {
        // Buffer before painting: the clip is the thing that can't be
        // recovered if this turn of the loop runs late, whereas a preview
        // frame arriving a few milliseconds behind is invisible.
        ref.read(impactClipProvider.notifier).offer(frame);
        // Converting and uploading a frame nobody is looking at is pure
        // waste, and it was competing with clip playback for the same
        // isolate. Buffering carries on regardless, so a shot hit while
        // reviewing is still caught.
        if (!_previewPaused) await _publish(frame);
      } finally {
        frame.dispose();
      }

      // Hand the event loop a turn, every iteration, unconditionally.
      //
      // `await` on its own does not guarantee one: a future that is already
      // complete — which readAsync is whenever the driver has a frame queued
      // — resumes through the *microtask* queue, and microtasks are drained
      // to exhaustion before any timer, gesture or frame callback runs. The
      // loop then spins on microtasks with the UI locked out entirely.
      //
      // Until now `_publish` hid this: decodeImageFromPixels completes on a
      // real event-loop callback, so painting the preview was accidentally
      // the thing keeping the app responsive. Pausing the preview during clip
      // review removed that, and the tab froze solid. A zero-duration delay
      // is a Timer, which is an event-loop task, so this yield is real.
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Turns one BGR frame into a `ui.Image` and hands it to the widget tree.
  Future<void> _publish(cv.Mat bgr) async {
    // Mat.data is a view onto native memory, not a copy, so the conversion
    // result has to outlive the upload — hence the dispose after the await.
    final rgba = cv.cvtColor(bgr, _colorBgr2Rgba);
    try {
      final image = await _decodeRgba(rgba.data, rgba.cols, rgba.rows);
      if (_disposed) {
        image.dispose();
        return;
      }
      final previous = _frame.value;
      _frame.value = image;
      _retired?.dispose();
      _retired = previous;
    } finally {
      rgba.dispose();
    }
  }

  static Future<ui.Image> _decodeRgba(Uint8List pixels, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Stops converting and uploading preview frames while something else is
  /// on screen. The camera keeps running and the ring keeps filling.
  void setPreviewPaused(bool paused) {
    if (_disposed || paused == _previewPaused) return;
    _previewPaused = paused;
  }

  /// Closes the camera and forgets the choice, so the tab doesn't silently
  /// reopen it next time.
  Future<void> stop() async {
    _openGeneration++;
    _releaseCapture();
    if (_disposed) return;
    state = CameraFeedState(
      status: CameraFeedStatus.idle,
      devices: state.devices,
    );
    ref.read(unitPrefsProvider.notifier).setCameraDeviceName(null);
  }

  void _fail(CameraDevice device, String error, int generation) {
    if (_disposed || generation != _openGeneration) return;
    state = CameraFeedState(
      status: CameraFeedStatus.failed,
      devices: state.devices,
      selected: device,
      error: error,
    );
  }

  void _releaseCapture() {
    final capture = _capture;
    _capture = null;
    // No feed, nothing to buffer — and the half-filled ring is stale the
    // moment the camera stops.
    if (!_disposed) ref.read(impactClipProvider.notifier).setArmed(false);
    capture?.release();
    capture?.dispose();
    _frame.value = null;
    _retired?.dispose();
    _retired = null;
  }
}
