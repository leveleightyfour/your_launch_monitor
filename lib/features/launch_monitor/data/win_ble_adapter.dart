import 'dart:async';
import 'dart:typed_data';

import 'package:win_ble/win_ble.dart';
import 'package:win_ble/win_file.dart';

import 'ble_adapter.dart';

/// BLE adapter backed by [WinBle] for Windows desktop builds.
class WinBleAdapter implements BleAdapter {
  bool _initialised = false;
  String? _connectedDeviceAddress;

  Future<void> _ensureInitialised() async {
    if (_initialised) return;
    await WinBle.initialize(serverPath: await WinServer.path());
    _initialised = true;
  }

  @override
  Stream<List<BleScannedDevice>> scan({
    Duration timeout = const Duration(seconds: 15),
  }) {
    final controller = StreamController<List<BleScannedDevice>>();
    final devices = <String, BleScannedDevice>{};

    () async {
      await _ensureInitialised();
      WinBle.startScanning();

      final sub = WinBle.scanStream.listen((device) {
        final name = device.name.isNotEmpty ? device.name : '';
        devices[device.address] = BleScannedDevice(
          id: device.address,
          name: name,
        );
        controller.add(devices.values.toList());
      });

      // Stop after timeout.
      Future.delayed(timeout, () {
        WinBle.stopScanning();
        sub.cancel();
        if (!controller.isClosed) controller.close();
      });

      controller.onCancel = () {
        WinBle.stopScanning();
        sub.cancel();
      };
    }();

    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    await _ensureInitialised();
    WinBle.stopScanning();
  }

  @override
  Future<void> connect(String deviceId) async {
    await _ensureInitialised();
    await WinBle.connect(deviceId);
    _connectedDeviceAddress = deviceId;
  }

  @override
  Stream<bool> connectionStateOf(String deviceId) {
    return WinBle.connectionStreamOf(deviceId).map(
      (event) => event == true,
    );
  }

  @override
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await _ensureInitialised();

    await WinBle.subscribeToCharacteristic(
      address: deviceId,
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
    );

    return WinBle.characteristicValueStream.map(
      (event) => List<int>.from(event.value),
    );
  }

  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    await _ensureInitialised();
    await WinBle.write(
      address: deviceId,
      service: serviceUuid,
      characteristic: characteristicUuid,
      data: Uint8List.fromList(data),
      writeWithResponse: withResponse,
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await WinBle.disconnect(deviceId);
    _connectedDeviceAddress = null;
  }

  @override
  Future<void> dispose() async {
    if (_connectedDeviceAddress != null) {
      await WinBle.disconnect(_connectedDeviceAddress!);
      _connectedDeviceAddress = null;
    }
    WinBle.dispose();
    _initialised = false;
  }
}
