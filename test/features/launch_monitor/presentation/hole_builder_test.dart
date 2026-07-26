import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/hole_builder.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

const _prefs = UnitPrefs();

/// The sheet is tall — the default 800x600 test surface clips the action row
/// and taps on it silently miss.
void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, HoleSetup hole) async {
  _bigScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HoleBuilderSheet(hole: hole, prefs: _prefs),
      ),
    ),
  );
  // pumpAndSettle never returns on these screens — something animates.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('opens on the hole already configured, not a blank sheet',
      (tester) async {
    // A player who has set up a par 3 should find that par 3 waiting, so the
    // builder is somewhere to adjust from rather than start over.
    const hole = HoleSetup(enabled: true, greenDistance: 165, fairwayWidth: 40);
    await _open(tester, hole);

    expect(find.text('Hole builder'), findsOneWidget);
    // Every terrain is offered as a brush.
    for (final t in Terrain.values) {
      expect(find.text(t.label), findsOneWidget);
    }
    tester.takeException();
  });

  testWidgets('the seeded grid carries the analytic hole across',
      (tester) async {
    const hole = HoleSetup(enabled: true, greenDistance: 165, fairwayWidth: 40);
    await _open(tester, hole);

    final grid = seedHoleGrid(hole);

    // Down the middle short of the green is fairway; wide of it is rough; the
    // green itself is where the setup said it was.
    expect(grid.terrainAt(0, 80), Terrain.fairway);
    expect(grid.terrainAt(60, 80), Terrain.rough);
    expect(grid.terrainAt(0, 165), Terrain.green);
    tester.takeException();
  });

  testWidgets('a disabled hole seeds as empty ground', (tester) async {
    await _open(tester, const HoleSetup());

    final grid = seedHoleGrid(const HoleSetup());

    expect(grid.cells.every((c) => c == Terrain.rough), isTrue);
    tester.takeException();
  });

  testWidgets('cancel pops with nothing; Use hole pops with the grid',
      (tester) async {
    // Pushed as an ordinary route rather than the modal sheet: what is worth
    // testing is that the buttons hand back the right value, not that Flutter
    // can animate a bottom sheet away.
    _bigScreen(tester);
    HoleSetup? returned;
    var done = false;

    Future<void> openThenTap(String button) async {
      returned = null;
      done = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                returned = await Navigator.of(ctx).push<HoleSetup>(
                  MaterialPageRoute<HoleSetup>(
                    builder: (_) => const Scaffold(
                      body: HoleBuilderSheet(
                        hole: HoleSetup(enabled: true, greenDistance: 165),
                        prefs: _prefs,
                      ),
                    ),
                  ),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Hole builder'), findsOneWidget);

      await tester.tap(find.text(button));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await openThenTap('Cancel');
    expect(done, isTrue, reason: 'Cancel did not close the builder');
    expect(returned, isNull);

    await openThenTap('Use hole');
    expect(done, isTrue);
    expect(returned, isNotNull);
    expect(returned!.enabled, isTrue);
    expect(returned!.grid, isNotNull,
        reason: 'the painted grid has to come back with the hole');
    tester.takeException();
  });

  testWidgets('the grid-size stepper resamples without losing the paint',
      (tester) async {
    const hole = HoleSetup(enabled: true, greenDistance: 165, fairwayWidth: 40);
    await _open(tester, hole);

    final state = tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));
    final HoleGrid before = state.currentGrid;
    expect(before.cellSize, HoleGrid.defaultCellSize);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 200));

    final HoleGrid after = state.currentGrid;
    expect(after.cellSize, HoleGrid.defaultCellSize + 1);
    // The ground it covers is unchanged, and so is what was painted on it.
    expect(after.width, closeTo(before.width, after.cellSize));
    expect(after.terrainAt(0, 80), Terrain.fairway);
    expect(after.terrainAt(0, 165), Terrain.green);
    tester.takeException();
  });

  testWidgets('clear wipes the plan but keeps its dimensions', (tester) async {
    const hole = HoleSetup(enabled: true, greenDistance: 165);
    await _open(tester, hole);

    final state = tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));
    final HoleGrid before = state.currentGrid;

    await tester.tap(find.text('Clear'));
    await tester.pump(const Duration(milliseconds: 200));

    final HoleGrid after = state.currentGrid;
    expect(after.cells.every((c) => c == Terrain.rough), isTrue);
    expect(after.cols, before.cols);
    expect(after.rows, before.rows);
    tester.takeException();
  });

  testWidgets('undo steps back through the painting', (tester) async {
    const hole = HoleSetup(enabled: true, greenDistance: 165);
    await _open(tester, hole);

    final state = tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));
    final HoleGrid original = state.currentGrid;

    await tester.tap(find.text('Clear'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.currentGrid, isNot(original));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump(const Duration(milliseconds: 200));

    expect(state.currentGrid, original);
    tester.takeException();
  });
}
