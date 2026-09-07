import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter.dart';
import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter_factory.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';

import '../../../support/fake_ble_adapter.dart';

void main() {
  late FakeBleAdapter ble;

  setUp(() {
    ble = FakeBleAdapter();
    debugBleAdapterFactory = () => ble;
  });

  tearDown(() => debugBleAdapterFactory = null);

  ProviderContainer newContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // The provider is auto-disposed, so without a standing listener it is torn
    // down and rebuilt between assertions and every check reads a fresh state.
    // A screen watching it is what keeps it alive in the app.
    container.listen(launchMonitorProvider, (_, __) {});
    return container;
  }

  group('a finished scan always releases the connect button', () {
    // Every connect affordance in the app is gated on the status being
    // `disconnected`, so a status left on `scanning` is not a cosmetic
    // spinner — it is a Connect button that no longer opens the picker.

    test('a scan that runs out of time ends the scanning status', () async {
      final container = newContainer();
      final notifier = container.read(launchMonitorProvider.notifier);

      final sub = notifier.scanForDevices().listen((_) {});
      expect(
        container.read(launchMonitorProvider).status,
        LaunchMonitorStatus.scanning,
      );

      // The timeout elapsing, as the adapter reports it.
      await ble.current.close();
      await pumpEventQueue();

      expect(
        container.read(launchMonitorProvider).status,
        LaunchMonitorStatus.disconnected,
      );
      await sub.cancel();
    });

    test('a scan that fails ends the scanning status', () async {
      final container = newContainer();
      final notifier = container.read(launchMonitorProvider.notifier);

      final sub = notifier.scanForDevices().listen((_) {});
      expect(
        container.read(launchMonitorProvider).status,
        LaunchMonitorStatus.scanning,
      );

      // Bluetooth off / unauthorised, which on macOS arrives as an error on
      // the scan rather than as a missing device.
      ble.current.addError(Exception('bluetooth must be turned on'));
      await pumpEventQueue();
      await ble.current.close();
      await pumpEventQueue();

      final state = container.read(launchMonitorProvider);
      expect(state.status, LaunchMonitorStatus.disconnected);
      expect(state.error, isNotNull, reason: 'the failure is worth saying');
      await sub.cancel();
    });

    test('stopScan releases it even while the scan is still open', () async {
      final container = newContainer();
      final notifier = container.read(launchMonitorProvider.notifier);

      final sub = notifier.scanForDevices().listen((_) {});
      await notifier.stopScan();

      expect(
        container.read(launchMonitorProvider).status,
        LaunchMonitorStatus.disconnected,
      );
      expect(ble.stopScanCalls, greaterThan(0), reason: 'the radio is idle');
      await sub.cancel();
    });

    test('walking away from the scan stops the platform scan', () async {
      final container = newContainer();
      final notifier = container.read(launchMonitorProvider.notifier);

      // What the picker does when it is dismissed mid-scan.
      final sub = notifier.scanForDevices().listen((_) {});
      await sub.cancel();

      expect(ble.cancelledScans, 1, reason: 'the adapter is told to wind down');
    });
  });

  test('devices found during a scan reach the picker', () async {
    final container = newContainer();
    final notifier = container.read(launchMonitorProvider.notifier);

    final seen = <List<DiscoveredSquareGolfDevice>>[];
    final sub = notifier.scanForDevices().listen(seen.add);

    ble.current.add(const [
      BleScannedDevice(id: 'a', name: 'SquareGolf-1234'),
      BleScannedDevice(id: 'b', name: 'Some Headphones'),
    ]);
    await pumpEventQueue();

    expect(seen, hasLength(1));
    expect(seen.single.map((d) => d.id), ['a']);
    await sub.cancel();
  });
}
