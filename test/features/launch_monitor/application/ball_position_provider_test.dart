import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/application/ball_position_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/ball_position.dart';

BallPosition _at(double depthMm, {double lateralMm = 0, double heightMm = 0}) =>
    BallPosition(
      depthMm: depthMm,
      lateralMm: lateralMm,
      heightMm: heightMm,
      detected: true,
      ready: true,
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  BallPositionNotifier notifier() =>
      container.read(ballPositionProvider.notifier);

  test('there is no position until the device reports one', () {
    expect(container.read(ballPositionProvider), isNull);
  });

  test('positions land on whole millimetres', () {
    // The wire carries twentieths. At map scale that is a fraction of a pixel,
    // so the precision buys nothing and the jitter costs a repaint on every
    // frame.
    notifier().update(_at(123.4, lateralMm: -67.8, heightMm: 9.9));

    final p = container.read(ballPositionProvider)!;
    expect(p.depthMm, 123);
    expect(p.lateralMm, -68);
    expect(p.heightMm, 10);
  });

  test('a ball that has not moved does not wake anything up', () {
    // The whole reason position lives outside LaunchMonitorState: a ball
    // sitting still on the mat streams frames forever and should cost nothing.
    var notifications = 0;
    container.listen(ballPositionProvider, (_, __) => notifications++);

    notifier().update(_at(200.02));
    notifier().update(_at(199.98)); // same millimetre
    notifier().update(_at(200.4)); // still the same millimetre

    expect(notifications, 1, reason: 'one move, one notification');
  });

  test('a ball that moves a millimetre does', () {
    var notifications = 0;
    container.listen(ballPositionProvider, (_, __) => notifications++);

    notifier().update(_at(200));
    notifier().update(_at(201));

    expect(notifications, 2);
  });

  test('clearing forgets the position rather than freezing it', () {
    // A stale dot is worse than no dot: it claims the ball is somewhere it may
    // well not be any more.
    notifier().update(_at(100));
    expect(container.read(ballPositionProvider), isNotNull);

    notifier().clear();
    expect(container.read(ballPositionProvider), isNull);
  });
}
