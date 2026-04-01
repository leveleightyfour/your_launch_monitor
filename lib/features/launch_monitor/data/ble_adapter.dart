import 'dart:async';

/// A discovered BLE device.
class BleScannedDevice {
  final String id;
  final String name;

  const BleScannedDevice({required this.id, required this.name});
}

/// Platform-agnostic BLE adapter interface.
///
/// Mobile / macOS use [FlutterBluePlusAdapter]; Windows uses [WinBleAdapter].
abstract class BleAdapter {
  /// Discover nearby BLE devices. Each emission is the latest scan batch.
  Stream<List<BleScannedDevice>> scan({Duration timeout});

  /// Stop an in-progress scan.
  Future<void> stopScan();

  /// Connect to the device identified by [deviceId].
  Future<void> connect(String deviceId);

  /// Stream that emits `false` when the connected device disconnects.
  Stream<bool> connectionStateOf(String deviceId);

  /// Discover services, then subscribe to notifications on [characteristicUuid]
  /// within [serviceUuid]. Returns a stream of raw byte packets.
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Write bytes to a characteristic.
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  });

  /// Disconnect and release resources for [deviceId].
  Future<void> disconnect(String deviceId);

  /// Tear down the adapter entirely.
  Future<void> dispose();
}
