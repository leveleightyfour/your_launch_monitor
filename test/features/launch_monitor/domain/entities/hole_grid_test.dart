import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';

ShotData _shot({HoleSetup? hole, double launchDirection = 0}) => ShotData(
      clubId: '7i',
      ballSpeed: 120,
      spinRate: 6500,
      spinAxis: 0,
      launchDirection: launchDirection,
      launchAngle: 18,
      clubSpeed: 86,
      hole: hole,
    );

void main() {
  group('geometry', () {
    test('a blank grid covers the ground it was asked for', () {
      final g = HoleGrid.blank(cellSize: 5, width: 100, length: 300);

      expect(g.cols, 20);
      expect(g.rows, 60);
      expect(g.width, 100);
      expect(g.length, 300);
      expect(g.left, -50);
      expect(g.cells.length, 1200);
    });

    test('columns are centred on the target line', () {
      final g = HoleGrid.blank(cellSize: 10, width: 100, length: 100);

      expect(g.colFor(-50), 0);
      expect(g.colFor(-0.1), 4);
      expect(g.colFor(0), 5);
      expect(g.colFor(49.9), 9);
      expect(g.colFor(-51), isNull);
      expect(g.colFor(50), isNull);
    });

    test('rows start at the tee and run downrange', () {
      final g = HoleGrid.blank(cellSize: 10, width: 40, length: 100);

      expect(g.rowFor(0), 0);
      expect(g.rowFor(95), 9);
      expect(g.rowFor(-1), isNull, reason: 'behind the tee is off the grid');
      expect(g.rowFor(100), isNull);
    });

    test('off the grid is out of bounds, not more rough', () {
      // A built hole has been told where its edges are, so leaving it means
      // something — unlike the analytic hole, where the world runs on forever.
      final g = HoleGrid.blank(width: 40, length: 100, fill: Terrain.fairway);

      expect(g.terrainAt(0, 50), Terrain.fairway);
      expect(g.terrainAt(500, 50), Terrain.outOfBounds);
      expect(g.terrainAt(0, -10), Terrain.outOfBounds);
    });
  });

  group('painting', () {
    test('one cell changes without disturbing its neighbours', () {
      final g = HoleGrid.blank(cellSize: 10, width: 40, length: 40);
      final painted = g.withCell(1, 2, Terrain.bunker);

      expect(painted.at(1, 2), Terrain.bunker);
      expect(painted.at(0, 2), Terrain.rough);
      expect(g.at(1, 2), Terrain.rough, reason: 'the original is untouched');
    });

    test('a block paints a rectangle and clips at the edges', () {
      final g = HoleGrid.blank(cellSize: 10, width: 40, length: 40);
      final painted = g.withBlock(-5, -5, 1, 1, Terrain.water);

      expect(painted.at(0, 0), Terrain.water);
      expect(painted.at(1, 1), Terrain.water);
      expect(painted.at(2, 2), Terrain.rough);
    });

    test('a drag painted backwards covers the same rectangle', () {
      final g = HoleGrid.blank(cellSize: 10, width: 40, length: 40);

      expect(
        g.withBlock(2, 3, 0, 1, Terrain.green),
        g.withBlock(0, 1, 2, 3, Terrain.green),
      );
    });
  });

  group('run-length encoding', () {
    test('a uniform hole encodes to almost nothing', () {
      final g = HoleGrid.blank(cellSize: 5, width: 120, length: 400);

      // 1,920 cells in four characters.
      expect(g.encode(), '1920r');
      expect(g.encode().length, lessThan(10));
    });

    test('a realistic hole stays small enough to sit on every shot', () {
      // Fairway corridor with a bunker and water down one side.
      var g = HoleGrid.blank(cellSize: 5, width: 120, length: 400);
      g = g.withBlock(8, 0, 15, 60, Terrain.fairway);
      g = g.withBlock(10, 30, 13, 36, Terrain.green);
      g = g.withBlock(16, 20, 18, 24, Terrain.bunker);
      g = g.withBlock(19, 40, 23, 55, Terrain.water);

      expect(g.encode().length, lessThan(700),
          reason: 'encoded ${g.encode().length} bytes — too big per row');
    });

    test('a single cell does not carry a count', () {
      final g = HoleGrid.blank(cellSize: 10, width: 30, length: 10)
          .withCell(1, 0, Terrain.bunker);

      expect(g.encode(), 'rbr');
    });

    test('survives a JSON round trip with every terrain in it', () {
      var g = HoleGrid.blank(cellSize: 5, width: 60, length: 60);
      var i = 0;
      for (final t in Terrain.values) {
        g = g.withCell(i % g.cols, i, t);
        i++;
      }

      expect(HoleGrid.fromJson(g.toJson()), g);
    });

    test('an unknown terrain code reads as rough rather than throwing', () {
      // A hole written by a newer build. Rough is the safe read: neither a
      // free ride nor a penalty.
      final g = HoleGrid.fromJson(const {
        'cell': 5.0,
        'cols': 2,
        'rows': 1,
        'g': 'fZ',
      });

      expect(g.cells, [Terrain.fairway, Terrain.rough]);
    });

    test('truncated data is padded, not rejected', () {
      final g = HoleGrid.fromJson(const {
        'cell': 5.0,
        'cols': 4,
        'rows': 1,
        'g': '2f',
      });

      expect(g.cells.length, 4);
      expect(g.cells, [
        Terrain.fairway,
        Terrain.fairway,
        Terrain.rough,
        Terrain.rough,
      ]);
    });

    test('a corrupt run length cannot allocate beyond the grid', () {
      final g = HoleGrid.fromJson(const {
        'cell': 5.0,
        'cols': 2,
        'rows': 1,
        'g': '999999999f',
      });

      expect(g.cells.length, 2);
    });
  });

  group('resizing', () {
    test('coarser cells keep the ground covered', () {
      final g = HoleGrid.blank(cellSize: 5, width: 100, length: 200);
      final coarse = g.resized(10);

      expect(coarse.cellSize, 10);
      expect(coarse.width, 100);
      expect(coarse.length, 200);
      expect(coarse.cols, 10);
      expect(coarse.rows, 20);
    });

    test('what was painted survives a change of cell size', () {
      var g = HoleGrid.blank(cellSize: 5, width: 100, length: 100);
      g = g.withBlock(0, 0, 9, 9, Terrain.fairway); // the left half, near end
      final coarse = g.resized(10);

      expect(coarse.terrainAt(-40, 20), Terrain.fairway);
      expect(coarse.terrainAt(40, 80), Terrain.rough);
    });

    test('cell size is clamped to something drawable', () {
      final g = HoleGrid.blank(cellSize: 5, width: 100, length: 100);

      expect(g.resized(0.1).cellSize, HoleGrid.minCellSize);
      expect(g.resized(500).cellSize, HoleGrid.maxCellSize);
    });

    test('resizing to the same size is a no-op', () {
      final g = HoleGrid.blank(cellSize: 5, width: 40, length: 40);

      expect(identical(g.resized(5), g), isTrue);
    });
  });

  group('terrain physics', () {
    test('each terrain resolves to a ground model', () {
      expect(Terrain.fairway.ground, GroundModel.fairway);
      expect(Terrain.green.ground, GroundModel.green);
      expect(Terrain.bunker.ground, GroundModel.bunker);
      // Under the trees is rough, because that is what it would be.
      expect(Terrain.trees.ground, GroundModel.rough);
    });

    test('sand stops the ball harder than rough does', () {
      expect(GroundModel.bunker.rollingResistance,
          greaterThan(GroundModel.rough.rollingResistance));
      expect(GroundModel.bunker.restitutionScale,
          lessThan(GroundModel.rough.restitutionScale));
    });

    test('only water and out of bounds end the shot', () {
      for (final t in Terrain.values) {
        final ends = t == Terrain.water || t == Terrain.outOfBounds;
        expect(t.stopsShot, ends, reason: t.name);
      }
    });
  });

  group('a grid hole drives the simulation', () {
    HoleSetup gridHole(Terrain fill) => HoleSetup(
          enabled: true,
          grid: HoleGrid.blank(
              cellSize: 10, width: 200, length: 400, fill: fill),
        );

    test('the grid overrides the analytic fairway and green', () {
      final hole = HoleSetup(
        enabled: true,
        greenDistance: 165,
        grid: HoleGrid.blank(
            cellSize: 10, width: 200, length: 400, fill: Terrain.bunker),
      );

      // The analytic description says there is a green at 165. The grid says
      // the whole hole is sand, and the grid wins.
      expect(hole.terrainAt(0, 165), Terrain.bunker);
      expect(hole.groundAt(0, 165), GroundModel.bunker);
    });

    test('landing in sand kills the roll', () {
      final onFairway = _shot(hole: gridHole(Terrain.fairway));
      final inSand = _shot(hole: gridHole(Terrain.bunker));

      expect(inSand.carry, closeTo(onFairway.carry, 0.001),
          reason: 'the flight is identical — only the landing differs');
      expect(inSand.rollDistance, lessThan(onFairway.rollDistance));
      expect(inSand.totalDistance, lessThan(onFairway.totalDistance));
    });

    test('water ends the shot where it pitches', () {
      final dry = _shot(hole: gridHole(Terrain.fairway));
      final wet = _shot(hole: gridHole(Terrain.water));

      expect(wet.outcome, ShotOutcome.water);
      expect(dry.outcome, ShotOutcome.inPlay);
      // No run-out at all: it stops at the pitch mark.
      expect(wet.rollDistance.abs(), lessThan(1.0));
      expect(wet.totalDistance, lessThan(dry.totalDistance));
    });

    test('a shot leaving the grid is out of bounds', () {
      // A narrow hole, and a shot pushed well right of it.
      final hole = HoleSetup(
        enabled: true,
        grid: HoleGrid.blank(
            cellSize: 5, width: 30, length: 400, fill: Terrain.fairway),
      );
      final pushed = _shot(hole: hole, launchDirection: 12);

      expect(pushed.trajectory.offline.abs(), greaterThan(15));
      expect(pushed.outcome, ShotOutcome.outOfBounds);
    });

    test('an unbuilt hole behaves exactly as it always did', () {
      const analytic = HoleSetup(enabled: true, greenDistance: 165);
      final withGrid = _shot(hole: analytic);
      final plain = _shot(hole: const HoleSetup());

      expect(analytic.grid, isNull);
      expect(withGrid.outcome, ShotOutcome.inPlay);
      expect(plain.outcome, ShotOutcome.inPlay);
      expect(analytic.terrainAt(0, 165), Terrain.green);
      expect(analytic.terrainAt(0, 60), Terrain.fairway);
      expect(analytic.terrainAt(90, 60), Terrain.rough);
    });

    test('a built hole survives being stamped on a shot and read back', () {
      var g = HoleGrid.blank(cellSize: 10, width: 100, length: 200);
      g = g.withBlock(3, 0, 6, 15, Terrain.fairway);
      final hole = HoleSetup(enabled: true, grid: g);

      final restored = HoleSetup.fromJson(hole.toJson());

      expect(restored, hole);
      expect(restored.grid!.at(4, 4), Terrain.fairway);
    });
  });
}
