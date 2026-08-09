/// A metric with no unit — smash factor is the one in the default grid — used
/// to drop the unit row entirely, handing its height to the value box above.
/// That tile then sized its digits against a taller box than its neighbours,
/// so the number came out larger and sat lower than every other tile in the
/// row. These measure the rendered geometry rather than trusting the layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/split_flap_text.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Ball 131.8 / club 92 puts smash at 1.43 — a real value, so the unitless
/// tile renders digits rather than the '--' placeholder.
const _shot = ShotData(
  dbId: 1,
  clubId: '7i',
  ballSpeed: 131.8,
  spinRate: 5500,
  spinAxis: 2.1,
  launchDirection: 1.1,
  launchAngle: 17.3,
  clubSpeed: 92,
);

/// The default grid: CARRY, BALL SPD, SPIN RATE, LAUNCH ANGLE, CLUB SPD and
/// SMASH — five with units, one without.
Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: TilesTab(shots: [_shot])),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

/// How far a tile's value sits below its own label. Measured per tile rather
/// than against the screen, because the grid puts the six metrics on two rows
/// — an absolute comparison would only be testing which row a tile landed in.
double _valueDrop(WidgetTester tester, String label, String value) {
  final labelFinder = find.text(label);
  final valueFinder = find.ancestor(
    of: find.text(value),
    matching: find.byType(SplitFlapText),
  );
  expect(labelFinder, findsOneWidget, reason: 'no tile labelled "$label"');
  expect(valueFinder, findsOneWidget, reason: 'no value rendering "$value"');
  return tester.getCenter(valueFinder).dy - tester.getCenter(labelFinder).dy;
}

void main() {
  testWidgets('the unitless tile keeps its neighbours\' digit size', (
    tester,
  ) async {
    await _pump(tester, const Size(1000, 700));

    expect(find.text('SMASH'), findsOneWidget, reason: 'smash tile is missing');
    expect(TileMetric.smashFactor.unit, isEmpty, reason: 'smash gained a unit');

    // One size across the grid, smash included. Before the fix its box was a
    // unit-line taller, so it resolved to a larger size than the rest.
    final sizes = tester
        .widgetList<SplitFlapText>(find.byType(SplitFlapText))
        .map((w) => w.style.fontSize)
        .toSet();
    expect(sizes, hasLength(1));
  });

  testWidgets('the unitless tile sits on its neighbours\' line', (tester) async {
    await _pump(tester, const Size(1000, 700));

    // Smash (1.43, no unit) against club speed (92.0, 'mph') and ball speed
    // (131.8, 'mph'). Every tile is the same height, so an equal drop from
    // label to value means the digits share a line across the grid.
    final smash = _valueDrop(tester, 'SMASH', '1.43');
    expect(smash, moreOrLessEquals(_valueDrop(tester, 'CLUB SPD', '92.0')));
    expect(smash, moreOrLessEquals(_valueDrop(tester, 'BALL SPD', '131.8')));
  });

  testWidgets('alignment survives a cramped split', (tester) async {
    // The narrow case reflows the grid and may drop the unit row on every
    // tile at once; either way the unitless tile must not drift on its own.
    // Overflow throws through FlutterError.onError, so pumping small is an
    // assertion in itself.
    await _pump(tester, const Size(360, 480));

    expect(
      _valueDrop(tester, 'SMASH', '1.43'),
      moreOrLessEquals(_valueDrop(tester, 'CLUB SPD', '92.0')),
    );
  });
}
