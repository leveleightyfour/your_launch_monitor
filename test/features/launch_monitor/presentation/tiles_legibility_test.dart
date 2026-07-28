import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/shared/theme.dart';

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

void main() {
  group('splitValueSuffix', () {
    test('a bare number has no suffix', () {
      expect(splitValueSuffix('131.8'), ('131.8', ''));
      expect(splitValueSuffix('5500'), ('5500', ''));
      expect(splitValueSuffix('1.35'), ('1.35', ''));
    });

    test(
      'direction letters split off; the degree sign stays with the digits',
      () {
        // ° rendered small and baseline-aligned sinks to mid-height; at full
        // size the glyph is already small and top-positioned.
        expect(splitValueSuffix('17.3°'), ('17.3°', ''));
        expect(splitValueSuffix('1.1° R'), ('1.1°', 'R'));
        expect(splitValueSuffix('5.2 T'), ('5.2', 'T'));
      },
    );

    test('a negative number keeps its sign with the digits', () {
      expect(splitValueSuffix('-3.2°'), ('-3.2°', ''));
    });

    test('the null placeholder passes through whole', () {
      expect(splitValueSuffix('--'), ('--', ''));
    });
  });

  group('tiles layout', () {
    Future<void> pump(WidgetTester tester, Size size) async {
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

    testWidgets('labels read as tracked caps with the unit under the value', (
      tester,
    ) async {
      await pump(tester, const Size(1000, 700));

      expect(find.text('CARRY'), findsOneWidget);
      expect(find.text('BALL SPD'), findsOneWidget);
      // Units live under the number now, not in the tile's top corner —
      // one 'mph' each for ball speed and club speed.
      expect(find.text('mph'), findsNWidgets(2));
      // One shot: the average pill is that shot's own numbers.
      expect(find.textContaining('AVG'), findsWidgets);
    });

    testWidgets('a cramped phone split does not overflow', (tester) async {
      // Overflow throws through FlutterError.onError and fails the test, so
      // pumping small is the whole assertion.
      await pump(tester, const Size(360, 480));
      expect(find.text('CARRY'), findsOneWidget);
    });
  });
}
