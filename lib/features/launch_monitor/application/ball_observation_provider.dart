/// Holds the ball-position log for the app's lifetime and writes it out.
///
/// Deliberately not Riverpod state: the log takes a sample on every sensor
/// frame, and nothing watches it continuously. It is read when the panel opens
/// and when it is exported. Rebuilding widgets ten times a second for a record
/// nobody is looking at would be pure cost.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/data/ball_observation_log.dart';

final ballObservationLogProvider = Provider<BallObservationRecorder>((ref) {
  final recorder = BallObservationRecorder();
  unawaited(recorder.restore());
  ref.onDispose(recorder.dispose);
  return recorder;
});

class BallObservationRecorder {
  BallObservationLog _log = BallObservationLog();
  Timer? _saveTimer;
  bool _dirty = false;

  BallObservationLog get log => _log;

  /// Pick up what earlier sessions recorded. The zone does not move between
  /// runs, so every session's samples are worth keeping.
  Future<void> restore() async {
    final stored = await BallObservationLog.load();
    // A session that started recording before the file came back keeps what it
    // has; merging is not worth the complexity for a diagnostic log.
    if (_log.bucketCount == 0) _log = stored;
  }

  void record({
    required double depthMm,
    required double lateralMm,
    required bool ready,
  }) {
    _log.record(depthMm: depthMm, lateralMm: lateralMm, ready: ready);
    _dirty = true;
    // Batched: writing a file on every frame would be absurd, and losing the
    // last few seconds of samples on a crash costs nothing.
    _saveTimer ??= Timer.periodic(const Duration(seconds: 20), (_) => flush());
  }

  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    await _log.save();
  }

  Future<void> clear() async {
    _log = BallObservationLog();
    _dirty = false;
    await BallObservationLog.erase();
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(flush());
  }
}
