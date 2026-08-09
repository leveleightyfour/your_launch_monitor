/// Writes a captured impact clip to disk.
///
/// Works down a ladder of containers: H.264 MP4 through the OS's own encoder
/// (Media Foundation on Windows, AVFoundation on macOS), then an MJPG AVI
/// through OpenCV's own RIFF muxer, then a numbered frame folder. The ladder
/// exists because dartcv ships without FFMPEG, so each writer's availability
/// is an open question per machine — the OS H.264 encoder is ordinarily
/// present, but nothing here assumes it. The result names the rung that
/// worked.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

import 'package:omni_sniffer/features/launch_monitor/application/impact_clip_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';

/// `cv::IMREAD_COLOR` — decode to 3-channel BGR, which is what writers expect.
const _imreadColor = 1;

/// `cv::CAP_MSMF` — Media Foundation, whose sink writer muxes H.264 into MP4
/// natively on Windows, no FFMPEG involved.
const _capMsmf = 1400;

/// `cv::CAP_AVFOUNDATION` — AVFoundation, macOS's Media Foundation
/// equivalent: AVAssetWriter muxes H.264 into MP4 natively, no FFMPEG.
const _capAvfoundation = 1200;

/// A container header alone is a few kB. A writer that opened but had no
/// working encoder behind it still lays that down and then silently drops
/// every frame, so a file this small means failure however healthy the API
/// looked.
const _minPlausibleVideoBytes = 8192;

/// One rung of the writer ladder.
class _VideoAttempt {
  final String label;
  final String extension;
  final String codec;
  final int? apiPreference;

  const _VideoAttempt(this.label, this.extension, this.codec,
      [this.apiPreference]);
}

const _attempts = [
  // H.264 in MP4 via Media Foundation. The backend is named explicitly —
  // left to choose, OpenCV would only reach MSMF by accident.
  _VideoAttempt('H.264 MP4', '.mp4', 'H264', _capMsmf),
  // The same rung for macOS. 'avc1' rather than 'H264': it is the FOURCC
  // AVFoundation's writer actually registers. On Windows this rung fails to
  // open and the ladder moves on, exactly as the MSMF rung does on macOS.
  _VideoAttempt('H.264 MP4', '.mp4', 'avc1', _capAvfoundation),
  // OpenCV's built-in RIFF muxer; needs no OS encoder at all, since the
  // frames are already JPEGs and MJPG is just JPEGs in an AVI.
  _VideoAttempt('MJPG AVI', '.avi', 'MJPG'),
];

enum ClipExportFormat { video, frames }

/// How a multi-angle shot is arranged in a single composite video.
enum CompositeLayout {
  sideBySide('Side by side', 'side-by-side'),
  stacked('Stacked', 'stacked');

  final String label;

  /// Goes into the file name, so a composite can't be mistaken for a
  /// single-angle export sitting next to it.
  final String stemSuffix;

  const CompositeLayout(this.label, this.stemSuffix);
}

@immutable
class ClipExportResult {
  final ClipExportFormat format;

  /// Which video rung succeeded — 'H.264 MP4' or 'MJPG AVI'. Null for the
  /// frame-folder fallback.
  final String? videoLabel;

  /// The video file, or the directory holding the frame sequence.
  final String path;

  final int bytes;
  final int frameCount;

  /// Pixel size of the written video (zero for the frame-folder fallback).
  /// Surfaced so a "that file looks the wrong size" report can be settled
  /// by reading the snackbar instead of hunting through file properties.
  final int width;
  final int height;

  /// Why the video rungs were abandoned, when they all were.
  final String? fallbackReason;

  /// Why the file didn't land in the chosen folder, when one was chosen and
  /// couldn't be written to. Null whenever [path] is where the golfer asked
  /// for — a fallback the caller can't see is a file reported as saved
  /// somewhere it isn't.
  final String? directoryFallback;

  const ClipExportResult({
    required this.format,
    required this.path,
    required this.bytes,
    required this.frameCount,
    this.width = 0,
    this.height = 0,
    this.videoLabel,
    this.fallbackReason,
    this.directoryFallback,
  });

  String get sizeLabel => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String get dimensionsLabel => '$width×$height';
}

class ClipExportService {
  ClipExportService._();

  /// The folder exports land in: [directory] when one was chosen and is
  /// still writable, else the default Documents/clips. Writability is proved
  /// with a throwaway file up front, because a denied folder would otherwise
  /// surface as every writer rung failing with encoder-shaped errors. A folder
  /// can still go bad between sessions — renamed, unmounted, permissions
  /// changed — so the check runs every export, not once at pick time.
  ///
  /// The second value says why the chosen folder was passed over, and is null
  /// when it wasn't. It rides all the way out to the snackbar: this fallback
  /// used to be a debugPrint, which meant the sheet could promise one folder
  /// while the file went to another and nothing on screen ever said so.
  static Future<(Directory, String?)> _exportRoot(String? directory) async {
    String? fallback;
    if (directory != null && directory.isNotEmpty) {
      try {
        final dir = Directory(directory);
        await dir.create(recursive: true);
        final probe = File('${dir.path}/.write-probe');
        await probe.writeAsString('');
        await probe.delete();
        return (dir, null);
      } catch (error) {
        // The phrase, not the raw error: this is snackbar text. The error
        // itself stays in the log, where a stack-shaped message belongs.
        fallback = '$directory could not be written to';
        debugPrint(
          '[export] $fallback ($error) — falling back to Documents/clips',
        );
      }
    }
    final root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/clips',
    );
    await root.create(recursive: true);
    return (root, fallback);
  }

  /// Writes [clip] under [directory] — or the app's documents directory when
  /// none is set — and returns where it landed.
  ///
  /// Documents rather than a temp file and a share sheet — the convention the
  /// CSV export follows — because these run to tens of megabytes and are
  /// meant to be kept and opened in something else, not passed around.
  static Future<ClipExportResult> export({
    required ImpactClip clip,
    required String baseName,
    double speed = 1.0,
    String? directory,
  }) async {
    if (clip.isEmpty) {
      throw StateError('Nothing to export: the clip holds no frames.');
    }
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be positive');
    }

    final (root, directoryFallback) = await _exportRoot(directory);
    final stem = _stem(baseName, clip.shotIndex, clip.capturedAt, speed);

    final probe = cv.imdecode(clip.frames.first.jpeg, _imreadColor);
    final (frameWidth, frameHeight) = (probe.cols, probe.rows);
    probe.dispose();

    final reasons = <String>[];
    for (final attempt in _attempts) {
      final path = '${root.path}/$stem${attempt.extension}';
      final reason = await _tryWriteVideo(clip, attempt, path, speed);
      if (reason == null) {
        final bytes = await File(path).length();
        debugPrint(
          '[export] ${attempt.label} ${frameWidth}x$frameHeight → $path '
          '($bytes bytes)',
        );
        return ClipExportResult(
          format: ClipExportFormat.video,
          videoLabel: attempt.label,
          path: path,
          bytes: bytes,
          frameCount: clip.frameCount,
          width: frameWidth,
          height: frameHeight,
          directoryFallback: directoryFallback,
        );
      }
      debugPrint('[export] ${attempt.label} unavailable — $reason');
      reasons.add('${attempt.label}: $reason');
    }

    final framesDir = Directory('${root.path}/$stem');
    final bytes = await _writeFrames(clip, framesDir);
    debugPrint('[export] frames → ${framesDir.path} ($bytes bytes)');
    return ClipExportResult(
      format: ClipExportFormat.frames,
      path: framesDir.path,
      bytes: bytes,
      frameCount: clip.frameCount,
      fallbackReason: reasons.join('; '),
      directoryFallback: directoryFallback,
    );
  }

  /// Returns null when a playable file was written, or the reason it wasn't.
  static Future<String?> _tryWriteVideo(
    ImpactClip clip,
    _VideoAttempt attempt,
    String path,
    double speed,
  ) async {
    // Remove any earlier attempt: a stale file would otherwise pass the size
    // check below and report success for a writer that wrote nothing.
    final file = File(path);
    if (await file.exists()) await file.delete();

    cv.VideoWriter? writer;
    try {
      final probe = cv.imdecode(clip.frames.first.jpeg, _imreadColor);
      final size = (probe.cols, probe.rows);
      probe.dispose();
      if (size.$1 <= 0 || size.$2 <= 0) {
        return 'the first frame would not decode';
      }

      // The clip's measured rate, not the camera's nominal one — DirectShow
      // reports 0 fps at capture, and a wrong value in the header plays the
      // clip back at the wrong speed. Slow motion is the same frames under a
      // slower header rate: no frames are invented, the player just holds
      // each one longer. Floored at 1fps, below which some players baulk.
      final base = clip.effectiveFps > 1 ? clip.effectiveFps : 30.0;
      final fps = (base * speed).clamp(1.0, double.infinity);

      writer = attempt.apiPreference == null
          ? cv.VideoWriter.fromFile(path, attempt.codec, fps, size)
          : cv.VideoWriter.fromFile(
              path,
              attempt.codec,
              fps,
              size,
              apiPreference: attempt.apiPreference,
            );
      if (!writer.isOpened) {
        return 'OpenCV would not open a ${attempt.codec} writer';
      }

      for (final frame in clip.frames) {
        final mat = cv.imdecode(frame.jpeg, _imreadColor);
        try {
          writer.write(mat);
        } finally {
          mat.dispose();
        }
      }
      writer.release();
    } catch (error) {
      return '$error';
    } finally {
      writer?.dispose();
    }

    if (!await file.exists()) return 'the writer produced no file';
    final length = await file.length();
    if (length < _minPlausibleVideoBytes) {
      await file.delete();
      return 'the file came out empty ($length bytes)';
    }
    return null;
  }

  /// Numbered JPEGs plus a manifest of frame times.
  ///
  /// The manifest is what makes a frame folder more than a pile of images:
  /// it carries each frame's offset from the trigger, which is how two
  /// camera angles of the same shot get lined up later.
  static Future<int> _writeFrames(ImpactClip clip, Directory dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final manifest = StringBuffer('frame,offset_ms,is_trigger\n');
    var bytes = 0;

    for (var i = 0; i < clip.frames.length; i++) {
      final number = i.toString().padLeft(4, '0');
      final isTrigger = i == clip.triggerIndex;
      // The trigger frame is named, not just listed — it is the one frame
      // anybody opening this folder is looking for.
      final suffix = isTrigger ? '_packet' : '';
      final file = File('${dir.path}/frame_$number$suffix.jpg');
      await file.writeAsBytes(clip.frames[i].jpeg);
      bytes += clip.frames[i].jpeg.lengthInBytes;

      manifest.writeln(
        '$number,${clip.offsetFromTrigger(i).inMilliseconds},$isTrigger',
      );
    }

    await File('${dir.path}/manifest.csv').writeAsString(manifest.toString());
    return bytes;
  }

  // ── Composite export ───────────────────────────────────────────────────────

  /// Writes every angle of [shot] into one video, aligned on the shared
  /// trigger, arranged per [layout].
  ///
  /// Alignment is arithmetic, not guesswork: every angle's frames carry wall
  /// clock timestamps and the shot carries the trigger's, so each frame has a
  /// signed offset from the packet. The composite covers the *intersection*
  /// of the angles' windows — the span where every camera was actually
  /// recording — because padding a late-starting angle with black or frozen
  /// frames would misrepresent what was captured.
  static Future<ClipExportResult> exportComposite({
    required ShotClips shot,
    required CompositeLayout layout,
    required String baseName,
    double speed = 1.0,
    String? directory,
  }) async {
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be positive');
    }
    final clips = [
      for (final slot in shot.slots)
        if (!shot.angles[slot]!.isEmpty) shot.angles[slot]!,
    ];
    if (clips.length < 2) {
      throw StateError('A composite needs at least two captured angles.');
    }

    final plan = _CompositePlan.build(shot, clips, layout);
    debugPrint(
      '[export] composite ${layout.name}: ${clips.length} angles → '
      '${plan.outWidth}×${plan.outHeight} '
      '(panes ${plan.paneSizes.map((s) => '${s.$1}×${s.$2}').join(' + ')}), '
      'window ${plan.windowStart.inMilliseconds}..'
      '${plan.windowEnd.inMilliseconds}ms, '
      'master ${plan.masterFps.toStringAsFixed(1)}fps, '
      '${plan.tickCount} frames',
    );

    final (root, directoryFallback) = await _exportRoot(directory);
    final stem = _stem(
      baseName,
      shot.shotIndex,
      shot.capturedAt,
      speed,
      suffix: layout.stemSuffix,
    );

    final reasons = <String>[];
    for (final attempt in _attempts) {
      final path = '${root.path}/$stem${attempt.extension}';
      final reason = await _tryWriteComposite(plan, attempt, path, speed);
      if (reason == null) {
        final bytes = await File(path).length();
        debugPrint(
          '[export] ${attempt.label} composite '
          '${plan.outWidth}x${plan.outHeight} → $path ($bytes bytes)',
        );
        return ClipExportResult(
          format: ClipExportFormat.video,
          videoLabel: attempt.label,
          path: path,
          bytes: bytes,
          frameCount: plan.tickCount,
          width: plan.outWidth,
          height: plan.outHeight,
          directoryFallback: directoryFallback,
        );
      }
      debugPrint('[export] ${attempt.label} composite unavailable — $reason');
      reasons.add('${attempt.label}: $reason');
    }

    final framesDir = Directory('${root.path}/$stem');
    final bytes = await _writeCompositeFrames(plan, framesDir);
    debugPrint('[export] composite frames → ${framesDir.path} ($bytes bytes)');
    return ClipExportResult(
      format: ClipExportFormat.frames,
      path: framesDir.path,
      bytes: bytes,
      frameCount: plan.tickCount,
      fallbackReason: reasons.join('; '),
      directoryFallback: directoryFallback,
    );
  }

  static Future<String?> _tryWriteComposite(
    _CompositePlan plan,
    _VideoAttempt attempt,
    String path,
    double speed,
  ) async {
    final file = File(path);
    if (await file.exists()) await file.delete();

    final fps = (plan.masterFps * speed).clamp(1.0, double.infinity);
    cv.VideoWriter? writer;
    final tracks = plan.newTracks();
    try {
      writer = attempt.apiPreference == null
          ? cv.VideoWriter.fromFile(
              path,
              attempt.codec,
              fps,
              (plan.outWidth, plan.outHeight),
            )
          : cv.VideoWriter.fromFile(
              path,
              attempt.codec,
              fps,
              (plan.outWidth, plan.outHeight),
              apiPreference: attempt.apiPreference,
            );
      if (!writer.isOpened) {
        return 'OpenCV would not open a ${attempt.codec} writer';
      }

      for (var tick = 0; tick < plan.tickCount; tick++) {
        final composite = plan.composeTick(tracks, tick);
        try {
          writer.write(composite);
        } finally {
          composite.dispose();
        }
      }
      writer.release();
    } catch (error) {
      return '$error';
    } finally {
      for (final track in tracks) {
        track.dispose();
      }
      writer?.dispose();
    }

    if (!await file.exists()) return 'the writer produced no file';
    final length = await file.length();
    if (length < _minPlausibleVideoBytes) {
      await file.delete();
      return 'the file came out empty ($length bytes)';
    }
    return null;
  }

  /// The composite equivalent of [_writeFrames]: re-encoded JPEGs of every
  /// composed tick, plus a manifest of trigger-relative offsets.
  static Future<int> _writeCompositeFrames(
    _CompositePlan plan,
    Directory dir,
  ) async {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final manifest = StringBuffer('frame,offset_ms,is_trigger\n');
    var bytes = 0;
    var triggerMarked = false;

    final tracks = plan.newTracks();
    try {
      for (var tick = 0; tick < plan.tickCount; tick++) {
        final offset = plan.tickOffset(tick);
        final isTrigger = !triggerMarked && offset >= Duration.zero;
        if (isTrigger) triggerMarked = true;

        final composite = plan.composeTick(tracks, tick);
        try {
          final (encoded, jpeg) = cv.imencode('.jpg', composite);
          if (!encoded) continue;
          final number = tick.toString().padLeft(4, '0');
          final suffix = isTrigger ? '_packet' : '';
          await File('${dir.path}/frame_$number$suffix.jpg')
              .writeAsBytes(jpeg);
          bytes += jpeg.lengthInBytes;
          manifest.writeln('$number,${offset.inMilliseconds},$isTrigger');
        } finally {
          composite.dispose();
        }
      }
    } finally {
      for (final track in tracks) {
        track.dispose();
      }
    }

    await File('${dir.path}/manifest.csv').writeAsString(manifest.toString());
    return bytes;
  }

  static String _stem(
    String baseName,
    int shotIndex,
    DateTime at,
    double speed, {
    String suffix = '',
  }) {
    final safe = baseName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp =
        '${at.year}-${_two(at.month)}-${_two(at.day)}_'
        '${_two(at.hour)}${_two(at.minute)}${_two(at.second)}';
    final prefix = safe.isEmpty ? 'clip' : safe;
    final tag = suffix.isEmpty ? '' : '_$suffix';
    // Named into the file so a slowed export can't be mistaken for the
    // real-time one sitting next to it.
    final rate = speed == 1.0 ? '' : '_${speed}x';
    return '${prefix}_shot-${shotIndex + 1}_$stamp$tag$rate';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

// ── Composite plumbing ───────────────────────────────────────────────────────

/// Everything decided once per composite export: the shared time window, the
/// master frame clock, and each angle's pane size. Built before any writer is
/// opened so an impossible export (angles that never overlap) fails with a
/// real explanation instead of an empty file.
class _CompositePlan {
  final CompositeLayout layout;
  final List<ImpactClip> clips;

  /// Each angle's first-frame time relative to the trigger.
  final List<Duration> startRels;

  /// The intersection window, trigger-relative.
  final Duration windowStart;
  final Duration windowEnd;

  /// The finest angle's measured rate — ticking at anything slower would
  /// throw away frames the best camera captured.
  final double masterFps;

  final List<(int, int)> paneSizes;
  final int outWidth;
  final int outHeight;

  _CompositePlan._({
    required this.layout,
    required this.clips,
    required this.startRels,
    required this.windowStart,
    required this.windowEnd,
    required this.masterFps,
    required this.paneSizes,
    required this.outWidth,
    required this.outHeight,
  });

  factory _CompositePlan.build(
    ShotClips shot,
    List<ImpactClip> clips,
    CompositeLayout layout,
  ) {
    final startRels = [
      for (final clip in clips)
        clip.frames.first.at.difference(shot.capturedAt),
    ];
    final endRels = [
      for (final clip in clips) clip.frames.last.at.difference(shot.capturedAt),
    ];
    final windowStart = startRels.reduce((a, b) => a > b ? a : b);
    final windowEnd = endRels.reduce((a, b) => a < b ? a : b);
    if (windowEnd <= windowStart) {
      throw StateError(
        'The angles never overlap in time, so there is nothing to compose. '
        'This usually means one camera stalled during the capture.',
      );
    }

    final bestFps = clips
        .map((c) => c.effectiveFps)
        .reduce((a, b) => a > b ? a : b);
    final masterFps = bestFps > 1 ? bestFps : 30.0;

    // Native sizes come from decoding one frame per angle — a camera's frames
    // are one size for the life of a clip. Panes are scaled to a shared edge
    // (heights for a row, widths for a column), scaling *up* to the largest
    // so no angle surrenders pixels. This matters once one camera is rotated
    // portrait: matching down to a landscape neighbour's 720px height would
    // shrink a 720×1280 portrait angle to a 404px-wide sliver, which is the
    // angle the composite exists to show. Upscaling the smaller pane costs
    // only file size. Dimensions are kept even because H.264 encoders
    // refuse odd ones.
    final natives = <(int, int)>[];
    for (final clip in clips) {
      final probe = cv.imdecode(clip.frames.first.jpeg, _imreadColor);
      final size = (probe.cols, probe.rows);
      probe.dispose();
      if (size.$1 <= 0 || size.$2 <= 0) {
        throw StateError('An angle\'s first frame would not decode.');
      }
      natives.add(size);
    }

    final paneSizes = <(int, int)>[];
    int outWidth;
    int outHeight;
    if (layout == CompositeLayout.sideBySide) {
      final height = _even(
        natives.map((s) => s.$2).reduce((a, b) => a > b ? a : b),
      );
      for (final (w, h) in natives) {
        paneSizes.add((_even((w * height / h).round()), height));
      }
      outWidth = paneSizes.fold(0, (sum, s) => sum + s.$1);
      outHeight = height;
    } else {
      final width = _even(
        natives.map((s) => s.$1).reduce((a, b) => a > b ? a : b),
      );
      for (final (w, h) in natives) {
        paneSizes.add((width, _even((h * width / w).round())));
      }
      outWidth = width;
      outHeight = paneSizes.fold(0, (sum, s) => sum + s.$2);
    }

    return _CompositePlan._(
      layout: layout,
      clips: clips,
      startRels: startRels,
      windowStart: windowStart,
      windowEnd: windowEnd,
      masterFps: masterFps,
      paneSizes: paneSizes,
      outWidth: outWidth,
      outHeight: outHeight,
    );
  }

  static int _even(int value) => value < 2 ? 2 : value - (value % 2);

  Duration get _tick =>
      Duration(microseconds: (1000000 / masterFps).round());

  int get tickCount =>
      (windowEnd - windowStart).inMicroseconds ~/ _tick.inMicroseconds + 1;

  /// Trigger-relative time of [tick] — negative before the packet.
  Duration tickOffset(int tick) => windowStart + _tick * tick;

  /// Fresh per-angle decode caches. Per attempt rather than per plan, so a
  /// failed writer rung can't leave the next one holding disposed Mats.
  List<_AngleTrack> newTracks() => [
    for (var i = 0; i < clips.length; i++)
      _AngleTrack(
        clip: clips[i],
        startRel: startRels[i],
        outWidth: paneSizes[i].$1,
        outHeight: paneSizes[i].$2,
      ),
  ];

  /// One composed frame. Each track only re-decodes when the master clock
  /// crosses into its next source frame — a 30fps angle under a 120fps clock
  /// is decoded once, not four times.
  cv.Mat composeTick(List<_AngleTrack> tracks, int tick) {
    final offset = tickOffset(tick);
    for (final track in tracks) {
      track.seek(offset);
    }
    var acc = tracks.first.pane.clone();
    for (var i = 1; i < tracks.length; i++) {
      final joined = layout == CompositeLayout.sideBySide
          ? cv.hconcat(acc, tracks[i].pane)
          : cv.vconcat(acc, tracks[i].pane);
      acc.dispose();
      acc = joined;
    }
    return acc;
  }
}

/// One angle's decode cache during a composite write.
class _AngleTrack {
  final ImpactClip clip;
  final Duration startRel;
  final int outWidth;
  final int outHeight;

  int _cachedIndex = -1;
  cv.Mat? _cached;

  _AngleTrack({
    required this.clip,
    required this.startRel,
    required this.outWidth,
    required this.outHeight,
  });

  cv.Mat get pane => _cached!;

  void seek(Duration triggerRelative) {
    var local = triggerRelative - startRel;
    if (local < Duration.zero) local = Duration.zero;
    final index = clip.indexAtOffset(local);
    if (index == _cachedIndex && _cached != null) return;

    final mat = cv.imdecode(clip.frames[index].jpeg, _imreadColor);
    cv.Mat scaled;
    if (mat.cols == outWidth && mat.rows == outHeight) {
      scaled = mat;
    } else {
      scaled = cv.resize(mat, (outWidth, outHeight));
      mat.dispose();
    }
    _cached?.dispose();
    _cached = scaled;
    _cachedIndex = index;
  }

  void dispose() {
    _cached?.dispose();
    _cached = null;
    _cachedIndex = -1;
  }
}
