import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';

void main() {
  group('resampling to a finer cell size', () {
    test('doubles the cell counts and keeps the painted ground', () {
      var coarse = HoleGrid.blank(cellSize: 5, width: 50, length: 100);
      coarse = coarse
          .withBlock(3, 0, 6, 18, Terrain.fairway)
          .withBlock(4, 14, 5, 16, Terrain.green)
          .withCell(1, 8, Terrain.bunker);

      final fine = coarse.resized(2.5);

      expect(fine.cellSize, 2.5);
      expect(fine.cols, coarse.cols * 2);
      expect(fine.rows, coarse.rows * 2);
      // The same world points answer the same terrain question.
      for (final (x, z) in const [
        (-7.5, 42.5), // bunker cell centre
        (0.0, 50.0), // fairway
        (-2.0, 77.5), // green
        (-20.0, 10.0), // rough
      ]) {
        expect(
          fine.terrainAt(x, z),
          coarse.terrainAt(x, z),
          reason: 'terrain at ($x, $z)',
        );
      }
    });

    test('a round trip back to coarse recovers block-painted ground', () {
      var coarse = HoleGrid.blank(cellSize: 5, width: 50, length: 100);
      coarse = coarse.withBlock(3, 0, 6, 18, Terrain.fairway);
      final back = coarse.resized(2.5).resized(5);
      expect(back.cols, coarse.cols);
      expect(back.rows, coarse.rows);
      expect(back.terrainAt(0, 50), Terrain.fairway);
      expect(back.terrainAt(-20, 10), Terrain.rough);
    });

    test('the requested size is clamped to the supported range', () {
      final g = HoleGrid.blank(cellSize: 5, width: 50, length: 100);
      expect(g.resized(0.1).cellSize, HoleGrid.minCellSize);
      expect(g.resized(100).cellSize, HoleGrid.maxCellSize);
    });
  });
}
