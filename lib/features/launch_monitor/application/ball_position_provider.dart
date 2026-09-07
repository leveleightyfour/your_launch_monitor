/// Live ball position on the mat.
///
/// Deliberately its own provider rather than another field on
/// [LaunchMonitorState]. The launch-monitor state is watched by the whole
/// session screen, the watch payload and the stats providers; they all get away
/// with it today because every one of them uses `.select` and the fields they
/// select — a status, a shot list, two booleans — change rarely. A coordinate
/// that moves at sensor-frame rate does not belong in that object, where a
/// single careless `ref.watch(launchMonitorProvider)` would repaint the 3D tab
/// on every frame. Here, only the map subscribes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/ball_position.dart';

final ballPositionProvider =
    NotifierProvider<BallPositionNotifier, BallPosition?>(
      BallPositionNotifier.new,
    );

class BallPositionNotifier extends Notifier<BallPosition?> {
  @override
  BallPosition? build() => null;

  /// Feed in a position decoded from a sensor frame.
  ///
  /// Rounded to whole millimetres on the way in. The wire carries tenths, a
  /// ball sitting still jitters across that bottom digit, and at map scale a
  /// tenth of a millimetre is a fifth of a pixel — so keeping the precision
  /// would buy nothing and repaint the map on every frame for a ball that has
  /// not moved.
  void update(BallPosition next) {
    // Everything quantised to the same millimetre, the raw words included, so
    // equality stays coherent: rounding the millimetres but keeping the raw
    // tenths would make every frame a new value again and undo the whole
    // point of the rounding.
    int toWholeMm(int ticks) =>
        (ticks / ticksPerMm).round() * ticksPerMm.toInt();

    state = BallPosition(
      depthMm: next.depthMm.roundToDouble(),
      lateralMm: next.lateralMm.roundToDouble(),
      heightMm: next.heightMm.roundToDouble(),
      detected: next.detected,
      ready: next.ready,
      rawX: toWholeMm(next.rawX),
      rawY: toWholeMm(next.rawY),
      rawZ: toWholeMm(next.rawZ),
    );
  }

  /// Forget the last position — on disconnect, or when detection stops. A
  /// stale dot is worse than no dot: it says the ball is somewhere it may well
  /// not be any more.
  void clear() => state = null;

  /// [BallPosition] has value equality, and after the rounding above a
  /// stationary ball produces an identical value frame after frame. Comparing
  /// by value rather than identity turns those into no repaints at all.
  @override
  bool updateShouldNotify(BallPosition? previous, BallPosition? next) =>
      previous != next;
}
