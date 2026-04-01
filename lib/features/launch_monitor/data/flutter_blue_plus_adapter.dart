import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_adapter.dart';

/// BLE adapter backed by [FlutterBluePlus] (Android, iOS, macOS, Linux).
class FlutterBluePlusAdapter implements BleAdapter {
  BluetoothDevice? _device;

  @override
  Stream<List<BleScannedDevice>> scan({Duration timeout = const Duration(seconds: 15)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults.map(
      (results) => results
          .map((r) => BleScannedDevice(
                id: r.device.remoteId.str,
                name: r.device.platformName,
              ))
          .toList(),
    );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> connect(String deviceId) async {
    _device = BluetoothDevice.fromId(deviceId);
    await _device!.connect(autoConnect: false);
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
    final services = await device.discoverServices();

    for (final service in services) {
      if (service.uuid.toString() != serviceUuid) continue;
      for (final char in service.characteristics) {
        if (char.uuid.toString() != characteristicUuid) continue;
        await char.setNotifyValue(true);
        return char.onValueReceived;
      }
    }

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

    throw Exception('Characteristic $characteristicUuid not found');
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _device?.disconnect();
    _device = null;
  }

  @override
  Future<void> dispose() async {
    await _device?.disconnect();
    _device = null;
  }
}
