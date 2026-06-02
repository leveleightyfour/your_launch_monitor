import 'dart:async';
import 'dart:typed_data';

import 'package:win_ble/win_ble.dart';
import 'package:win_ble/win_file.dart';

import 'ble_adapter.dart';
import 'squaregolf/log.dart';

/// BLE adapter backed by [WinBle] for Windows desktop builds.
class WinBleAdapter implements BleAdapter {
  bool _initialised = false;
  String? _connectedDeviceAddress;

  /// Maps a normalised characteristic UUID → the service UUID that exposes it.
  /// WinBle's read/write/subscribe calls require the service id, so we discover
  /// everything up front and resolve the service from the characteristic.
  final Map<String, String> _charToService = {};

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
      lmLog('scan', 'WinBle.startScanning timeout=${timeout.inSeconds}s');
      WinBle.startScanning();

      final sub = WinBle.scanStream.listen((device) {
        final name = device.name.isNotEmpty ? device.name : '';
        final mfg = StringBuffer();
        for (final b in device.manufacturerData) {
          mfg.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
        }
        if (name.startsWith('SquareGolf')) {
          lmLog('scan',
              'found name="$name" id=${device.address} mfg=$mfg');
        }
        devices[device.address] = BleScannedDevice(
          id: device.address,
          name: name,
          manufacturerDataHex: mfg.toString(),
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
    lmLog('scan', 'WinBle.stopScanning');
    WinBle.stopScanning();
  }

  @override
  Future<void> connect(String deviceId) async {
    await _ensureInitialised();
    lmLog('conn', 'WinBle.connect $deviceId');
    _charToService.clear();
    await WinBle.connect(deviceId);
    _connectedDeviceAddress = deviceId;
    lmLog('conn', 'WinBle.connect → ok');
  }

  @override
  Stream<bool> connectionStateOf(String deviceId) {
    return WinBle.connectionStreamOf(deviceId).map(
      (event) => event == true,
    );
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    await _ensureInitialised();
    lmLog('conn', 'WinBle.discoverServices $deviceId');
    _charToService.clear();
    final services = await WinBle.discoverServices(deviceId);
    for (final serviceId in services) {
      final chars = await WinBle.discoverCharacteristics(
        address: deviceId,
        serviceId: serviceId,
      );
      for (final c in chars) {
        _charToService[normalizeUuid(c.uuid)] = serviceId;
      }
    }
    lmLog(
      'conn',
      'discovered ${services.length} services / ${_charToService.length} characteristics',
    );
  }

  Future<String> _serviceFor(String deviceId, String characteristicUuid) async {
    if (_charToService.isEmpty) await discoverServices(deviceId);
    final key = normalizeUuid(characteristicUuid);
    final serviceId = _charToService[key];
    if (serviceId == null) {
      lmWarn('conn', 'characteristic $characteristicUuid not found');
      throw Exception('Characteristic $characteristicUuid not found');
    }
    return serviceId;
  }

  @override
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  }) async {
    final serviceId = await _serviceFor(deviceId, characteristicUuid);
    lmLog('conn', 'subscribe $characteristicUuid (svc=$serviceId)');

    await WinBle.subscribeToCharacteristic(
      address: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicUuid,
    );

    return WinBle.characteristicValueStream
        .where((event) =>
            normalizeUuid(event.characteristicId) ==
            normalizeUuid(characteristicUuid))
        .map((event) => List<int>.from(event.value));
  }

  @override
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  }) async {
    final serviceId = await _serviceFor(deviceId, characteristicUuid);
    final value = await WinBle.read(
      address: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicUuid,
    );
    return List<int>.from(value);
  }

  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    final serviceId = await _serviceFor(deviceId, characteristicUuid);
    await WinBle.write(
      address: deviceId,
      service: serviceId,
      characteristic: characteristicUuid,
      data: Uint8List.fromList(data),
      writeWithResponse: withResponse,
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {
    lmLog('conn', 'WinBle.disconnect $deviceId');
    _charToService.clear();
    await WinBle.disconnect(deviceId);
    _connectedDeviceAddress = null;
  }

  @override
  Future<void> dispose() async {
    _charToService.clear();
    if (_connectedDeviceAddress != null) {
      await WinBle.disconnect(_connectedDeviceAddress!);
      _connectedDeviceAddress = null;
    }
    WinBle.dispose();
    _initialised = false;
  }
}
