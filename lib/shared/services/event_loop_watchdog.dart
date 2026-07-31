/// Detects the app's event loop being starved.
///
/// A stalled UI has two very different causes that look identical from the
/// outside: work so heavy that frames come slowly, or a loop that never hands
/// the event loop a turn at all. This tells them apart. A periodic timer is
/// itself an event-loop task, so if it fires late, by definition nothing else
/// got a turn either — and the lateness is the measurement.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

class EventLoopWatchdog {
  /// How often to check in. Short enough to catch a stall while it is still
  /// attributable to whatever caused it.
  static const _interval = Duration(milliseconds: 100);

  /// Lateness worth reporting. Frame scheduling and GC routinely cost tens of
  /// milliseconds, so this sits above that — but low enough to catch the
  /// hundred-millisecond hitches that read as lag rather than as a freeze.
  static const _threshold = Duration(milliseconds: 120);

  /// Ticks between heartbeats — 5 seconds at the 100ms interval.
  ///
  /// The heartbeat is what makes silence in the log interpretable. Without
  /// it, "no watchdog lines" is ambiguous three ways: the loop is healthy,
  /// the loop is *totally* starved (a starved loop can't run the timer that
  /// would report the starvation — lateness is only measured when the timer
  /// finally fires), or log output is being lost. With it: regular beats
  /// mean healthy, beats that stop mean starved or dead, beats that never
  /// appear mean the console isn't receiving prints.
  static const _beatEvery = 50;

  final String tag;

  Timer? _timer;
  Stopwatch? _since;
  int _stalls = 0;
  int _ticks = 0;
  Duration _worst = Duration.zero;

  EventLoopWatchdog(this.tag);

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null || !kDebugMode) return;
    _stalls = 0;
    _ticks = 0;
    _worst = Duration.zero;
    debugPrint('[watchdog:$tag] started');
    final since = Stopwatch()..start();
    _since = since;
    _timer = Timer.periodic(_interval, (_) {
      final late = since.elapsed - _interval;
      since.reset();
      if (++_ticks % _beatEvery == 0) {
        debugPrint(
          '[watchdog:$tag] alive · $_stalls stalls · '
          'worst ${_worst.inMilliseconds}ms',
        );
      }
      if (late <= _threshold) return;
      _stalls++;
      if (late > _worst) _worst = late;
      debugPrint(
        '[watchdog:$tag] event loop stalled ${late.inMilliseconds}ms '
        '(stall $_stalls, worst ${_worst.inMilliseconds}ms)',
      );
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _since = null;
    debugPrint(
      '[watchdog:$tag] stopped · $_stalls stalls · '
      'worst ${_worst.inMilliseconds}ms',
    );
  }
}
