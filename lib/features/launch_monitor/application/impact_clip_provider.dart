/// Rolling capture of the frames either side of a shot.
///
/// The pre-roll half cannot be recorded on demand: by the time the launch
/// monitor's BLE packet arrives the ball is already gone, so the frames
/// before it have to come from a buffer that is always filling. That buffer
/// is this file's job.
///
/// It is deliberately not part of the camera provider. The camera's job is a
/// live picture; this one owns clip lifetime, memory and the shot pairing,
/// and the two want to change for different reasons.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';

@immutable
class ImpactClipState {
  /// Frames are being buffered — the camera is streaming.
  final bool armed;

  /// A shot landed and the post-roll is still being collected.
  final bool capturing;

  /// Sealed clips, newest first.
  final List<ImpactClip> clips;

  /// Frames currently held in the ring, for a live "buffer filling" readout.
  final int bufferedFrames;

  const ImpactClipState({
    this.armed = false,
    this.capturing = false,
    this.clips = const [],
    this.bufferedFrames = 0,
  });

  ImpactClip? get latest => clips.isEmpty ? null : clips.first;

  int get byteSize =>
      clips.fold<int>(0, (sum, clip) => sum + clip.byteSize);
}

final impactClipProvider =
    NotifierProvider<ImpactClipRecorder, ImpactClipState>(
      ImpactClipRecorder.new,
    );

class ImpactClipRecorder extends Notifier<ImpactClipState> {
  /// How much of the run-up to keep. Generous on purpose: the BLE packet
  /// lands an unknown time after the strike, so the pre-roll has to cover
  /// both the swing and that latency.
  static const preRoll = Duration(seconds: 3);

  /// How long to keep recording once a shot is reported.
  static const postRoll = Duration(seconds: 3);

  /// Clips retained in memory. Each is tens of megabytes, so this is a hard
  /// ceiling rather than a hint — a full session's worth would not fit.
  static const maxClips = 3;

  final Queue<ClipFrame> _ring = Queue<ClipFrame>();
  DateTime? _triggerAt;
  int _pendingShotIndex = 0;
  bool _disposed = false;

  @override
  ImpactClipState build() {
    // The shot count going up is the trigger. Listening here rather than in
    // a widget means capture does not depend on which tab happens to be on
    // screen — the golfer will usually be looking at their numbers.
    ref.listen<int>(launchMonitorProvider.select((s) => s.shots.length), (
      previous,
      next,
    ) {
      if (next > (previous ?? 0)) _onShot(next - 1);
    });
    ref.onDispose(() {
      _disposed = true;
      _ring.clear();
    });
    return const ImpactClipState();
  }

  /// Called by the camera pump when the feed starts and stops. Buffering
  /// only while a picture is live keeps the JPEG encode off the CPU the rest
  /// of the time.
  void setArmed(bool armed) {
    if (_disposed || armed == state.armed) return;
    if (!armed) {
      _ring.clear();
      _triggerAt = null;
    }
    state = ImpactClipState(
      armed: armed,
      capturing: false,
      clips: state.clips,
      bufferedFrames: 0,
    );
  }

  /// Offers one frame straight off the camera.
  ///
  /// Encoding happens here, on the pump's turn of the loop — roughly 5-10ms
  /// for a 1080p JPEG against a 33ms frame budget at 30fps. If that ever
  /// starts costing frames, encoding quality is the first dial and dropping
  /// to every other frame for the pre-roll is the second.
  void offer(cv.Mat bgr) {
    if (_disposed || !state.armed) return;

    final (ok, bytes) = cv.imencode('.jpg', bgr);
    if (!ok) return;

    final now = DateTime.now();
    _ring.add(ClipFrame(jpeg: bytes, at: now));

    final trigger = _triggerAt;
    if (trigger == null) {
      // Free-running: keep only the pre-roll window.
      final cutoff = now.subtract(preRoll);
      while (_ring.length > 1 && _ring.first.at.isBefore(cutoff)) {
        _ring.removeFirst();
      }
      _publishBufferSize();
      return;
    }

    // Capturing: hold everything until the post-roll is complete, otherwise
    // trimming would eat the pre-roll we are here for.
    if (now.difference(trigger) >= postRoll) {
      _seal(trigger);
    } else {
      _publishBufferSize();
    }
  }

  void _onShot(int shotIndex) {
    if (_disposed || !state.armed) return;
    // A second shot inside the post-roll window keeps the clip already in
    // progress: splitting it would hand back two clips neither of which
    // contains a whole swing.
    if (_triggerAt != null) {
      debugPrint('[clip] shot $shotIndex arrived mid-capture; folded in');
      return;
    }
    _triggerAt = DateTime.now();
    _pendingShotIndex = shotIndex;
    state = ImpactClipState(
      armed: state.armed,
      capturing: true,
      clips: state.clips,
      bufferedFrames: _ring.length,
    );
    debugPrint('[clip] shot $shotIndex — ${_ring.length} frames of pre-roll');
  }

  void _seal(DateTime trigger) {
    final frames = List<ClipFrame>.unmodifiable(_ring);
    _ring.clear();
    _triggerAt = null;

    if (frames.isEmpty) {
      _publishBufferSize();
      return;
    }

    // First frame at or after the packet. Every earlier frame is pre-roll,
    // and the strike itself is somewhere in them.
    var triggerIndex = frames.indexWhere((f) => !f.at.isBefore(trigger));
    if (triggerIndex < 0) triggerIndex = frames.length - 1;

    final clip = ImpactClip(
      frames: frames,
      triggerIndex: triggerIndex,
      shotIndex: _pendingShotIndex,
      capturedAt: trigger,
    );

    final clips = [clip, ...state.clips];
    state = ImpactClipState(
      armed: state.armed,
      capturing: false,
      clips: List.unmodifiable(
        clips.length > maxClips ? clips.sublist(0, maxClips) : clips,
      ),
      bufferedFrames: 0,
    );

    debugPrint(
      '[clip] sealed shot ${clip.shotIndex}: ${clip.frameCount} frames, '
      '${clip.duration.inMilliseconds}ms, '
      '${clip.effectiveFps.toStringAsFixed(1)}fps, '
      'trigger at ${clip.triggerIndex}, '
      '${(clip.byteSize / (1024 * 1024)).toStringAsFixed(1)}MB',
    );
  }

  /// Drops every retained clip. The only way to hand back the memory short
  /// of leaving the session.
  void clearClips() {
    if (_disposed) return;
    state = ImpactClipState(
      armed: state.armed,
      capturing: state.capturing,
      bufferedFrames: state.bufferedFrames,
    );
  }

  void _publishBufferSize() {
    // Cheap enough to publish every frame, and it is the only signal that
    // the buffer is actually filling before the first shot lands.
    if (state.bufferedFrames == _ring.length) return;
    state = ImpactClipState(
      armed: state.armed,
      capturing: state.capturing,
      clips: state.clips,
      bufferedFrames: _ring.length,
    );
  }
}
