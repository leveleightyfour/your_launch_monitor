import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/application/ball_position_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter_factory.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/ball_position.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/ball_position_map.dart';
import 'package:omni_sniffer/shared/theme.dart';

import '../../../support/fake_ble_adapter.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    // Opening the panel builds the launch-monitor notifier, which builds a BLE
    // adapter in a field initialiser. Hand it a fake so no real radio is
    // touched.
    debugBleAdapterFactory = FakeBleAdapter.new;
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    debugBleAdapterFactory = null;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => BallPositionPanel.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Building the launch-monitor notifier arms its deferred auto-reconnect.
    // Let that fire, or it is still pending at teardown and fails the test.
    await tester.pump(const Duration(milliseconds: 1300));
  }

  testWidgets('the panel shows the mat and the ball on it', (tester) async {
    container
        .read(ballPositionProvider.notifier)
        .update(
          const BallPosition(
            depthMm: 100,
            lateralMm: 0,
            heightMm: 0,
            detected: true,
            ready: true,
          ),
        );

    await open(tester);

    expect(find.text('BALL POSITION'), findsOneWidget);
    expect(find.byType(BallPositionMap), findsOneWidget);

    final map = tester.widget<BallPositionMap>(find.byType(BallPositionMap));
    expect(map.position?.depthMm, 100);
  });

  testWidgets('the panel says where its numbers come from', (tester) async {
    // The scale is read off a third-party connector, not vendor docs. The app
    // draws a line between measured and inferred everywhere else.
    await open(tester);

    expect(
      find.textContaining('read off a third-party connector'),
      findsOneWidget,
    );
  });

  testWidgets('the panel shows the numbers behind the picture', (tester) async {
    // The transform is read off a third-party connector, not vendor docs. When
    // the drawing looks wrong these are what settle whether the ball moved or
    // the arithmetic is off, so they are on the face of it, not behind a flag.
    container
        .read(ballPositionProvider.notifier)
        .update(
          const BallPosition(
            depthMm: 475,
            lateralMm: 175,
            heightMm: -100,
            detected: true,
            ready: true,
            rawX: 4760,
            rawY: 1740,
            rawZ: -1000,
          ),
        );
    await open(tester);

    expect(find.textContaining('FRONT +475mm'), findsOneWidget);
    expect(find.textContaining('RAW 4760 / 1740 / -1000'), findsOneWidget);
  });

  testWidgets('the panel closes again', (tester) async {
    await open(tester);
    expect(find.text('BALL POSITION'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(find.text('BALL POSITION'), findsNothing);
  });

  testWidgets('the panel defers to the monitor on readiness', (tester) async {
    // The app used to infer whether the ball was inside a ready zone from the
    // manual's offsets. Those only hold with the monitor standing where the
    // manual puts it, so every real ball got a confident, wrong verdict. The
    // monitor's light already answers it.
    await open(tester);
    expect(
      find.textContaining("The monitor's light is the word"),
      findsOneWidget,
    );
  });
}
