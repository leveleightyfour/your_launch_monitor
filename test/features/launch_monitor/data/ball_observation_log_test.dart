import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/ball_observation_log.dart';

void main() {
  group('what the log is for', () {
    // The ready zone cannot be read off the manual: its offsets are quoted from
    // the device's body, while the wire reports from the middle of the field of
    // view. The monitor knows, though — its light goes solid green inside the
    // zone — so the log watches instead of inferring.

    test('separates where a ball was seen from where it was called ready', () {
      final log = BallObservationLog()
        ..record(depthMm: 400, lateralMm: 100, ready: true)
        ..record(depthMm: 600, lateralMm: 100, ready: false);

      final seen = log.extentOf(log.observations)!;
      final ready = log.extentOf(log.readySquares)!;

      expect(seen.maxDepth, 600, reason: 'detection reaches further out');
      expect(ready.maxDepth, 400, reason: 'the zone stops short of it');
    });

    test('one ready sighting is enough to claim a square', () {
      // A square visited a hundred times without ever going green is outside;
      // one green frame says the zone reaches it. Requiring a majority would
      // erase the boundary squares, which are the ones being measured.
      final log = BallObservationLog();
      for (var i = 0; i < 100; i++) {
        log.record(depthMm: 400, lateralMm: 100, ready: false);
      }
      log.record(depthMm: 400, lateralMm: 100, ready: true);

      expect(log.readySquares, hasLength(1));
      final o = log.observations.single;
      expect(o.readyCount, 1);
      expect(o.detectedCount, 100);
    });

    test('a ball sitting still does not grow the log', () {
      // Frames arrive continuously. Without bucketing, a ball left on the mat
      // would bury the samples that actually map the boundary.
      final log = BallObservationLog();
      for (var i = 0; i < 500; i++) {
        log.record(depthMm: 400.4, lateralMm: 100.2, ready: true);
      }
      expect(log.bucketCount, 1);
      expect(log.frameCount, 500);
    });

    test('positions land on the bucket grid', () {
      final log = BallObservationLog()
        ..record(depthMm: 404, lateralMm: -96, ready: true);
      final o = log.observations.single;
      expect(o.depthMm % bucketMm, 0);
      expect(o.lateralMm % bucketMm, 0);
      expect(o.depthMm, 400);
      expect(o.lateralMm, -100);
    });
  });

  test('survives a round trip through storage', () {
    // Sessions accumulate: the zone does not move between app launches, so
    // every run's samples are worth keeping.
    final log = BallObservationLog()
      ..record(depthMm: 400, lateralMm: 100, ready: true)
      ..record(depthMm: 400, lateralMm: 100, ready: false)
      ..record(depthMm: -200, lateralMm: -50, ready: false);

    final restored = BallObservationLog.fromJsonString(log.toJsonString());

    expect(restored.bucketCount, log.bucketCount);
    expect(restored.frameCount, log.frameCount);
    expect(restored.readySquares, hasLength(1));
  });

  test('the report says both extents, and says so when the zone is unseen', () {
    final nothingReady = BallObservationLog()
      ..record(depthMm: 600, lateralMm: 0, ready: false);
    expect(nothingReady.report(), contains('Called ready: never'));

    final withZone = BallObservationLog()
      ..record(depthMm: 400, lateralMm: 100, ready: true);
    expect(withZone.report(), contains('Called ready: depth 400..400'));
  });
}
