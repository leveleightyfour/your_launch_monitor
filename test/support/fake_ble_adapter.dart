import 'dart:async';

import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter.dart';

/// A scan the test drives by hand: it yields devices when the test says so and
/// ends when the test says so, the way a real one ends when its timeout
/// elapses. Each [scan] hands out a fresh stream, so a picker that is opened,
/// dismissed and opened again behaves the way it does against a real adapter.
class FakeBleAdapter implements BleAdapter {
  final List<StreamController<List<BleScannedDevice>>> scans = [];
  int stopScanCalls = 0;
  int cancelledScans = 0;

  /// The scan currently in progress.
  StreamController<List<BleScannedDevice>> get current => scans.last;

  @override
  Stream<List<BleScannedDevice>> scan({Duration timeout = Duration.zero}) {
    final controller = StreamController<List<BleScannedDevice>>();
    controller.onCancel = () => cancelledScans++;
    scans.add(controller);
    return controller.stream;
  }

  @override
  Future<void> stopScan() async => stopScanCalls++;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Stream<bool> connectionStateOf(String deviceId) => const Stream.empty();

  @override
  Future<void> discoverServices(String deviceId) async {}

  @override
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  }) async => const [];

  @override
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  }) async => const Stream.empty();

  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {}
}
