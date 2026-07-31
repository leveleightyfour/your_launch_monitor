/// Writes a captured impact clip to disk.
///
/// Tries an MJPG AVI first and falls back to a numbered frame sequence. The
/// fallback is not defensive padding: dartcv dropped FFMPEG in 2.2.0, and
/// whether OpenCV's own AVI writer can still produce a playable file without
/// it is exactly the thing this code finds out. The result says which path
/// was taken so the answer is visible rather than assumed.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';

/// `cv::IMREAD_COLOR` — decode to 3-channel BGR, which is what the writer
/// expects.
const _imreadColor = 1;

/// An AVI header alone is about 2 kB. A writer that opened but had no working
/// encoder behind it still lays that down and then silently drops every
/// frame, so a file this small means failure however healthy the API looked.
const _minPlausibleVideoBytes = 8192;

enum ClipExportFormat { video, frames }

@immutable
class ClipExportResult {
  final ClipExportFormat format;

  /// The `.avi` file, or the directory holding the frame sequence.
  final String path;

  final int bytes;
  final int frameCount;

  /// Why the video attempt was abandoned, when it was.
  final String? fallbackReason;

  const ClipExportResult({
    required this.format,
    required this.path,
    required this.bytes,
    required this.frameCount,
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
  }) async {
    if (clip.isEmpty) {
      throw StateError('Nothing to export: the clip holds no frames.');
    }

    final root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/clips',
    );
    await root.create(recursive: true);
    final stem = _stem(baseName, clip);

    final videoPath = '${root.path}/$stem.avi';
    final reason = await _tryWriteVideo(clip, videoPath);
    if (reason == null) {
      final bytes = await File(videoPath).length();
      debugPrint('[export] MJPG AVI → $videoPath ($bytes bytes)');
      return ClipExportResult(
        format: ClipExportFormat.video,
        path: videoPath,
        bytes: bytes,
        frameCount: clip.frameCount,
      );
    }

    debugPrint('[export] MJPG unavailable — $reason; writing frames instead');
    final framesDir = Directory('${root.path}/$stem');
    final bytes = await _writeFrames(clip, framesDir);
    debugPrint('[export] frames → ${framesDir.path} ($bytes bytes)');
    return ClipExportResult(
      format: ClipExportFormat.frames,
      path: framesDir.path,
      bytes: bytes,
      frameCount: clip.frameCount,
      fallbackReason: reason,
    );
  }

  /// Returns null when a playable file was written, or the reason it wasn't.
  static Future<String?> _tryWriteVideo(ImpactClip clip, String path) async {
    // Remove any earlier attempt: a stale file would otherwise pass the size
    // check below and report success for a writer that wrote nothing.
    final file = File(path);
    if (await file.exists()) await file.delete();

    cv.VideoWriter? writer;
    try {
      final probe = cv.imdecode(clip.frames.first.jpeg, _imreadColor);
      final size = (probe.cols, probe.rows);
      probe.dispose();
      if (size.$1 <= 0 || size.$2 <= 0) return 'the first frame would not decode';

      // The clip's measured rate, not the camera's nominal one — DirectShow
      // reports 0 fps here, and a wrong value in the header plays the clip
      // back at the wrong speed.
      final fps = clip.effectiveFps > 1 ? clip.effectiveFps : 30.0;

      writer = cv.VideoWriter.fromFile(path, 'MJPG', fps, size);
      if (!writer.isOpened) return 'OpenCV would not open an MJPG writer';

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

  static String _stem(String baseName, ImpactClip clip) {
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
    return '${prefix}_shot-${clip.shotIndex + 1}_$stamp';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
