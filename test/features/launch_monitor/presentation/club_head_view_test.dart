import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:omni_sniffer/features/launch_monitor/application/club_head_model_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/club_tab.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';
import 'package:omni_sniffer/shared/three/glb_model.dart';

class _MemoryPrefs extends UnitPrefsNotifier {
  @override
  UnitPrefs build() => const UnitPrefs();
  @override
  void setClubView(String view) => state = state.copyWith(clubView: view);
}

ShotData _shot(int i, {double h = 5, double v = 3}) => ShotData(
  dbId: i,
  clubId: 'dr',
  ballSpeed: 150,
  clubSpeed: 104,
  spinRate: 2600,
  spinAxis: 1,
  launchAngle: 12.5,
  launchDirection: 1,
  swingPath: 2.0,
  faceAngle: 2.5,
  angleOfAttack: -1.2,
  dynamicLoft: 14.0,
  horizontalImpact: h,
  verticalImpact: v,
);

void main() {
  late ClubHeadModel model;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final mesh = parseGlb(
      File('assets/models/titleist_gt2_head.glb').readAsBytesSync(),
    ).mirroredX();
    final images = <ui.Image?>[];
    for (final image in mesh.images) {
      images.add(await decodeImageFromList(image.bytes));
    }
    model = ClubHeadModel.measure(mesh, images);
  });

  test('the GT2 head is measured as a right-handed driver', () {
    // ~86 mm heel to toe, ~44 mm tall, about ten degrees of loft.
    expect(model.faceHalfWidth * 2000, closeTo(86, 4));
    expect(model.faceHalfHeight * 2000, closeTo(44, 4));
    expect(model.staticLoft, closeTo(10.4, 0.5));
    expect(model.faceNormal[2], greaterThan(0.95));
    // Hosel on the heel, at −X once mirrored; the toe script at +X.
    final hosel = model.mesh.parts.firstWhere((p) => p.name.startsWith('Ferrule'));
    final script = model.mesh.parts.firstWhere((p) => p.name.startsWith('Toe-side'));
    expect(hosel.positions[0], lessThan(0));
    expect(script.positions[0], greaterThan(0));
  });

  testWidgets('the tab swings between views, remembers the choice and draws no Material glyph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shots = [_shot(1), _shot(2, h: -8, v: -4), _shot(3, h: 12, v: 8)];
    final container = ProviderContainer(
      overrides: [
        unitPrefsProvider.overrideWith(_MemoryPrefs.new),
        clubHeadModelProvider.overrideWith((_) async => model),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ClubTab(shots: shots, clubs: Club.catalog, selectedShot: shots.first),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Loading club model'), findsNothing);
    expect(find.text('Heatmap'), findsNothing);

    await tester.tap(find.text('Impact'));
    await tester.pump();
    expect(container.read(unitPrefsProvider).clubView, 'impact');
    // Mid-swing, then settled.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Heatmap'), findsOneWidget);
    await tester.tap(find.text('Heatmap'));
    await tester.pump();

    await tester.tap(find.text('Top'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Interrupting a swing with another choice must not throw.
    await tester.tap(find.text('Side'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(unitPrefsProvider).clubView, 'side');

    await tester.tap(find.text('Show AVG'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byWidgetPredicate((w) => w is Icon && w.icon?.fontFamily == 'MaterialIcons'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
