import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/pga_sim_profiles.dart';

void main() {
  group('generatePgaTourShot', () {
    final rng = math.Random(42);

    ({double mean, double sd}) carryStats(String clubId, {int n = 300}) {
      final carries = [
        for (var i = 0; i < n; i++)
          generatePgaTourShot(clubId, rng).carry,
      ];
      final mean = carries.reduce((a, b) => a + b) / n;
      final variance =
          carries.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) /
              (n - 1);
      return (mean: mean, sd: math.sqrt(variance));
    }

    test('driver carry ~ PGA Tour average (275 yds)', () {
      final s = carryStats('dr');
      // Tolerance is generous — the app's trajectory model, not the table,
      // decides carry. This guards against gross drift, not exact match.
      expect(s.mean, inInclusiveRange(255, 295),
          reason: 'driver mean carry ${s.mean.toStringAsFixed(1)}');
      expect(s.sd, inInclusiveRange(3, 18),
          reason: 'driver carry SD ${s.sd.toStringAsFixed(1)}');
    });

    test('7-iron carry ~ PGA Tour average (172 yds)', () {
      final s = carryStats('7i');
      expect(s.mean, inInclusiveRange(157, 187),
          reason: '7i mean carry ${s.mean.toStringAsFixed(1)}');
      expect(s.sd, inInclusiveRange(2, 14),
          reason: '7i carry SD ${s.sd.toStringAsFixed(1)}');
    });

    test('pitching wedge carry ~ PGA Tour average (136 yds)', () {
      final s = carryStats('pw');
      expect(s.mean, inInclusiveRange(121, 151),
          reason: 'pw mean carry ${s.mean.toStringAsFixed(1)}');
    });

    test('carry ladder is monotonic through the bag', () {
      const ladder = ['dr', '3w', '5w', '4i', '6i', '8i', 'pw', 'sw', '60deg'];
      final means = [for (final c in ladder) carryStats(c, n: 150).mean];
      for (var i = 1; i < means.length; i++) {
        expect(means[i], lessThan(means[i - 1]),
            reason:
                '${ladder[i]} (${means[i].toStringAsFixed(0)}) should carry '
                'less than ${ladder[i - 1]} (${means[i - 1].toStringAsFixed(0)})');
      }
    });

    test('putter stays on the ground', () {
      for (var i = 0; i < 50; i++) {
        final shot = generatePgaTourShot('pt', rng);
        expect(shot.totalDistance, lessThan(30));
      }
    });

    test('unknown club falls back to mid-iron numbers', () {
      final s = carryStats('mystery-club');
      expect(s.mean, inInclusiveRange(150, 195));
    });
  });
}
