/// Rolling capture of the frames either side of a shot, per camera slot.
///
/// The pre-roll half cannot be recorded on demand: by the time the launch
/// monitor's BLE packet arrives the ball is already gone, so the frames
/// before it have to come from a buffer that is always filling. That buffer
/// is this file's job — one ring per camera, but a single shared trigger, so
/// two angles of the same swing land in one [ShotClips] rather than as two
/// clips that happen to have close timestamps.
///
/// It is deliberately not part of the camera provider. The camera's job is a
/// live picture; this one owns clip lifetime, memory and the shot pairing,
/// and the two want to change for different reasons.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/impact_clip.dart';

// ── Shot clips ───────────────────────────────────────────────────────────────

/// Every angle captured around one shot, keyed by camera slot.
///
/// All angles share [capturedAt] — the BLE packet's arrival — so lining a
/// down-the-line frame up against its face-on counterpart is arithmetic on
/// each clip's own timestamps, not guesswork.
@immutable
class ShotClips {
  final int shotIndex;
  final DateTime capturedAt;
  final Map<int, ImpactClip> angles;

  const ShotClips({
    required this.shotIndex,
    required this.capturedAt,
    required this.angles,
  });

  /// Slots present, lowest first.
  List<int> get slots => angles.keys.toList()..sort();

  /// The lowest-numbered angle — what single-angle UI shows by default.
  ImpactClip get primary => angles[slots.first]!;

  int get angleCount => angles.length;

  int get byteSize =>
      angles.values.fold<int>(0, (sum, clip) => sum + clip.byteSize);
}

// ── State ────────────────────────────────────────────────────────────────────

@immutable
class ImpactClipState {
  /// Slots currently buffering — their cameras are streaming.
  final Set<int> armedSlots;

  /// A shot landed and at least one slot is still collecting post-roll.
  final bool capturing;

  /// Sealed shots, newest first.
  final List<ShotClips> clips;

  /// Frames currently held across every ring, for the "buffer filling"
  /// readout.
  final int bufferedFrames;

  const ImpactClipState({
    this.armedSlots = const {},
    this.capturing = false,
    this.clips = const [],
    this.bufferedFrames = 0,
  });

  bool get armed => armedSlots.isNotEmpty;

  ShotClips? get latest => clips.isEmpty ? null : clips.first;
}

// ── Recorder ─────────────────────────────────────────────────────────────────

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

  /// Shots retained in memory. Each can be tens of megabytes per angle, so
  /// this is a hard ceiling rather than a hint.
  static const maxClips = 3;

  /// How often the buffered-frame count is allowed to reach the UI.
  /// Publishing it per frame rebuilt the whole Camera tab thirty times a
  /// second to change one number; twice a second reads as live.
  static const _countPublishInterval = Duration(milliseconds: 500);

  final Map<int, Queue<ClipFrame>> _rings = {};
  DateTime _lastCountPublish = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _triggerAt;
  int _pendingShotIndex = 0;

  /// Slots that were armed when the trigger landed and have not sealed yet.
  final Set<int> _capturingSlots = {};

  /// Angles sealed so far for the shot in progress.
  final Map<int, ImpactClip> _pendingAngles = {};

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
      _rings.clear();
    });
    return const ImpactClipState();
  }

  /// Called by each camera as its feed starts and stops. Buffering only
  /// while a picture is live keeps the encode cost off idle slots.
  void setArmed(int slot, bool armed) {
    if (_disposed || armed == state.armedSlots.contains(slot)) return;

    final slots = {...state.armedSlots};
    if (armed) {
      slots.add(slot);
      _rings[slot] = Queue<ClipFrame>();
    } else {
      slots.remove(slot);
      // A camera leaving mid-capture seals with what it has — the other
      // angle must not be held hostage to an unplugged device.
      final trigger = _triggerAt;
      if (trigger != null && _capturingSlots.contains(slot)) {
        _sealSlot(slot, trigger);
      }
      _rings.remove(slot);
    }

    state = ImpactClipState(
      armedSlots: Set.unmodifiable(slots),
      capturing: state.capturing,
      clips: state.clips,
      bufferedFrames: _totalBuffered(),
    );
    _maybeFinish();
  }

  /// Offers one frame from [slot], already JPEG-encoded by that camera's
  /// worker isolate. [at] is the worker's capture timestamp — wall clock,
  /// which every isolate shares, so all angles line up with the BLE trigger
  /// stamped here.
  void offer(int slot, Uint8List jpeg, DateTime at) {
    if (_disposed) return;
    final ring = _rings[slot];
    if (ring == null) return;

    ring.add(ClipFrame(jpeg: jpeg, at: at));

    final trigger = _triggerAt;
    if (trigger == null || !_capturingSlots.contains(slot)) {
      // Free-running: keep only the pre-roll window.
      final cutoff = at.subtract(preRoll);
      while (ring.length > 1 && ring.first.at.isBefore(cutoff)) {
        ring.removeFirst();
      }
      _publishBufferSize();
      return;
    }

    // Capturing: hold everything until the post-roll is complete, otherwise
    // trimming would eat the pre-roll we are here for.
    if (at.difference(trigger) >= postRoll) {
      _sealSlot(slot, trigger);
      _maybeFinish();
    } else {
      _publishBufferSize();
    }
  }

  void _onShot(int shotIndex) {
    if (_disposed || state.armedSlots.isEmpty) return;
    // A second shot inside the post-roll window keeps the capture already in
    // progress: splitting it would hand back clips with no whole swing in
    // either.
    if (_triggerAt != null) {
      debugPrint('[clip] shot $shotIndex arrived mid-capture; folded in');
      return;
    }
    _triggerAt = DateTime.now();
    _pendingShotIndex = shotIndex;
    _capturingSlots
      ..clear()
      ..addAll(state.armedSlots);
    _pendingAngles.clear();
    state = ImpactClipState(
      armedSlots: state.armedSlots,
      capturing: true,
      clips: state.clips,
      bufferedFrames: _totalBuffered(),
    );
    final preRollCounts = [
      for (final slot in _capturingSlots.toList()..sort())
        'slot $slot: ${_rings[slot]?.length ?? 0}',
    ].join(', ');
    debugPrint('[clip] shot $shotIndex — pre-roll $preRollCounts');
  }

  void _sealSlot(int slot, DateTime trigger) {
    if (!_capturingSlots.remove(slot)) return;
    final ring = _rings[slot];
    if (ring == null || ring.isEmpty) return;

    final frames = List<ClipFrame>.unmodifiable(ring);
    ring.clear();

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
    _pendingAngles[slot] = clip;

    debugPrint(
      '[clip] slot $slot sealed shot ${clip.shotIndex}: '
      '${clip.frameCount} frames, ${clip.duration.inMilliseconds}ms, '
      '${clip.effectiveFps.toStringAsFixed(1)}fps, '
      'trigger at ${clip.triggerIndex}, '
      '${(clip.byteSize / (1024 * 1024)).toStringAsFixed(1)}MB',
    );
  }

  /// Publishes the shot once every capturing slot has sealed.
  void _maybeFinish() {
    final trigger = _triggerAt;
    if (trigger == null || _capturingSlots.isNotEmpty) return;
    _triggerAt = null;

    if (_pendingAngles.isEmpty) {
      state = ImpactClipState(
        armedSlots: state.armedSlots,
        capturing: false,
        clips: state.clips,
        bufferedFrames: _totalBuffered(),
      );
      return;
    }

    final shot = ShotClips(
      shotIndex: _pendingShotIndex,
      capturedAt: trigger,
      angles: Map.unmodifiable(Map.of(_pendingAngles)),
    );
    _pendingAngles.clear();

    final clips = [shot, ...state.clips];
    state = ImpactClipState(
      armedSlots: state.armedSlots,
      capturing: false,
      clips: List.unmodifiable(
        clips.length > maxClips ? clips.sublist(0, maxClips) : clips,
      ),
      bufferedFrames: _totalBuffered(),
    );

    debugPrint(
      '[clip] shot ${shot.shotIndex} complete: ${shot.angleCount} angle(s), '
      '${(shot.byteSize / (1024 * 1024)).toStringAsFixed(1)}MB total',
    );
  }

  /// Drops every retained shot. The only way to hand back the memory short
  /// of leaving the session.
  void clearClips() {
    if (_disposed) return;
    state = ImpactClipState(
      armedSlots: state.armedSlots,
      capturing: state.capturing,
      bufferedFrames: state.bufferedFrames,
    );
  }

  int _totalBuffered() =>
      _rings.values.fold<int>(0, (sum, ring) => sum + ring.length);

  void _publishBufferSize() {
    final total = _totalBuffered();
    if (state.bufferedFrames == total) return;
    final now = DateTime.now();
    if (now.difference(_lastCountPublish) < _countPublishInterval) return;
    _lastCountPublish = now;
    state = ImpactClipState(
      armedSlots: state.armedSlots,
      capturing: state.capturing,
      clips: state.clips,
      bufferedFrames: total,
    );
  }
}
