import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// One buffered camera frame, JPEG-encoded.
///
/// Encoded rather than raw because raw is unaffordable: a 1080p BGR frame is
/// about 6 MB, so three seconds of pre-roll at 30fps would be over half a
/// gigabyte held permanently while the session runs.
@immutable
class ClipFrame {
  final Uint8List jpeg;

  /// Wall-clock time the frame was pulled off the camera. Absolute rather
  /// than an offset, because the clip's own start isn't known until the ring
  /// buffer is sealed.
  final DateTime at;

  const ClipFrame({required this.jpeg, required this.at});
}

/// The frames around one shot: everything the ring buffer held when the
/// launch monitor reported it, plus the post-roll recorded afterwards.
@immutable
class ImpactClip {
  /// Oldest first.
  final List<ClipFrame> frames;

  /// Index of the first frame at or after the launch monitor's packet.
  ///
  /// This is *not* the moment of impact. The Omni measures the ball at
  /// impact, but the reading reaches us over BLE some unknown time later, so
  /// the true strike is somewhere in the frames *before* this one. Marking
  /// what we actually know beats inventing a latency constant — and watching
  /// where the ball really is at this marker is the cheapest way to measure
  /// that latency for real.
  final int triggerIndex;

  /// Position of the shot in the session at capture time, for pairing the
  /// clip with its row in the shot list.
  final int shotIndex;

  final DateTime capturedAt;

  const ImpactClip({
    required this.frames,
    required this.triggerIndex,
    required this.shotIndex,
    required this.capturedAt,
  });

  bool get isEmpty => frames.isEmpty;

  int get frameCount => frames.length;

  /// Wall-clock span from first to last frame.
  Duration get duration => frames.length < 2
      ? Duration.zero
      : frames.last.at.difference(frames.first.at);

  /// Frames per second actually achieved, which is what the analysis is
  /// limited by — never assume the camera's nominal rate.
  double get effectiveFps {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    return seconds <= 0 ? 0 : (frames.length - 1) / seconds;
  }

  /// Signed offset of [index] from the trigger frame. Negative before the
  /// launch monitor reported the shot, positive after.
  Duration offsetFromTrigger(int index) {
    if (frames.isEmpty) return Duration.zero;
    final safe = index.clamp(0, frames.length - 1);
    final pivot = triggerIndex.clamp(0, frames.length - 1);
    return frames[safe].at.difference(frames[pivot].at);
  }

  /// Total bytes held, so the UI can be honest about what a clip costs.
  int get byteSize =>
      frames.fold<int>(0, (sum, frame) => sum + frame.jpeg.lengthInBytes);
}
