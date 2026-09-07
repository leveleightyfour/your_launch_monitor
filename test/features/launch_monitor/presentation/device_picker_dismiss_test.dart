import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter_factory.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/device_picker_sheet.dart';
import 'package:omni_sniffer/shared/theme.dart';

import '../../../support/fake_ble_adapter.dart';

/// Stands in for the session screen's connect control, gated exactly the way
/// the real ones are: it only opens the picker while the status is
/// `disconnected`. That gate is what turns a stuck `scanning` into a dead
/// button, so the harness has to keep it to reproduce the bug.
class _ConnectControl extends ConsumerWidget {
  const _ConnectControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(launchMonitorProvider.select((s) => s.status));
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: status == LaunchMonitorStatus.disconnected
              ? () => DevicePickerSheet.show(context)
              : null,
          child: const Text('Connect'),
        ),
      ),
    );
  }
}

void main() {
  late FakeBleAdapter ble;
  late ProviderContainer container;

  setUp(() {
    ble = FakeBleAdapter();
    debugBleAdapterFactory = () => ble;
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    debugBleAdapterFactory = null;
  });

  // The picker's spinner animates for as long as the scan runs, so
  // pumpAndSettle never returns while it is up. Advance real frames instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const _ConnectControl(),
        ),
      ),
    );
    await tester.pump();
  }

  LaunchMonitorStatus status() => container.read(launchMonitorProvider).status;

  testWidgets('dismissing the picker leaves the connect button usable', (
    tester,
  ) async {
    // The macOS report: after opening and dismissing the picker, the session
    // screen's connect button stops opening it. The scan was still running as
    // far as the notifier knew, and every connect control is gated on
    // `disconnected`.
    await pumpApp(tester);

    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.text('Connect device'), findsOneWidget);
    expect(status(), LaunchMonitorStatus.scanning);

    // Dismissed mid-scan, without picking anything — tapping the barrier is
    // the drag/Esc/back path the user actually takes.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Connect device'), findsNothing);

    expect(
      status(),
      LaunchMonitorStatus.disconnected,
      reason: 'a dismissed picker is not a scan still in progress',
    );

    // The whole point: the button works a second time.
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.text('Connect device'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
  });

  testWidgets('a scan that runs out of time stops the picker spinning', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(
      find.text('Scanning for nearby Square Golf devices…'),
      findsOneWidget,
    );

    // The timeout elapsing. The picker only learns about it if the adapter
    // ends the stream, which is what it never used to do.
    await ble.current.close();
    await settle(tester);

    expect(find.text('No devices found.'), findsOneWidget);
    expect(status(), LaunchMonitorStatus.disconnected);

    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
  });
}
