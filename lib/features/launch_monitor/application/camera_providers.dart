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

/// `cv::COLOR_BGR2RGBA` — OpenCV decodes to BGR; Flutter uploads RGBA.
const _colorBgr2Rgba = 2;

/// How many device indices to look past the number the OS named, in case
/// OpenCV's enumeration order runs longer than Media Foundation's.
const _probeOvershoot = 2;

int get _backend =>
    defaultTargetPlatform == TargetPlatform.windows ? _capDshow : _capAny;

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

    // What the driver actually gave us, which is not what the camera can do:
    // VideoCapture opens a device on its *default* mode, and for most UVC
    // cameras that is 640x480 no matter what the sensor is capable of.
    // Requesting a mode is a prerequisite for the high-speed work, and until
    // then this line is the only place the real capture size is visible.
    final width = capture.get(_propFrameWidth).round();
    final height = capture.get(_propFrameHeight).round();
    final fps = capture.get(_propFps);
    debugPrint(
      '[camera] opened "${device.name}" index ${device.index} — '
      '${width}x$height @ ${fps.toStringAsFixed(1)}fps',
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
        await _publish(frame);
      } finally {
        frame.dispose();
      }
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
