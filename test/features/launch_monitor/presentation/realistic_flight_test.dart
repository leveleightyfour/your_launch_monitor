import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/profile_screen.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

class _MemoryPrefs extends UnitPrefsNotifier {
  @override
  UnitPrefs build() => const UnitPrefs();

  void usePrefs(UnitPrefs prefs) => state = prefs;

  @override
  void setFlightViewStyle(FlightViewStyle style) {
    state = state.copyWith(flightViewStyle: style);
  }
}

const _shot = ShotData(
  dbId: 1,
  clubId: '7i',
  ballSpeed: 120,
  spinRate: 6500,
  spinAxis: 0,
  launchDirection: 0,
  launchAngle: 18,
  clubSpeed: 85,
  hole: HoleSetup.standard,
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  testWidgets('Profile switches the mounted flight view in both directions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [unitPrefsProvider.overrideWith(_MemoryPrefs.new)],
    );
    addTearDown(container.dispose);
    var profile = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return IndexedStack(
                index: profile ? 1 : 0,
                children: const [
                  Scaffold(body: Flight3DTab(shots: [_shot])),
                  ProfileScreen(),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flight-scene-classic')), findsOneWidget);
    final trajectory = _shot.trajectory;
    for (final style in [FlightViewStyle.realistic, FlightViewStyle.classic]) {
      rebuild(() => profile = true);
      await tester.pumpAndSettle();
      final option = find.byKey(ValueKey('flight-view-${style.name}'));
      await tester.scrollUntilVisible(
        option,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(container.read(unitPrefsProvider).flightViewStyle, style);
      rebuild(() => profile = false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('flight-scene-${style.name}')),
        findsOneWidget,
      );
      expect(identical(_shot.trajectory, trajectory), isTrue);
      expect(find.byTooltip('Replay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'realistic replay renders every camera at phone and split-pane sizes',
    (tester) async {
      final container = ProviderContainer(
        overrides: [unitPrefsProvider.overrideWith(_MemoryPrefs.new)],
      );
      addTearDown(container.dispose);
      container
          .read(unitPrefsProvider.notifier)
          .setFlightViewStyle(FlightViewStyle.realistic);
      for (final size in [const Size(390, 500), const Size(320, 260)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(
                body: Flight3DTab(shots: [_shot], showStatBar: false),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final camera in FlightCamera.values) {
          // Camera chips are all present even when their labels collapse.
          final chip = find.byTooltip(camera.label);
          await tester.scrollUntilVisible(
            chip,
            80,
            scrollable: find.byType(Scrollable),
          );
          expect(chip, findsOneWidget);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Replay'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          expect(
            tester.takeException(),
            isNull,
            reason: '${camera.name} at $size',
          );
          await tester.pumpAndSettle();
        }
      }
      tester.view.reset();
    },
  );
  testWidgets('custom terrain and every sky render in realistic mode', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [unitPrefsProvider.overrideWith(_MemoryPrefs.new)],
    );
    addTearDown(container.dispose);
    final grid = HoleGrid(
      cellSize: 5,
      cols: 24,
      rows: 50,
      cells: List.generate(
        24 * 50,
        (i) => Terrain.values[(i % 24) ~/ 4 % Terrain.values.length],
      ),
    );
    final shot = _shot.copyWith(hole: HoleSetup.standard.copyWith(grid: grid));
    for (final sky in SkyScene.values) {
      (container.read(unitPrefsProvider.notifier) as _MemoryPrefs).usePrefs(
        UnitPrefs(flightViewStyle: FlightViewStyle.realistic, skyScene: sky),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: Flight3DTab(shots: [shot])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: sky.name);
      await tester.pumpAndSettle();
    }
  });
}
