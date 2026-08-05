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
/// On macOS the Runner serves the name list over a method channel instead
/// (MainFlutterWindow.swift): the `camera` plugin has no macOS
/// implementation at all. Capture itself is OpenCV on both desktops.
///
/// **iOS is the exception: capture is native AVFoundation** (the
/// NativeCameraController in the Runner's AppDelegate.swift). OpenCV's iOS
/// backend is pinned to 480×360 with no property that raises it, and it
/// dies on any attempt to ask — setting CAP_PROP_FRAME_WIDTH/HEIGHT pushes
/// pixel-buffer size keys into AVCaptureVideoDataOutput.videoSettings,
/// which iOS rejects with an NSInvalidArgumentException nothing on this
/// side can catch. The native module keeps this file's contract — JPEG
/// frames with wall-clock timestamps for the ring buffer, a throttled
/// preview — but picks a real device format, so resolution and rate
/// requests are honoured. The worker-isolate path survives on iOS only as
/// a fallback for a code-pushed Dart side running on a Runner older than
/// the native module, and then only on the camera's default mode.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show availableCameras;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show EventChannel, MethodChannel, MissingPluginException, PlatformException;
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

int get _backend => switch (defaultTargetPlatform) {
      TargetPlatform.windows => capDshow,
      TargetPlatform.macOS || TargetPlatform.iOS => capAvfoundation,
      _ => capAny,
    };

/// The Runner-side AVFoundation device list and permission request (macOS
/// MainFlutterWindow.swift, iOS AppDelegate.swift).
const _appleCameras = MethodChannel('omni_sniffer/apple_cameras');

/// Settles camera authorization before anything opens a device, on the
/// platforms that gate capture behind consent. OpenCV's open never asks —
/// with the decision undetermined it would race the system prompt, fail
/// every index, and report "no cameras" while the dialog is still on
/// screen. True means capture may proceed; false means the user has denied
/// access (now or previously) and opening devices is pointless.
Future<bool> _ensureCameraAccess() async {
  if (defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return true;
  }
  try {
    return await _appleCameras.invokeMethod<bool>('requestCameraAccess') ??
        true;
  } on MissingPluginException {
    // A Runner from before this method existed — code push updates only the
    // Dart side. The old behaviour (open and hope) is the best available.
    return true;
  } on PlatformException catch (error) {
    debugPrint('[camera] permission request failed: ${error.message}');
    return true;
  }
}

/// Device names in index order, from whichever side of the fence can name
/// them on this platform.
Future<List<String>> _deviceNames() async {
  if (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    final names =
        await _appleCameras.invokeListMethod<String>('listCameraNames');
    return names ?? const [];
  }
  return (await availableCameras()).map((d) => d.name).toList();
}

// ── Camera slots ─────────────────────────────────────────────────────────────

/// How many cameras the tab can run at once.
const kCameraSlotCount = 2;

/// Golf's names for the two angles: slot 0 films from behind the ball down
/// the target line, slot 1 faces the golfer.
const kCameraSlotLabels = ['Down the line', 'Face on'];
const kCameraSlotShortLabels = ['DTL', 'FO'];

/// Device indices with a live worker on them right now, shared across slots.
/// The probe must not open these — opening a busy camera fails, which would
/// silently drop the other slot's device from the list — and a slot's picker
/// uses it to warn that a device is already spoken for.
final Map<int, CameraDevice> _liveByIndex = {};

/// One camera operation at a time, app-wide.
///
/// Two probes — or a probe and a worker's open — hitting DirectShow at once
/// is exactly what the two-camera startup did, and the driver's answer was
/// "raised unknown C++ exception" followed by a 38-second wedge. Device
/// opens on these drivers are not concurrency-safe, so every probe and
/// every worker open queues here.
Future<void> _cameraOps = Future<void>.value();

/// Fresh probe results shared across slots. Both panes scan at startup, and
/// without this each scan opens every camera — four opens before a single
/// real one, on drivers that can wedge on any open that goes wrong. A scan
/// from the last few seconds answers the second requester for free; a manual
/// rescan bypasses it.
List<CameraDevice>? _cachedProbe;
DateTime _cachedProbeAt = DateTime.fromMillisecondsSinceEpoch(0);
const _probeCacheLife = Duration(seconds: 10);

Future<T> _serialized<T>(Future<T> Function() action) {
  final result = _cameraOps.then((_) => action());
  // The queue must survive a failed action; errors surface to the caller
  // through `result`, not through the chain.
  _cameraOps = result.then<void>((_) {}, onError: (_) {});
  return result;
}

/// Probe isolate entry. Streams a message per device — 'opening' before the
/// blocking call, 'result' after — so the main isolate always knows exactly
/// which index a wedged driver died on, and can kill this isolate and keep
/// the devices that had already answered. A single opaque run-to-completion
/// probe threw all of that away: one bad driver failed the whole scan with
/// nothing but a TimeoutException.
Future<void> _probeIsolateMain(List<Object?> args) async {
  final toMain = args[0] as SendPort;
  final backend = args[1] as int;
  final limit = args[2] as int;
  final skip = (args[3] as List).cast<int>().toSet();

  for (var index = 0; index < limit; index++) {
    if (skip.contains(index)) continue;
    toMain.send({'type': 'opening', 'index': index});
    final timer = Stopwatch()..start();
    var opened = false;
    var width = 0;
    var height = 0;
    try {
      final capture = cv.VideoCapture.fromDevice(
        index,
        apiPreference: backend,
      );
      opened = capture.isOpened;
      if (opened) {
        width = capture.get(propFrameWidth).round();
        height = capture.get(propFrameHeight).round();
        capture.release();
      }
      capture.dispose();
    } catch (_) {
      // A throwing open is a real answer: not a camera.
    }
    toMain.send({
      'type': 'result',
      'index': index,
      'opened': opened,
      'width': width,
      'height': height,
      'ms': timer.elapsedMilliseconds,
    });
  }
  toMain.send({'type': 'done'});
}

/// Runs the probe isolate, watching its progress. Returns the per-index
/// results plus the index whose open stalled, if one did — that isolate is
/// killed rather than awaited, and everything found before the stall is
/// kept.
Future<(List<Map<String, Object>>, int?)> _runProbeIsolate(
  int backend,
  int limit,
  Set<int> skip,
) async {
  final fromProbe = ReceivePort();
  final results = <Map<String, Object>>[];
  int? openingIndex;
  final done = Completer<int?>();
  Timer? stallTimer;

  // Ten seconds without progress means the current open is wedged. Per open,
  // not for the whole scan, so three slow-but-honest devices don't trip it.
  void arm() {
    stallTimer?.cancel();
    stallTimer = Timer(const Duration(seconds: 10), () {
      if (!done.isCompleted) done.complete(openingIndex ?? -1);
    });
  }

  final sub = fromProbe.listen((message) {
    if (message is! Map) return; // onError Lists land here too; stall covers.
    switch (message['type']) {
      case 'opening':
        openingIndex = message['index'] as int;
        arm();
      case 'result':
        results.add(Map<String, Object>.from(message));
        openingIndex = null;
        arm();
      case 'done':
        if (!done.isCompleted) done.complete(null);
    }
  });

  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      _probeIsolateMain,
      [fromProbe.sendPort, backend, limit, skip.toList()],
      onError: fromProbe.sendPort,
      debugName: 'camera-probe',
    );
    arm();
    final wedged = await done.future;
    if (wedged != null) isolate.kill(priority: Isolate.immediate);
    return (results, wedged);
  } finally {
    stallTimer?.cancel();
    await sub.cancel();
    fromProbe.close();
  }
}

// ── Capture mode ─────────────────────────────────────────────────────────────

/// A frame size to ask the camera for.
@immutable
class CaptureMode {
  final int width;
  final int height;

  /// Requested frame rate. Zero means "no preference", which the worker
  /// treats as 30 alongside a size request — the value that first pulled
  /// DirectShow off its slow uncompressed default. A rate the camera cannot
  /// do snaps down; the clip's measured fps stays the number to trust.
  final int fps;

  const CaptureMode(this.width, this.height, [this.fps = 0]);

  /// Take whatever the camera opens on. For most UVC devices that is 640x480,
  /// whatever the sensor is capable of.
  static const auto = CaptureMode(0, 0);

  bool get isAuto => width <= 0 || height <= 0;

  String get label {
    if (isAuto) return 'Camera default';
    return fps > 0 ? '$width×$height @ ${fps}fps' : '$width×$height';
  }

  /// Offered in the picker. A camera that cannot do the requested size or
  /// rate snaps to its nearest supported mode rather than failing, so an
  /// over-ambitious choice costs nothing but less than was asked for.
  static const candidates = [
    auto,
    CaptureMode(640, 480),
    CaptureMode(640, 480, 60),
    CaptureMode(640, 480, 120),
    CaptureMode(1280, 720),
    CaptureMode(1280, 720, 60),
    CaptureMode(1280, 720, 120),
    CaptureMode(1920, 1080),
    CaptureMode(1920, 1080, 60),
  ];

  @override
  bool operator ==(Object other) =>
      other is CaptureMode &&
      other.width == width &&
      other.height == height &&
      other.fps == fps;

  @override
  int get hashCode => Object.hash(width, height, fps);
}

// ── Native capture (iOS) ─────────────────────────────────────────────────────

/// The Runner's native AVFoundation capture module (AppDelegate.swift).
const _nativeCamera = MethodChannel('omni_sniffer/native_camera');

/// Frames and errors from every native feed, tagged by slot. One broadcast
/// stream shared by both notifiers; each filters for its own slot.
const _nativeFrames = EventChannel('omni_sniffer/native_camera/frames');
Stream<Object?>? _nativeFrameBroadcast;
Stream<Object?> get _nativeFrameEvents =>
    _nativeFrameBroadcast ??= _nativeFrames.receiveBroadcastStream();

/// Set when the native channel turns out not to exist at runtime: a
/// code-pushed Dart side running on a Runner built before the module.
/// From then on this session uses the OpenCV worker fallback.
bool _nativeCaptureMissing = false;

bool get _useNativeCapture =>
    !_nativeCaptureMissing &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS;

// ── Devices ──────────────────────────────────────────────────────────────────

@immutable
class CameraDevice {
  /// The index OpenCV opens this camera by. Under native capture it is the
  /// device's position in the scan, kept so the cross-slot registry and the
  /// UI treat both backends identically.
  final int index;

  /// The OS's name for it, or `Camera <index>` when enumeration gave nothing.
  final String name;

  /// AVFoundation's stable identifier, set only under native capture —
  /// that backend opens devices by this rather than by index.
  final String? uniqueId;

  /// Frame size last seen from this camera. Zero when the driver declined to
  /// say before a frame was pulled.
  final int width;
  final int height;

  const CameraDevice({
    required this.index,
    required this.name,
    this.uniqueId,
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

  /// Completes when the worker's open has resolved either way — the device
  /// answered, errored, or the worker died. Holding the camera-ops queue on
  /// this is what keeps a probe from hitting DirectShow mid-open.
  final Completer<void> settled = Completer<void>();

  _WorkerLink(this.generation, this.fromWorker);

  void markSettled() {
    if (!settled.isCompleted) settled.complete();
  }

  void send(Map<String, Object?> command) => commands?.send(command);

  /// Ask nicely, then make sure. The kill is a backstop for a worker wedged
  /// inside a native call where the stop command cannot be heard.
  void shutdown() {
    markSettled();
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
    NotifierProvider.family<CameraFeedNotifier, CameraFeedState, int>(
      CameraFeedNotifier.new,
    );

class CameraFeedNotifier extends FamilyNotifier<CameraFeedState, int> {
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

  /// Device index this slot is currently streaming, for the shared registry.
  int? _liveIndex;

  /// Native-capture state: the event subscription for this slot's frames,
  /// whether a native feed is live, and the last preview decode's time —
  /// the native path throttles preview on this side, where the worker path
  /// throttles in the worker.
  StreamSubscription<Object?>? _nativeSub;
  bool _nativeActive = false;
  DateTime _lastNativePreview = DateTime.fromMillisecondsSinceEpoch(0);

  late final _watchdog = EventLoopWatchdog('ui-cam$slot');

  /// Which camera slot this instance drives.
  int get slot => arg;

  @override
  CameraFeedState build(int arg) {
    ref.onDispose(() {
      _disposed = true;
      _openGeneration++;
      _watchdog.stop();
      _link?.shutdown();
      _link = null;
      _nativeSub?.cancel();
      _nativeSub = null;
      if (_nativeActive) {
        _nativeActive = false;
        unawaited(_nativeCamera.invokeMethod<void>('stop', {'slot': arg}));
      }
      _frame.value?.dispose();
      _retired?.dispose();
      _frame.dispose();
    });
    return const CameraFeedState();
  }

  /// Finds attached cameras. OpenCV has no enumeration call, so this asks the
  /// OS for names and then confirms each index by opening it — the only way
  /// to know an index actually yields a camera.
  Future<void> refreshDevices({bool autoOpen = true, bool force = false}) async {
    if (_disposed) return;
    // Already streaming; nothing to re-probe.
    if (_link != null || _nativeActive) return;

    state = CameraFeedState(
      status: CameraFeedStatus.listing,
      devices: state.devices,
      selected: state.selected,
    );

    if (!await _ensureCameraAccess()) {
      if (_disposed) return;
      state = CameraFeedState(
        status: CameraFeedStatus.failed,
        devices: state.devices,
        error: 'Camera access is turned off for this app. Allow it in the '
            'system privacy settings, then rescan.',
      );
      return;
    }
    if (_disposed) return;

    // Native capture enumerates by identifier — no open-to-confirm probe
    // needed, and none of the driver-wedge machinery either.
    List<CameraDevice>? found;
    if (_useNativeCapture) {
      try {
        final raw =
            await _nativeCamera.invokeListMethod<Object?>('listDevices') ??
                const [];
        found = [
          for (final (i, entry) in raw.indexed)
            if (entry is Map)
              CameraDevice(
                index: i,
                name: entry['name'] as String? ?? 'Camera $i',
                uniqueId: entry['id'] as String?,
              ),
        ];
      } on MissingPluginException {
        // Runner predates the native module; the probe below still works,
        // on the camera's default mode.
        _nativeCaptureMissing = true;
      } catch (error) {
        debugPrint('[camera] native device list failed: $error');
        if (_disposed) return;
        state =
            CameraFeedState(status: CameraFeedStatus.failed, error: '$error');
        return;
      }
      if (_disposed) return;
    }

    if (found == null) {
      // Names are a nicety — an unnamed camera is still perfectly openable.
      List<String> names = const [];
      try {
        names = await _deviceNames();
      } catch (error) {
        debugPrint('[camera] name enumeration unavailable: $error');
      }
      if (_disposed) return;

      try {
        found = await _probe(names, force: force);
      } catch (error, stack) {
        // Logged as well as surfaced: a failure on the very first probe means
        // no per-index line ever prints, which reads as total silence.
        debugPrint('[camera] probe failed: $error\n$stack');
        if (_disposed) return;
        state =
            CameraFeedState(status: CameraFeedStatus.failed, error: '$error');
        return;
      }
      if (_disposed) return;
    }

    if (found.isEmpty) {
      state = const CameraFeedState(status: CameraFeedStatus.noDevices);
      return;
    }

    state = CameraFeedState(status: CameraFeedStatus.idle, devices: found);

    if (!autoOpen) return;
    final remembered = _slotPref().deviceName;
    if (remembered.isEmpty) return;
    // Prefer the first name match that is free: two identical cameras share
    // a name, and the match could otherwise be the very device the other
    // slot is streaming — an open guaranteed to fail.
    for (final device in found) {
      if (device.name != remembered) continue;
      if (_liveByIndex.containsKey(device.index)) continue;
      await select(device);
      return;
    }
  }

  CameraSlotPref _slotPref() {
    final slots = ref.read(unitPrefsProvider).cameraSlots;
    return slot < slots.length ? slots[slot] : const CameraSlotPref();
  }

  /// Opens each candidate index just long enough to learn whether a camera
  /// answers on it, and at what size.
  ///
  /// The opens run in a short-lived isolate behind the camera-ops queue: a
  /// DirectShow open is a blocking native call that can take seconds — or
  /// wedge for half a minute — when another camera is streaming or a driver
  /// is unhappy, and with two slots this scan legitimately runs while the
  /// other slot is live. On the UI thread that was the two-camera freeze.
  Future<List<CameraDevice>> _probe(
    List<String> names, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final cached = _cachedProbe;
    if (!force &&
        cached != null &&
        now.difference(_cachedProbeAt) < _probeCacheLife) {
      debugPrint(
        '[camera] probe: reusing the scan from '
        '${now.difference(_cachedProbeAt).inMilliseconds}ms ago',
      );
      return List.of(cached);
    }

    final limit = names.length + _probeOvershoot;
    final live = Map<int, CameraDevice>.of(_liveByIndex);
    final backend = _backend;
    final skip = live.keys.toSet();

    final (results, wedgedIndex) = await _serialized(
      () => _runProbeIsolate(backend, limit, skip),
    );

    if (wedgedIndex != null) {
      debugPrint(
        '[camera] probe stalled '
        '${wedgedIndex >= 0 ? "opening device index $wedgedIndex" : "before its first open"}'
        ' — probe isolate killed, keeping the '
        '${results.length} result(s) it got. That device\'s driver is '
        'wedged: unplug and replug it, on a different USB controller if '
        'both cameras share one.',
      );
    }

    final found = <CameraDevice>[];
    for (var index = 0; index < limit; index++) {
      // A device another slot is streaming can't be opened to probe — and
      // failing to open it would silently drop it from the list, vanishing
      // the very camera that is working. Report what the live feed knows.
      final liveDevice = live[index];
      if (liveDevice != null) {
        found.add(liveDevice);
        debugPrint(
          '[camera] probe $index: ${liveDevice.name} (live on a slot)',
        );
        continue;
      }
      Map<String, Object>? result;
      for (final entry in results) {
        if (entry['index'] == index) {
          result = entry;
          break;
        }
      }
      if (result == null || result['opened'] != true) continue;
      found.add(
        CameraDevice(
          index: index,
          name: index < names.length ? names[index] : 'Camera $index',
          width: result['width'] as int? ?? 0,
          height: result['height'] as int? ?? 0,
        ),
      );
      debugPrint(
        '[camera] probe $index: ${found.last.name} '
        '${found.last.resolutionLabel} in ${result['ms']}ms',
      );
    }

    // A clean scan is worth sharing with the other slot; one that wedged is
    // not — the next requester should look again.
    if (wedgedIndex == null) {
      _cachedProbe = List.of(found);
      _cachedProbeAt = now;
    }

    // A wedge with nothing found at all is worth failing loudly; a wedge
    // after real finds is not — the working camera must stay usable.
    if (found.isEmpty && wedgedIndex != null) {
      throw TimeoutException(
        'The camera scan stalled opening device index $wedgedIndex. '
        'Unplug and replug that camera, then rescan.',
      );
    }
    return found;
  }

  CaptureMode _preferredMode() {
    final pref = _slotPref();
    return CaptureMode(pref.width, pref.height, pref.fps);
  }

  /// Requests a different capture mode, reopening the live camera on it.
  Future<void> setMode(CaptureMode mode) async {
    if (_disposed) return;
    ref
        .read(unitPrefsProvider.notifier)
        .setCameraSlot(
          slot,
          width: mode.width,
          height: mode.height,
          fps: mode.fps,
        );
    final device = state.selected;
    if (device == null || (_link == null && !_nativeActive)) return;
    await select(device);
  }

  /// Spawns a capture worker for [device], replacing whatever was running.
  Future<void> select(CameraDevice device) async {
    if (_disposed) return;

    // The other slot already streams this device. Spawning a worker would
    // only fail after a slow open inside the driver — fail fast instead.
    if (_liveByIndex.containsKey(device.index) && _liveIndex != device.index) {
      debugPrint(
        '[camera] slot $slot refused index ${device.index}: held by the '
        'other slot',
      );
      state = CameraFeedState(
        status: CameraFeedStatus.failed,
        devices: state.devices,
        selected: device,
        error: 'This camera is already streaming on the other slot. Pick a '
            'different device for this angle.',
      );
      return;
    }

    final generation = ++_openGeneration;
    _releaseWorker();

    state = CameraFeedState(
      status: CameraFeedStatus.opening,
      devices: state.devices,
      selected: device,
    );

    // Behind the ops queue, held until the device answers: DirectShow must
    // never see this open and a probe (or the other slot's open) at once.
    // The native path queues too — its opens are quick, and one open at a
    // time is a property worth keeping uniform.
    await _serialized(
      () => _useNativeCapture
          ? _startNative(device, generation)
          : _spawnWorker(device, generation),
    );
  }

  /// Opens [device] through the Runner's native capture module and wires
  /// its frames into the same places the worker's messages go: every frame
  /// to the impact-clip ring, a throttled decode to the live preview.
  Future<void> _startNative(CameraDevice device, int generation) async {
    if (_disposed || generation != _openGeneration) return;

    // Same recheck as the worker path, for the same startup race.
    if (_liveByIndex.containsKey(device.index) && _liveIndex != device.index) {
      debugPrint(
        '[camera] slot $slot refused index ${device.index} at open time: '
        'held by the other slot',
      );
      state = CameraFeedState(
        status: CameraFeedStatus.failed,
        devices: state.devices,
        selected: device,
        error: 'This camera is already streaming on the other slot. Pick a '
            'different device for this angle.',
      );
      return;
    }

    debugPrint(
      '[camera] slot $slot opening "${device.name}" natively '
      '(${device.uniqueId ?? "no id"})',
    );
    final requested = _preferredMode();

    // Subscribed before start so the first frames land, not vanish.
    await _nativeSub?.cancel();
    _nativeSub = _nativeFrameEvents.listen(_onNativeEvent);

    Map<String, Object?>? granted;
    try {
      granted = await _nativeCamera.invokeMapMethod<String, Object?>('start', {
        'slot': slot,
        'deviceId': device.uniqueId ?? '',
        'width': requested.width,
        'height': requested.height,
        'fps': requested.fps,
        'rotation': _slotPref().rotationQuarterTurns,
      });
    } on MissingPluginException {
      // Runner predates the native module. The worker fallback opens the
      // same device by index — its scan order matches listDevices' only
      // roughly, but this path exists for one code-push generation.
      _nativeCaptureMissing = true;
      await _nativeSub?.cancel();
      _nativeSub = null;
      return _spawnWorker(device, generation);
    } on PlatformException catch (error) {
      await _nativeSub?.cancel();
      _nativeSub = null;
      if (_disposed || generation != _openGeneration) return;
      _fail(device, error.message ?? '$error', generation);
      return;
    }

    if (_disposed || generation != _openGeneration) {
      await _nativeSub?.cancel();
      _nativeSub = null;
      unawaited(_nativeCamera.invokeMethod<void>('stop', {'slot': slot}));
      return;
    }

    _nativeActive = true;
    final width = (granted?['width'] as num?)?.toInt() ?? 0;
    final height = (granted?['height'] as num?)?.toInt() ?? 0;
    final fps = (granted?['fps'] as num?)?.toDouble() ?? 0;
    debugPrint(
      '[camera] slot $slot opened "${device.name}" natively — requested '
      '${requested.label}, got ${width}x$height @ ${fps.toStringAsFixed(1)}fps',
    );
    _watchdog.start();
    ref.read(impactClipProvider.notifier).setArmed(slot, true);
    final grantedDevice = CameraDevice(
      index: device.index,
      name: device.name,
      uniqueId: device.uniqueId,
      width: width,
      height: height,
    );
    _liveByIndex[device.index] = grantedDevice;
    _liveIndex = device.index;
    state = CameraFeedState(
      status: CameraFeedStatus.streaming,
      devices: state.devices,
      selected: grantedDevice,
      frames: _frame,
    );
    ref
        .read(unitPrefsProvider.notifier)
        .setCameraSlot(slot, deviceName: device.name);
  }

  /// One event off the shared native stream. Frames for other slots pass
  /// through untouched.
  void _onNativeEvent(Object? message) {
    if (_disposed || message is! Map) return;
    if (message['slot'] != slot) return;

    switch (message['type']) {
      case 'frame':
        final jpeg = message['jpeg'] as Uint8List;
        ref.read(impactClipProvider.notifier).offer(
              slot,
              jpeg,
              DateTime.fromMicrosecondsSinceEpoch(message['us'] as int),
            );
        if (_previewPaused) return;
        final now = DateTime.now();
        if (now.difference(_lastNativePreview) >= _previewInterval) {
          _lastNativePreview = now;
          unawaited(_publishJpegPreview(jpeg));
        }

      case 'error':
        debugPrint('[camera] slot $slot native error: ${message['message']}');
        final device = state.selected;
        if (device != null) {
          _fail(device, '${message['message']}', _openGeneration);
        }
        _releaseWorker();
    }
  }

  /// Decodes one JPEG for the preview. Same drop-if-busy policy as the RGBA
  /// path: for a live view, newest beats complete.
  Future<void> _publishJpegPreview(Uint8List jpeg) async {
    if (_uploadBusy) return;
    _uploadBusy = true;
    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      final frameInfo = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frameInfo.image.dispose();
        return;
      }
      final previous = _frame.value;
      _frame.value = frameInfo.image;
      _retired?.dispose();
      _retired = previous;
    } catch (error) {
      debugPrint('[camera] preview decode failed: $error');
    } finally {
      _uploadBusy = false;
    }
  }

  Future<void> _spawnWorker(CameraDevice device, int generation) async {
    if (_disposed || generation != _openGeneration) return;

    // Re-checked here, inside the serialized section — not only in select().
    // The early check races: two auto-opens both pass it before either has
    // opened and registered, and the queue then executes both. That is
    // exactly how both slots opened the same camera at startup, the driver
    // let two graphs share it, and the first slot starved to death at 1fps.
    // By this point the previous open has fully settled, so the registry
    // tells the truth.
    if (_liveByIndex.containsKey(device.index) && _liveIndex != device.index) {
      debugPrint(
        '[camera] slot $slot refused index ${device.index} at open time: '
        'held by the other slot',
      );
      state = CameraFeedState(
        status: CameraFeedStatus.failed,
        devices: state.devices,
        selected: device,
        error: 'This camera is already streaming on the other slot. Pick a '
            'different device for this angle.',
      );
      return;
    }

    debugPrint(
      '[camera] slot $slot opening "${device.name}" index ${device.index}',
    );
    // On iOS this worker is only ever the fallback for a Runner without the
    // native module, and there a size request is fatal: OpenCV's backend
    // pushes pixel-buffer size keys into videoSettings, which iOS rejects
    // with an uncatchable NSInvalidArgumentException. Default mode only.
    final requested = defaultTargetPlatform == TargetPlatform.iOS
        ? CaptureMode.auto
        : _preferredMode();
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
          requestFps: requested.fps,
          previewIntervalMs: _previewInterval.inMilliseconds,
          rotationQuarterTurns: _slotPref().rotationQuarterTurns,
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

    // Hold the queue until the worker reports opened, errored or died, with
    // a ceiling so a wedged driver can't block camera operations forever.
    await link.settled.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {},
    );
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
      link.markSettled();
      debugPrint(
        '[camera] slot $slot worker crashed: ${message[0]}\n${message[1]}',
      );
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
        link.markSettled();
        if (stale) return;
        final width = message['width'] as int;
        final height = message['height'] as int;
        final fps = message['fps'] as double;
        final fourcc = message['fourcc'] as int? ?? 0;
        debugPrint(
          '[camera] slot $slot opened "${device.name}" index ${device.index} '
          '— requested ${requested.label}, got ${width}x$height '
          '@ ${fps.toStringAsFixed(1)}fps in ${_fourccName(fourcc)}',
        );
        _watchdog.start();
        ref.read(impactClipProvider.notifier).setArmed(slot, true);
        // Carry the granted size so the UI shows the truth rather than the
        // probe's guess or the request.
        final granted = CameraDevice(
          index: device.index,
          name: device.name,
          width: width,
          height: height,
        );
        _liveByIndex[device.index] = granted;
        _liveIndex = device.index;
        state = CameraFeedState(
          status: CameraFeedStatus.streaming,
          devices: state.devices,
          selected: granted,
          frames: _frame,
        );
        ref
            .read(unitPrefsProvider.notifier)
            .setCameraSlot(slot, deviceName: device.name);

      case 'frame':
        if (stale) return;
        ref
            .read(impactClipProvider.notifier)
            .offer(
              slot,
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
          '[pump:$slot] ${(loops / seconds).toStringAsFixed(1)}/s in worker · '
          'read ${perLoop(message['readUs']).toStringAsFixed(1)}ms · '
          'encode ${perLoop(message['encodeUs']).toStringAsFixed(1)}ms · '
          'preview ${((message['previewUs'] as int) / 1000).toStringAsFixed(1)}ms/s · '
          '$empties empty reads · '
          '${_previewPaused ? 'paused' : 'live'}',
        );

      case 'error':
        link.markSettled();
        debugPrint('[camera] slot $slot worker error: ${message['message']}');
        if (stale) return;
        _fail(device, '${message['message']}', link.generation);
        _releaseWorker();

      case 'stopped':
        link.markSettled();
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

  /// Applies [quarterTurns] clockwise to the live feed and remembers it.
  /// Takes effect on the very next frame — no reopen — but the ring buffer
  /// restarts, because a clip mixing two orientations would hand the export
  /// writer frames of two different sizes.
  Future<void> setRotation(int quarterTurns) async {
    if (_disposed) return;
    final turns = quarterTurns % 4;
    ref
        .read(unitPrefsProvider.notifier)
        .setCameraSlot(slot, rotationQuarterTurns: turns);
    if (_link == null && !_nativeActive) return;
    if (_nativeActive) {
      unawaited(
        _nativeCamera.invokeMethod<void>('setRotation', {
          'slot': slot,
          'turns': turns,
        }),
      );
    } else {
      _link?.send({'cmd': 'rotation', 'value': turns});
    }
    final recorder = ref.read(impactClipProvider.notifier);
    recorder.setArmed(slot, false);
    recorder.setArmed(slot, true);
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
    ref.read(unitPrefsProvider.notifier).setCameraSlot(slot, deviceName: '');
  }

  /// Closes the camera but keeps the remembered choice. Used when the two
  /// slots trade devices: [stop]'s forget-the-choice would erase the very
  /// preferences being swapped.
  Future<void> halt() async {
    _openGeneration++;
    _releaseWorker();
    if (_disposed) return;
    state = CameraFeedState(
      status: CameraFeedStatus.idle,
      devices: state.devices,
    );
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
    final sub = _nativeSub;
    _nativeSub = null;
    unawaited(sub?.cancel());
    if (_nativeActive) {
      _nativeActive = false;
      unawaited(_nativeCamera.invokeMethod<void>('stop', {'slot': slot}));
    }
    _watchdog.stop();
    final index = _liveIndex;
    _liveIndex = null;
    if (index != null) _liveByIndex.remove(index);
    _frame.value = null;
    _retired?.dispose();
    _retired = null;
    // No feed, nothing to buffer — and the half-filled ring is stale the
    // moment the camera stops.
    if (!_disposed) ref.read(impactClipProvider.notifier).setArmed(slot, false);
  }
}
