import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_adapter.dart';
import 'squaregolf/log.dart';

/// BLE adapter backed by [FlutterBluePlus] (Android, iOS, macOS, Linux).
class FlutterBluePlusAdapter implements BleAdapter {
  BluetoothDevice? _device;

  /// Discovered characteristics, keyed by normalised characteristic UUID.
  /// Populated by [discoverServices] — the reference matches by characteristic
  /// UUID alone, so we never assume which service holds a characteristic.
  final Map<String, BluetoothCharacteristic> _chars = {};

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
    _chars.clear();
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
  Future<void> discoverServices(String deviceId) async {
    final device = _device ?? BluetoothDevice.fromId(deviceId);
    lmLog('conn', 'discoverServices()');
    final services = await device.discoverServices();
    _chars.clear();
    for (final service in services) {
      for (final char in service.characteristics) {
        _chars[normalizeUuid(char.uuid.toString())] = char;
      }
    }
    lmLog(
      'conn',
      'discovered ${services.length} services / ${_chars.length} characteristics: '
          '${_chars.keys.join(", ")}',
    );
  }

  Future<BluetoothCharacteristic> _characteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    if (_chars.isEmpty) await discoverServices(deviceId);
    final key = normalizeUuid(characteristicUuid);
    final char = _chars[key];
    if (char == null) {
      lmWarn('conn', 'characteristic $characteristicUuid not found');
      throw Exception('Characteristic $characteristicUuid not found');
    }
    return char;
  }

  @override
  Future<Stream<List<int>>> subscribeToCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  }) async {
    final char = await _characteristic(deviceId, characteristicUuid);
    await char.setNotifyValue(true);
    lmLog('conn', 'subscribed $characteristicUuid');
    return char.onValueReceived;
  }

  @override
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String characteristicUuid,
  }) async {
    final char = await _characteristic(deviceId, characteristicUuid);
    return char.read();
  }

  @override
  Future<void> writeCharacteristic({
    required String deviceId,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    final char = await _characteristic(deviceId, characteristicUuid);
    await char.write(data, withoutResponse: !withResponse);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    lmLog('conn', 'BLE.disconnect $deviceId');
    _chars.clear();
    await _device?.disconnect();
    _device = null;
  }

  @override
  Future<void> dispose() async {
    lmLog('conn', 'BLE.dispose');
    _chars.clear();
    await _device?.disconnect();
    _device = null;
  }
}
