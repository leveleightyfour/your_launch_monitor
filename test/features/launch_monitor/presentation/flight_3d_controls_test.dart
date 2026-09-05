import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';
import 'package:omni_sniffer/shared/theme.dart';

const _shot = ShotData(
  dbId: 1,
  clubId: '7i',
  ballSpeed: 120,
  spinRate: 6500,
  spinAxis: 0,
  launchDirection: 0,
  launchAngle: 18,
  clubSpeed: 85,
);

Future<void> _pumpTab(WidgetTester tester, {
  required bool canEditHole,
  ShotData shot = _shot,
}) async {
  tester.view.physicalSize = const Size(900, 650);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Flight3DTab(shots: [shot], canEditHole: canEditHole),
        ),
      ),
    ),
  );
  await tester.pump();
  // Run the replay out so no ticker is live at teardown.
  await tester.pump(const Duration(seconds: 20));
}

void main() {
  testWidgets('device reports are labelled separately from the simulation',
      (tester) async {
    const reported = ShotData(
      ballSpeed: 120, spinRate: 6500, spinAxis: 0,
      launchDirection: 0, launchAngle: 18, clubSpeed: 85,
      apex: 80, run: 500,
    );
    await _pumpTab(tester, canEditHole: false, shot: reported);
    expect(find.textContaining('Simulated'), findsOneWidget);
    expect(find.textContaining('Device apex'), findsOneWidget);
    expect(find.textContaining('Device roll'), findsOneWidget);
    expect(reported.apexHeight, reported.trajectory.apex);
    expect(reported.rollDistance, reported.trajectory.roll);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a live session offers the hole builder', (tester) async {
    await _pumpTab(tester, canEditHole: true);
    expect(find.byTooltip('Hole builder'), findsOneWidget);
  });

  testWidgets('a saved session hides the hole builder, and only it', (
    tester,
  ) async {
    // The builder edits the hole the NEXT shots play to; from a saved
    // session that would silently change future state while the view keeps
    // rendering the hole stamped on its shots.
    await _pumpTab(tester, canEditHole: false);
    expect(find.byTooltip('Hole builder'), findsNothing);
    // Everything that reads rather than edits stays.
    expect(find.byTooltip('Replay'), findsOneWidget);
    expect(find.byTooltip('Sky'), findsOneWidget);
    expect(find.byTooltip('Previous shots with this club'), findsOneWidget);
  });
}
