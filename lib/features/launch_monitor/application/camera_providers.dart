/// Live camera feed for the desktop Camera tab, captured through OpenCV.
///
/// **Why not the `camera` plugin.** `camera_windows` drives Media Foundation,
/// and on a plain UVC webcam its media-type search comes up empty and fails
/// with "Failed to initialize video preview" at every resolution preset —
/// flutter/flutter#140014, open and unresolved. It also reverted frame
/// streaming in 0.2.6, so it could never expose the frames the impact-clip
/// capture is built on. OpenCV's VideoCapture takes the DirectShow path and
/// hands us decoded frames in Dart.
///
/// **Where the work happens.** Capture runs in a dedicated isolate (see
/// camera_capture_worker.dart): on Flutter Windows the main isolate executes
/// on the platform thread — the thread that pumps mouse input — so the
/// capture loop's blocking work ran directly against click handling and the
/// tab lagged even at rest. This side owns no OpenCV handle while streaming;
/// it receives encoded frames for the ring buffer and throttled RGBA buffers
/// for the preview, both cheap to accept.
///
/// `camera`'s `availableCameras()` is still used, for device *names* only —
/// OpenCV addresses cameras by bare integer index and has no enumeration API.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show availableCameras;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'package:omni_sniffer/features/launch_monitor/application/camera_capture_worker.dart';
import 'package:omni_sniffer/features/launch_monitor/application/impact_clip_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/services/event_loop_watchdog.dart';

/// How many device indices to look past the number the OS named, in case
/// OpenCV's enumeration order runs longer than Media Foundation's.
const _probeOvershoot = 2;

/// Shortest gap between preview buffers. The difference between a 30fps and
/// a 15fps preview of a hitting mat is imperceptible; the saved conversions
/// are not.
const _previewInterval = Duration(milliseconds: 66);

int get _backend =>
    defaultTargetPlatform == TargetPlatform.windows ? capDshow : capAny;

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

  /// Frame size last seen from this camera. Zero when the driver declined to
  /// say before a frame was pulled.
  final int width;
  final int height;

  const CameraDevice({
    required this.index,
    required this.name,
    this.width = 0,
    this.height = 0,
  });

  /// `1920×1080`, or empty when nothing is known.
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
  /// listenable rather than part of this state: routing frames through
  /// provider state would rebuild every watcher of the tab per frame to
  /// change one picture.
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

// ── Worker link ──────────────────────────────────────────────────────────────

/// One spawned capture worker and the plumbing to talk to it.
class _WorkerLink {
  final int generation;
  final ReceivePort fromWorker;
  Isolate? isolate;
  SendPort? commands;

  _WorkerLink(this.generation, this.fromWorker);

  void send(Map<String, Object?> command) => commands?.send(command);

  /// Ask nicely, then make sure. The kill is a backstop for a worker wedged
  /// inside a native call where the stop command cannot be heard.
  void shutdown() {
    send(const {'cmd': 'stop'});
    final doomed = isolate;
    isolate = null;
    if (doomed != null) {
      Timer(const Duration(seconds: 2), () {
        doomed.kill(priority: Isolate.immediate);
      });
    }
    Timer(const Duration(seconds: 3), fromWorker.close);
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

final cameraFeedProvider =
    NotifierProvider<CameraFeedNotifier, CameraFeedState>(
      CameraFeedNotifier.new,
    );

class CameraFeedNotifier extends Notifier<CameraFeedState> {
  _WorkerLink? _link;
  bool _disposed = false;
  bool _previewPaused = false;

  final ValueNotifier<ui.Image?> _frame = ValueNotifier<ui.Image?>(null);

  /// The frame one behind the one on screen — freed only when its
  /// replacement's replacement lands, so the painted image is never disposed.
  ui.Image? _retired;

  /// Drops preview buffers that arrive while one is still uploading, instead
  /// of queueing a backlog.
  bool _uploadBusy = false;

  /// Guards against a slow spawn finishing after the user picked a different
  /// camera — the stale worker must not claim the feed.
  int _openGeneration = 0;

  final _watchdog = EventLoopWatchdog('ui');

  @override
  CameraFeedState build() {
    ref.onDispose(() {
      _disposed = true;
      _openGeneration++;
      _watchdog.stop();
      _link?.shutdown();
      _link = null;
      _frame.value?.dispose();
      _retired?.dispose();
      _frame.dispose();
    });
    return const CameraFeedState();
  }

  /// Finds attached cameras. OpenCV has no enumeration call, so this asks the
  /// OS for names and then confirms each index by opening it — the only way
  /// to know an index actually yields a camera.
  Future<void> refreshDevices({bool autoOpen = true}) async {
    if (_disposed) return;
    if (_link != null) return; // Already streaming; nothing to re-probe.

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
      state = CameraFeedState(status: CameraFeedStatus.failed, error: '$error');
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
  /// answers on it, and at what size. Runs on the UI thread, but only during
  /// an explicit scan — never while a feed is live.
  Future<List<CameraDevice>> _probe(List<String> names) async {
    final found = <CameraDevice>[];
    final limit = names.length + _probeOvershoot;
    for (var index = 0; index < limit; index++) {
      final capture = cv.VideoCapture.fromDevice(
        index,
        apiPreference: _backend,
      );
      if (!capture.isOpened) {
        capture.dispose();
        continue;
      }
      final width = capture.get(propFrameWidth).round();
      final height = capture.get(propFrameHeight).round();
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
      debugPrint(
        '[camera] probe $index: ${found.last.name} '
        '${found.last.resolutionLabel}',
      );
      // Let input and paint through between the blocking opens.
      await Future<void>.delayed(Duration.zero);
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
    if (device == null || _link == null) return;
    await select(device);
  }

  /// Spawns a capture worker for [device], replacing whatever was running.
  Future<void> select(CameraDevice device) async {
    if (_disposed) return;
    final generation = ++_openGeneration;

    _releaseWorker();

    state = CameraFeedState(
      status: CameraFeedStatus.opening,
      devices: state.devices,
      selected: device,
    );

    final requested = _preferredMode();
    final link = _WorkerLink(generation, ReceivePort());
    link.fromWorker.listen(
      (message) => _onWorkerMessage(link, device, requested, message),
    );

    try {
      link.isolate = await Isolate.spawn(
        cameraWorkerMain,
        CameraWorkerConfig(
          toMain: link.fromWorker.sendPort,
          deviceIndex: device.index,
          apiPreference: _backend,
          requestWidth: requested.width,
          requestHeight: requested.height,
          previewIntervalMs: _previewInterval.inMilliseconds,
        ),
        // Uncaught worker errors arrive on the same port as a List rather
        // than dying silently.
        onError: link.fromWorker.sendPort,
        debugName: 'camera-worker',
      );
    } catch (error) {
      link.fromWorker.close();
      if (_disposed || generation != _openGeneration) return;
      state = CameraFeedState(
        status: CameraFeedStatus.failed,
        devices: state.devices,
        selected: device,
        error: '$error',
      );
      return;
    }

    if (_disposed || generation != _openGeneration) {
      link.shutdown();
      return;
    }
    _link = link;
  }

  void _onWorkerMessage(
    _WorkerLink link,
    CameraDevice device,
    CaptureMode requested,
    Object? message,
  ) {
    if (_disposed) return;
    final stale = link.generation != _openGeneration;

    // An uncaught error inside the worker, forwarded by onError.
    if (message is List && message.length == 2) {
      debugPrint('[camera] worker crashed: ${message[0]}\n${message[1]}');
      if (!stale) {
        _fail(device, '${message[0]}', link.generation);
        _releaseWorker();
      }
      return;
    }
    if (message is! Map) return;

    switch (message['type']) {
      case 'ready':
        link.commands = message['commands'] as SendPort;
        if (stale) {
          // A newer select() won while this worker was spawning.
          link.shutdown();
          return;
        }
        if (_previewPaused) {
          link.send(const {'cmd': 'previewPaused', 'value': true});
        }

      case 'opened':
        if (stale) return;
        final width = message['width'] as int;
        final height = message['height'] as int;
        final fps = message['fps'] as double;
        final fourcc = message['fourcc'] as int? ?? 0;
        debugPrint(
          '[camera] opened "${device.name}" index ${device.index} — '
          'requested ${requested.label}, got ${width}x$height '
          '@ ${fps.toStringAsFixed(1)}fps in ${_fourccName(fourcc)}',
        );
        _watchdog.start();
        ref.read(impactClipProvider.notifier).setArmed(true);
        state = CameraFeedState(
          status: CameraFeedStatus.streaming,
          devices: state.devices,
          // Carry the granted size so the UI shows the truth rather than
          // the probe's guess or the request.
          selected: CameraDevice(
            index: device.index,
            name: device.name,
            width: width,
            height: height,
          ),
          frames: _frame,
        );
        ref.read(unitPrefsProvider.notifier).setCameraDeviceName(device.name);

      case 'frame':
        if (stale) return;
        ref
            .read(impactClipProvider.notifier)
            .offer(
              message['jpeg'] as Uint8List,
              DateTime.fromMicrosecondsSinceEpoch(message['us'] as int),
            );

      case 'preview':
        if (stale || _previewPaused) return;
        unawaited(
          _publishPreview(
            message['rgba'] as Uint8List,
            message['width'] as int,
            message['height'] as int,
          ),
        );

      case 'stats':
        if (stale) return;
        final seconds = message['seconds'] as double;
        final loops = message['loops'] as int;
        final empties = message['emptyReads'] as int? ?? 0;
        double perLoop(Object? us) => (us as int) / loops / 1000;
        debugPrint(
          '[pump] ${(loops / seconds).toStringAsFixed(1)}/s in worker · '
          'read ${perLoop(message['readUs']).toStringAsFixed(1)}ms · '
          'encode ${perLoop(message['encodeUs']).toStringAsFixed(1)}ms · '
          'preview ${((message['previewUs'] as int) / 1000).toStringAsFixed(1)}ms/s · '
          '$empties empty reads · '
          '${_previewPaused ? 'paused' : 'live'}',
        );

      case 'error':
        debugPrint('[camera] worker error: ${message['message']}');
        if (stale) return;
        _fail(device, '${message['message']}', link.generation);
        _releaseWorker();

      case 'stopped':
        link.fromWorker.close();
    }
  }

  /// Uploads one RGBA preview buffer. Buffers that arrive mid-upload are
  /// dropped — for a live view, newest beats complete.
  Future<void> _publishPreview(Uint8List rgba, int width, int height) async {
    if (_uploadBusy) return;
    _uploadBusy = true;
    try {
      final image = await _decodeRgba(rgba, width, height);
      if (_disposed) {
        image.dispose();
        return;
      }
      final previous = _frame.value;
      _frame.value = image;
      _retired?.dispose();
      _retired = previous;
    } finally {
      _uploadBusy = false;
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

  /// Stops converting and sending preview frames while something else is on
  /// screen. The worker keeps capturing and the ring keeps filling.
  void setPreviewPaused(bool paused) {
    if (_disposed || paused == _previewPaused) return;
    _previewPaused = paused;
    _link?.send({'cmd': 'previewPaused', 'value': paused});
  }

  /// Closes the camera and forgets the choice, so the tab doesn't silently
  /// reopen it next time.
  Future<void> stop() async {
    _openGeneration++;
    _releaseWorker();
    if (_disposed) return;
    state = CameraFeedState(
      status: CameraFeedStatus.idle,
      devices: state.devices,
    );
    ref.read(unitPrefsProvider.notifier).setCameraDeviceName(null);
  }

  /// `1196444237` → `MJPG`. Falls back to the raw number for a value that
  /// doesn't decode as four printable characters.
  static String _fourccName(int fourcc) {
    if (fourcc <= 0) return 'unknown format';
    final chars = [
      fourcc & 0xFF,
      (fourcc >> 8) & 0xFF,
      (fourcc >> 16) & 0xFF,
      (fourcc >> 24) & 0xFF,
    ];
    if (chars.any((c) => c < 0x20 || c > 0x7E)) return 'format #$fourcc';
    return String.fromCharCodes(chars);
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

  void _releaseWorker() {
    final link = _link;
    _link = null;
    link?.shutdown();
    _watchdog.stop();
    _frame.value = null;
    _retired?.dispose();
    _retired = null;
    // No feed, nothing to buffer — and the half-filled ring is stale the
    // moment the camera stops.
    if (!_disposed) ref.read(impactClipProvider.notifier).setArmed(false);
  }
}
