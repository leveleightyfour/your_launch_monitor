import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/hole_builder.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

// The app defaults to metres, so that is the default fixture too.
const _prefs = UnitPrefs();
const _yardPrefs = UnitPrefs(distance: DistanceUnit.yards);

/// The sheet is tall — the default 800x600 test surface clips the action row
/// and taps on it silently miss.
void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  HoleSetup hole, {
  UnitPrefs prefs = _prefs,
}) async {
  _bigScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HoleBuilderSheet(hole: hole, prefs: prefs),
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

  testWidgets('a yard profile gets five-yard cells', (tester) async {
    await _open(tester, const HoleSetup(enabled: true, greenDistance: 165),
        prefs: _yardPrefs);
    final state =
        tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));

    expect(state.currentGrid.cellSize, 5.0);
    tester.takeException();
  });

  testWidgets('a metric profile gets five-metre cells, still kept in yards',
      (tester) async {
    // Only the size of the square follows the preference. The grid stays in
    // yards because the trajectory and the ground models are.
    await _open(tester, const HoleSetup(enabled: true, greenDistance: 165));
    final state =
        tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));

    expect(state.currentGrid.cellSize, closeTo(5.4681, 0.001));
    tester.takeException();
  });

  testWidgets('there is no grid-size control to get wrong', (tester) async {
    await _open(tester, const HoleSetup(enabled: true, greenDistance: 165));

    expect(find.text('Grid size'), findsNothing);
    tester.takeException();
  });

  testWidgets('the hole extends and shortens from the far end',
      (tester) async {
    const hole = HoleSetup(enabled: true, greenDistance: 165);
    await _open(tester, hole);

    final state =
        tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));
    final before = state.currentGrid;
    // Paint something near the tee so it can be checked for survival.
    final marked = before.withCell(0, 0, Terrain.bunker);
    expect(marked.at(0, 0), Terrain.bunker);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 200));

    final longer = state.currentGrid;
    expect(longer.rows, before.rows + HoleGrid.lengthStepCells);
    expect(longer.cols, before.cols, reason: 'width must not change');
    expect(longer.cellSize, before.cellSize);
    // The tee end is untouched and the new ground is rough.
    expect(longer.at(0, 0), before.at(0, 0));
    expect(longer.at(0, longer.rows - 1), Terrain.rough);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump(const Duration(milliseconds: 200));

    expect(state.currentGrid.rows, before.rows);
    tester.takeException();
  });

  testWidgets('the sheet is the same height whatever the hole length',
      (tester) async {
    await _open(tester, const HoleSetup(enabled: true, greenDistance: 120));
    final short = tester.getSize(find.byType(HoleBuilderSheet));

    await _open(tester, const HoleSetup(enabled: true, greenDistance: 600));
    final long = tester.getSize(find.byType(HoleBuilderSheet));

    // The plan scrolls instead of the modal growing.
    expect(long.height, short.height);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
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

  group('distance markers', () {
    test('the step is a round number and never crowds the plan', () {
      // A 600-yard par 5 should get the same handful of lines a pitch-and-putt
      // does, so the step grows with the hole rather than the count.
      for (final length in [40.0, 90.0, 150.0, 230.0, 400.0, 600.0, 900.0]) {
        final step = distanceMarkerStep(length);

        expect(const [10.0, 25.0, 50.0, 100.0, 200.0], contains(step),
            reason: '$length gave a step of $step, which is not a round one');
        expect(length / step, lessThanOrEqualTo(8.0),
            reason: '$length would draw ${length ~/ step} lines');
      }
    });

    test('short holes get finer marks than long ones', () {
      expect(distanceMarkerStep(60), lessThan(distanceMarkerStep(600)));
      expect(distanceMarkerStep(80), 10.0);
      expect(distanceMarkerStep(230), 50.0);
    });

    test('a hole too long for the biggest step still gets marks', () {
      expect(distanceMarkerStep(5000), 200.0);
    });
  });

  testWidgets('the hole widens and narrows about the target line',
      (tester) async {
    await _open(tester, const HoleSetup(enabled: true, greenDistance: 165));
    final state =
        tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));
    final before = state.currentGrid;

    // Distinct icons from the length bar, so the two controls are separable
    // by touch and by test.
    await tester.tap(find.byIcon(Icons.unfold_more));
    await tester.pump(const Duration(milliseconds: 200));

    final wide = state.currentGrid;
    expect(wide.cols, before.cols + HoleGrid.widthStepCells);
    expect(wide.rows, before.rows, reason: 'length must not change');
    expect(wide.left, -wide.width / 2, reason: 'centre drifted');

    await tester.tap(find.byIcon(Icons.unfold_less));
    await tester.pump(const Duration(milliseconds: 200));

    expect(state.currentGrid.cols, before.cols);
    tester.takeException();
  });

  testWidgets('length and width are separate controls', (tester) async {
    await _open(tester, const HoleSetup(enabled: true, greenDistance: 165));
    final state =
        tester.state<HoleBuilderSheetState>(find.byType(HoleBuilderSheet));
    final before = state.currentGrid;

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 200));

    // Lengthening leaves the width alone...
    expect(state.currentGrid.cols, before.cols);
    expect(state.currentGrid.rows, greaterThan(before.rows));

    await tester.tap(find.byIcon(Icons.unfold_more));
    await tester.pump(const Duration(milliseconds: 200));

    // ...and widening leaves the new length alone.
    expect(state.currentGrid.rows,
        before.rows + HoleGrid.lengthStepCells);
    expect(state.currentGrid.cols, before.cols + HoleGrid.widthStepCells);
    tester.takeException();
  });
}
