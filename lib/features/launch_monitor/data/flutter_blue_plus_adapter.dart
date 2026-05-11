import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_adapter.dart';
import 'squaregolf/log.dart';

/// BLE adapter backed by [FlutterBluePlus] (Android, iOS, macOS, Linux).
class FlutterBluePlusAdapter implements BleAdapter {
  BluetoothDevice? _device;

  @override
  Stream<List<BleScannedDevice>> scan({Duration timeout = const Duration(seconds: 15)}) {
    lmLog('scan', 'startScan timeout=${timeout.inSeconds}s');
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults.map((results) {
      final mapped = results
          .map((r) => BleScannedDevice(
                id: r.device.remoteId.str,
                name: r.device.platformName,
                manufacturerDataHex: _flattenManufacturerData(
                  r.advertisementData.manufacturerData,
                ),
              ))
          .toList();
      // Log only Square Golf candidates so the scan doesn't drown the log.
      for (final d in mapped) {
        if (d.name.startsWith('SquareGolf')) {
          lmLog('scan',
              'found name="${d.name}" id=${d.id} mfg=${d.manufacturerDataHex}');
        }
      }
      return mapped;
    });
  }

  static String _flattenManufacturerData(Map<int, List<int>> data) {
    if (data.isEmpty) return '';
    final buf = StringBuffer();
    for (final entry in data.entries) {
      // Manufacturer ID is 2 bytes little-endian by BLE convention.
      buf.write((entry.key & 0xFF).toRadixString(16).padLeft(2, '0'));
      buf.write(((entry.key >> 8) & 0xFF).toRadixString(16).padLeft(2, '0'));
      for (final b in entry.value) {
        buf.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
      }
    }
    return buf.toString();
  }

  @override
  Future<void> stopScan() {
    lmLog('scan', 'stopScan');
    return FlutterBluePlus.stopScan();
  }

  @override
  Future<void> connect(String deviceId) async {
    lmLog('conn', 'BLE.connect $deviceId');
    _device = BluetoothDevice.fromId(deviceId);
    await _device!.connect(autoConnect: false);
    lmLog('conn', 'BLE.connect → ok');
  }

  @override
  Stream<bool> connectionStateOf(String deviceId) {
    final device = _device ?? BluetoothDevice.fromId(deviceId);
    return device.connectionState.map(
      (s) => s == BluetoothConnectionState.connected,
    );
  }

  @override
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final device = _device ?? BluetoothDevice.fromId(deviceId);
    lmLog('conn', 'discoverServices() for subscribe $characteristicUuid');
    final services = await device.discoverServices();
    lmLog('conn',
        'discovered ${services.length} services: ${services.map((s) => s.uuid.toString()).join(", ")}');

    for (final service in services) {
      if (service.uuid.toString() != serviceUuid) continue;
      for (final char in service.characteristics) {
        if (char.uuid.toString() != characteristicUuid) continue;
        await char.setNotifyValue(true);
        lmLog('conn', 'subscribed $characteristicUuid');
        return char.onValueReceived;
      }
    }

    lmWarn('conn',
        'characteristic $characteristicUuid not found under $serviceUuid');
    throw Exception('Characteristic $characteristicUuid not found');
  }

  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    final device = _device ?? BluetoothDevice.fromId(deviceId);
    final services = await device.discoverServices();

    for (final service in services) {
      if (service.uuid.toString() != serviceUuid) continue;
      for (final char in service.characteristics) {
        if (char.uuid.toString() != characteristicUuid) continue;
        await char.write(data, withoutResponse: !withResponse);
        return;
      }
    }

    lmWarn('conn', 'write target $characteristicUuid not found');
    throw Exception('Characteristic $characteristicUuid not found');
  }

  @override
  Future<void> disconnect(String deviceId) async {
    lmLog('conn', 'BLE.disconnect $deviceId');
    await _device?.disconnect();
    _device = null;
  }

  @override
  Future<void> dispose() async {
    lmLog('conn', 'BLE.dispose');
    await _device?.disconnect();
    _device = null;
  }
}
