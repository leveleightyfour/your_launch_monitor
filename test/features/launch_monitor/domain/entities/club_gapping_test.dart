import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club_gapping.dart';

const _club = Club(id: '7i', shortName: '7i', color: Color(0xFFF489FA));

void main() {
  group('quantile', () {
    test('median of an odd-length list is the middle value', () {
      expect(quantile([1, 2, 100], 0.5), 2);
    });

    test('median of an even-length list interpolates', () {
      expect(quantile([1, 2, 3, 4], 0.5), 2.5);
    });

    test('empty list yields zero', () {
      expect(quantile([], 0.5), 0);
    });
  });

  group('ClubCarryStats', () {
    test('a duffed chunk falls outside the fence', () {
      // Tour-like 7-iron carries plus one 40-yard chunk.
      final carries = [168.0, 170.0, 171.0, 172.0, 173.0, 174.0, 176.0, 40.0];
      final stats = ClubCarryStats.fromCarries(_club, carries);
      expect(stats.excluded, [40.0]);
      expect(stats.kept.length, 7);
      expect(stats.shortest, 168.0);
      expect(stats.totalCount, 8);
    });

    test('a flyer falls outside the fence too', () {
      final carries = [150.0, 151.0, 152.0, 153.0, 154.0, 155.0, 210.0];
      final stats = ClubCarryStats.fromCarries(_club, carries);
      expect(stats.excluded, [210.0]);
      expect(stats.longest, 155.0);
    });

    test('includeOutliers keeps everything', () {
      final carries = [150.0, 151.0, 152.0, 153.0, 40.0];
      final stats = ClubCarryStats.fromCarries(
        _club,
        carries,
        includeOutliers: true,
      );
      expect(stats.excluded, isEmpty);
      expect(stats.kept.length, 5);
      expect(stats.shortest, 40.0);
    });

    test('fewer than four shots are never fenced', () {
      final stats = ClubCarryStats.fromCarries(_club, [150.0, 40.0, 152.0]);
      expect(stats.excluded, isEmpty);
      expect(stats.kept.length, 3);
    });

    test('a tight spread keeps every shot', () {
      final carries = [160.0, 161.0, 162.0, 163.0, 164.0, 165.0];
      final stats = ClubCarryStats.fromCarries(_club, carries);
      expect(stats.excluded, isEmpty);
      expect(stats.median, 162.5);
      expect(stats.average, closeTo(162.5, 0.001));
    });
  });
}
