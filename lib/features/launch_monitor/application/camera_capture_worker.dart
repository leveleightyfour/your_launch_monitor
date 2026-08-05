/// The camera capture loop, run in its own isolate.
///
/// On Flutter Windows the main Dart isolate executes on the platform thread —
/// the thread that also pumps Win32 input messages. Capture ran there first,
/// and every millisecond of its blocking work (the JPEG encode, the colour
/// conversion, whatever DirectShow does inside a read) was taken directly out
/// of mouse and keyboard handling; the tab lagged at rest and locked up under
/// any extra load. Moving the whole loop here leaves the UI thread with
/// nothing but cheap message handling.
///
/// The worker owns the `VideoCapture` outright — OpenCV handles cannot cross
/// isolates. It sends every captured frame as an encoded JPEG (the ring
/// buffer's storage format) plus, at a throttled rate, an RGBA buffer for the
/// live preview. DirectShow's COM objects are created on this isolate's
/// thread too, keeping them off the input thread entirely.
///
/// This file must stay importable by an isolate entry point: dart:isolate,
/// dart:typed_data and OpenCV only — no Flutter imports.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

// ── OpenCV constants ─────────────────────────────────────────────────────────
//
// Given by value rather than by binding name. These are fixed in OpenCV's own
// headers (videoio.hpp, imgproc.hpp) and so are stable across binding
// versions and renames, which the Dart-side names are not.

/// `cv::CAP_ANY` — let OpenCV choose the backend.
const capAny = 0;

/// `cv::CAP_DSHOW` — DirectShow. Named explicitly on Windows because the
/// default would pick Media Foundation, which is the stack that fails.
const capDshow = 700;

/// `cv::CAP_AVFOUNDATION` — the native capture stack on macOS and iOS. It is
/// the only camera backend in an Apple OpenCV build, but naming it keeps the
/// backend in play a statement rather than a guess, as CAP_DSHOW does on
/// Windows.
const capAvfoundation = 1200;

const propFrameWidth = 3; // cv::CAP_PROP_FRAME_WIDTH
const propFrameHeight = 4; // cv::CAP_PROP_FRAME_HEIGHT
const propFps = 5; // cv::CAP_PROP_FPS
const propFourcc = 6; // cv::CAP_PROP_FOURCC

/// MJPG as a FOURCC integer: 'M' | 'J'<<8 | 'P'<<16 | 'G'<<24.
///
/// Asking for this matters more than the resolution does. Uncompressed YUY2
/// saturates USB long before 1080p, so a camera asked for a large frame in
/// its default format hands back a slideshow rather than refusing.
const fourccMjpg = 1196444237;

/// `cv::COLOR_BGR2RGBA` — OpenCV decodes to BGR; Flutter uploads RGBA.
const colorBgr2Rgba = 2;

/// `cv::ROTATE_*` codes, indexed by clockwise quarter turns minus one.
const _rotateCodes = [
  0, // ROTATE_90_CLOCKWISE
  1, // ROTATE_180
  2, // ROTATE_90_COUNTERCLOCKWISE
];

// ── Spawn configuration ──────────────────────────────────────────────────────

/// Everything the worker needs, all of it sendable across an isolate spawn.
class CameraWorkerConfig {
  final SendPort toMain;
  final int deviceIndex;
  final int apiPreference;

  /// Requested capture size; zero means leave the camera on its default.
  final int requestWidth;
  final int requestHeight;

  /// Requested frame rate; zero falls back to 30 alongside a size request.
  final int requestFps;

  /// Shortest gap between preview buffers sent to the UI.
  final int previewIntervalMs;

  /// Clockwise quarter turns applied to every frame before it leaves the
  /// worker, so preview, ring buffer and exports all agree on orientation.
  final int rotationQuarterTurns;

  const CameraWorkerConfig({
    required this.toMain,
    required this.deviceIndex,
    required this.apiPreference,
    required this.requestWidth,
    required this.requestHeight,
    required this.previewIntervalMs,
    this.requestFps = 0,
    this.rotationQuarterTurns = 0,
  });
}

// ── Messages to the main isolate ─────────────────────────────────────────────
//
// Plain maps keyed by 'type':
//   ready    — {commands: SendPort} first message; where to send commands
//   opened   — {width, height, fps} the mode the driver actually granted
//   frame    — {jpeg: Uint8List, us: int} every captured frame, encoded
//   preview  — {rgba: Uint8List, width, height} throttled, for the live view
//   stats    — {seconds, loops, readUs, encodeUs, previewUs} once a second
//   error    — {message} terminal; the worker exits after sending it
//   stopped  — {} clean exit after a stop command
//
// Commands to the worker: {'cmd': 'stop'} and
// {'cmd': 'previewPaused', 'value': bool}.

/// Isolate entry point.
Future<void> cameraWorkerMain(CameraWorkerConfig config) async {
  final toMain = config.toMain;
  final commands = ReceivePort();
  toMain.send({'type': 'ready', 'commands': commands.sendPort});

  var stop = false;
  var previewPaused = false;
  var rotation = config.rotationQuarterTurns % 4;
  commands.listen((message) {
    if (message is! Map) return;
    switch (message['cmd']) {
      case 'stop':
        stop = true;
      case 'previewPaused':
        previewPaused = message['value'] == true;
      case 'rotation':
        rotation = ((message['value'] as int?) ?? 0) % 4;
    }
  });

  // Two attempts, a beat apart. These UVC drivers routinely refuse an open
  // that lands shortly after a release — the startup probe releases the
  // device moments before this worker opens it — and one retry clears the
  // transient case at no cost to the case that opens first time.
  cv.VideoCapture? capture;
  Object? openError;
  for (var attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (stop) {
      commands.close();
      return;
    }
    try {
      final candidate = cv.VideoCapture.fromDevice(
        config.deviceIndex,
        apiPreference: config.apiPreference,
      );
      if (candidate.isOpened) {
        capture = candidate;
        break;
      }
      candidate.dispose();
      openError = null;
    } catch (error) {
      openError = error;
    }
  }

  if (capture == null) {
    toMain.send({
      'type': 'error',
      'message': openError != null
          ? '$openError'
          : 'The device is attached but refused to open, twice. Another app '
                'may be holding it, or its driver is wedged — unplug and '
                'replug it.',
    });
    commands.close();
    return;
  }

  // The format matters more than the size. Uncompressed YUY2 at 1280x720x30
  // needs ~55MB/s against USB 2.0's ~35-40, so a camera left uncompressed at
  // 720p gets capped by the driver at 10-15fps — it doesn't refuse, it
  // crawls. MJPG fits with room to spare. The catch is that DirectShow can
  // ignore a FOURCC request silently, and changing the frame size can reset
  // the format, so the request is made before the size, checked after it,
  // and repeated if it didn't stick. What was actually granted goes back in
  // the opened message, so a format that refuses to take is visible in the
  // log rather than deduced from the frame rate.
  if (config.requestWidth > 0 && config.requestHeight > 0) {
    // 30 stays the request when no rate was chosen — it is what first pulled
    // DirectShow off its slow uncompressed default. A chosen rate replaces
    // it; the camera snaps down whatever it cannot do.
    final fps = config.requestFps > 0 ? config.requestFps : 30;
    capture.set(propFourcc, fourccMjpg.toDouble());
    capture.set(propFrameWidth, config.requestWidth.toDouble());
    capture.set(propFrameHeight, config.requestHeight.toDouble());
    capture.set(propFps, fps.toDouble());
    if (capture.get(propFourcc).toInt() != fourccMjpg) {
      capture.set(propFourcc, fourccMjpg.toDouble());
    }
  }

  toMain.send({
    'type': 'opened',
    'width': capture.get(propFrameWidth).round(),
    'height': capture.get(propFrameHeight).round(),
    'fps': capture.get(propFps),
    'fourcc': capture.get(propFourcc).toInt(),
  });

  final sincePreview = Stopwatch()..start();
  final report = Stopwatch()..start();
  final step = Stopwatch();
  var loops = 0;
  var readUs = 0;
  var encodeUs = 0;
  var previewUs = 0;
  var emptyReads = 0;
  var consecutiveFailures = 0;

  while (!stop) {
    step
      ..reset()
      ..start();
    final (ok, frame) = await capture.readAsync();
    readUs += step.elapsedMicroseconds;

    if (stop) {
      frame.dispose();
      break;
    }
    if (!ok || frame.isEmpty) {
      frame.dispose();
      emptyReads++;
      // A run of failures means the camera has gone away, most often
      // unplugged mid-session. The threshold is high because an empty read
      // can also just mean "no new frame yet": some backends return instead
      // of blocking when polled between deliveries.
      if (++consecutiveFailures >= 200) {
        toMain.send({
          'type': 'error',
          'message': 'The camera stopped sending frames.',
        });
        capture.release();
        capture.dispose();
        commands.close();
        return;
      }
      // Short back-off only. This used to be 30ms, which turned a
      // non-blocking backend into read → empty → sleep 30 → read: roughly
      // 13fps from a 30fps camera, with the sleep — not the camera —
      // setting the pace.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      continue;
    }
    consecutiveFailures = 0;

    // Rotation happens here, once, at the source: every consumer — the ring
    // buffer, the preview, review, every export — then agrees on orientation
    // for free, instead of each applying (or forgetting) its own transform.
    cv.Mat oriented = frame;
    cv.Mat? rotated;
    if (rotation != 0) {
      rotated = cv.rotate(frame, _rotateCodes[rotation - 1]);
      oriented = rotated;
    }

    try {
      step
        ..reset()
        ..start();
      final (encoded, jpeg) = cv.imencode('.jpg', oriented);
      encodeUs += step.elapsedMicroseconds;
      if (encoded) {
        toMain.send({
          'type': 'frame',
          'jpeg': jpeg,
          'us': DateTime.now().microsecondsSinceEpoch,
        });
      }

      if (!previewPaused &&
          sincePreview.elapsedMilliseconds >= config.previewIntervalMs) {
        sincePreview
          ..reset()
          ..start();
        step
          ..reset()
          ..start();
        final rgba = cv.cvtColor(oriented, colorBgr2Rgba);
        // Mat.data is a view onto native memory; it has to be copied out
        // before the Mat is disposed, and a copy is required to cross the
        // isolate boundary anyway.
        final pixels = Uint8List.fromList(rgba.data);
        final width = rgba.cols;
        final height = rgba.rows;
        rgba.dispose();
        previewUs += step.elapsedMicroseconds;
        toMain.send({
          'type': 'preview',
          'rgba': pixels,
          'width': width,
          'height': height,
        });
      }
    } finally {
      rotated?.dispose();
      frame.dispose();
    }

    loops++;
    if (report.elapsed >= const Duration(seconds: 1)) {
      toMain.send({
        'type': 'stats',
        'seconds': report.elapsedMicroseconds / 1000000,
        'loops': loops,
        'readUs': readUs,
        'encodeUs': encodeUs,
        'previewUs': previewUs,
        'emptyReads': emptyReads,
      });
      report.reset();
      loops = 0;
      readUs = 0;
      encodeUs = 0;
      previewUs = 0;
      emptyReads = 0;
    }

    // No explicit yield here, deliberately. On the UI isolate one was vital,
    // but here the readAsync await already hands the event loop a turn — its
    // completion arrives as a port message, which cannot be delivered
    // synchronously — so the command port is always serviced. The
    // zero-duration timer this used to carry was pure per-frame overhead in
    // a background isolate.
  }

  capture.release();
  capture.dispose();
  commands.close();
  toMain.send({'type': 'stopped'});
}
