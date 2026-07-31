/// Writes a captured impact clip to disk.
///
/// Works down a ladder of containers: H.264 MP4 through Windows Media
/// Foundation, then an MJPG AVI through OpenCV's own RIFF muxer, then a
/// numbered frame folder. The ladder exists because dartcv ships without
/// FFMPEG, so each writer's availability is an open question per machine —
/// MSMF is a Windows component and its H.264 encoder is ordinarily present,
/// but nothing here assumes it. The result names the rung that worked.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';

/// `cv::IMREAD_COLOR` — decode to 3-channel BGR, which is what writers expect.
const _imreadColor = 1;

/// `cv::CAP_MSMF` — Media Foundation, whose sink writer muxes H.264 into MP4
/// natively on Windows, no FFMPEG involved.
const _capMsmf = 1400;

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
  // OpenCV's built-in RIFF muxer; needs no OS encoder at all, since the
  // frames are already JPEGs and MJPG is just JPEGs in an AVI.
  _VideoAttempt('MJPG AVI', '.avi', 'MJPG'),
];

enum ClipExportFormat { video, frames }

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

  /// Why the video rungs were abandoned, when they all were.
  final String? fallbackReason;

  const ClipExportResult({
    required this.format,
    required this.path,
    required this.bytes,
    required this.frameCount,
    this.videoLabel,
    this.fallbackReason,
  });

  String get sizeLabel => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class ClipExportService {
  ClipExportService._();

  /// Writes [clip] under the app's documents directory and returns where it
  /// landed.
  ///
  /// Documents rather than a temp file and a share sheet — the convention the
  /// CSV export follows — because these run to tens of megabytes and are
  /// meant to be kept and opened in something else, not passed around.
  static Future<ClipExportResult> export({
    required ImpactClip clip,
    required String baseName,
    double speed = 1.0,
  }) async {
    if (clip.isEmpty) {
      throw StateError('Nothing to export: the clip holds no frames.');
    }
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'must be positive');
    }

    final root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/clips',
    );
    await root.create(recursive: true);
    final stem = _stem(baseName, clip, speed);

    final reasons = <String>[];
    for (final attempt in _attempts) {
      final path = '${root.path}/$stem${attempt.extension}';
      final reason = await _tryWriteVideo(clip, attempt, path, speed);
      if (reason == null) {
        final bytes = await File(path).length();
        debugPrint('[export] ${attempt.label} → $path ($bytes bytes)');
        return ClipExportResult(
          format: ClipExportFormat.video,
          videoLabel: attempt.label,
          path: path,
          bytes: bytes,
          frameCount: clip.frameCount,
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

  static String _stem(String baseName, ImpactClip clip, double speed) {
    final safe = baseName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final at = clip.capturedAt;
    final stamp =
        '${at.year}-${_two(at.month)}-${_two(at.day)}_'
        '${_two(at.hour)}${_two(at.minute)}${_two(at.second)}';
    final prefix = safe.isEmpty ? 'clip' : safe;
    // Named into the file so a slowed export can't be mistaken for the
    // real-time one sitting next to it.
    final rate = speed == 1.0 ? '' : '_${speed}x';
    return '${prefix}_shot-${clip.shotIndex + 1}_$stamp$rate';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
