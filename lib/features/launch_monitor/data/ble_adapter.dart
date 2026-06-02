import 'dart:async';

/// A discovered BLE device.
class BleScannedDevice {
  final String id;
  final String name;

  /// Raw manufacturer-data bytes flattened to a lower-case hex string.
  /// Empty when the platform doesn't expose this field. Used by callers like
  /// `detectDeviceType` to distinguish Square Golf Home vs Omni at scan time.
  final String manufacturerDataHex;

  const BleScannedDevice({
    required this.id,
    required this.name,
    this.manufacturerDataHex = '',
  });
}

/// Platform-agnostic BLE adapter interface.
///
/// Mobile / macOS use [FlutterBluePlusAdapter]; Windows uses [WinBleAdapter].
///
/// The Square Golf reference connector does **not** hard-code a service UUID:
/// after connecting it discovers *all* services/characteristics and then looks
/// up the ones it needs by their **characteristic UUID** alone. The methods
/// below therefore take only a [characteristicUuid] — implementations must
/// discover all services (see [discoverServices]) and match by characteristic.
abstract class BleAdapter {
  /// Discover nearby BLE devices. Each emission is the latest scan batch.
  Stream<List<BleScannedDevice>> scan({Duration timeout});

  /// Stop an in-progress scan.
  Future<void> stopScan();

  /// Connect to the device identified by [deviceId].
  Future<void> connect(String deviceId);

  /// Stream that emits `false` when the connected device disconnects.
  Stream<bool> connectionStateOf(String deviceId);

  /// Discover *all* services and characteristics and cache them keyed by
  /// characteristic UUID. Must be called (or implicitly triggered) before any
  /// read/write/subscribe. Matches the reference's "discover everything, then
  /// match by characteristic UUID" model.
  Future<void> discoverServices(String deviceId);

  /// Subscribe to notifications on [characteristicUuid] (matched across all
  /// discovered services). Returns a stream of raw byte packets.
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  });

  /// Read the current value of [characteristicUuid] (matched across all
  /// discovered services).
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  });

  /// Write bytes to [characteristicUuid] (matched across all discovered
  /// services).
  Future<void> writeCharacteristic({
    required String deviceId,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  });

  /// Disconnect and release resources for [deviceId].
  Future<void> disconnect(String deviceId);

  /// Tear down the adapter entirely.
  Future<void> dispose();
}

/// Normalises a BLE UUID string for comparison: lower-cases it and expands
/// 16-bit (`2a19`) or 32-bit short forms to the full 128-bit Bluetooth base
/// UUID. This lets us match regardless of whether the platform reports short
/// or long UUIDs.
String normalizeUuid(String uuid) {
  final u = uuid.toLowerCase().trim();
  if (u.length == 4) {
    return '0000$u-0000-1000-8000-00805f9b34fb';
  }
  if (u.length == 8) {
    return '$u-0000-1000-8000-00805f9b34fb';
  }
  return u;
}
