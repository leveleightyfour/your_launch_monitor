import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_adapter.dart';
import 'squaregolf/constants.dart';
import 'squaregolf/frame_capture.dart';
import 'squaregolf/log.dart';

/// BLE adapter backed by [FlutterBluePlus] (Android, iOS, macOS, Linux).
class FlutterBluePlusAdapter implements BleAdapter {
  BluetoothDevice? _device;

  /// Discovered characteristics, keyed by normalised characteristic UUID.
  /// Populated by [discoverServices] — the reference matches by characteristic
  /// UUID alone, so we never assume which service holds a characteristic.
  final Map<String, BluetoothCharacteristic> _chars = {};

  @override
  Stream<List<BleScannedDevice>> scan({
    Duration timeout = const Duration(seconds: 15),
  }) {
    // A plain `.map` over `FlutterBluePlus.scanResults` reads simpler, but that
    // stream is a long-lived broadcast controller that is never closed: when the
    // scan times out the caller gets no `done`, so a picker waiting on one spins
    // forever. Cancelling it doesn't stop the platform scan either. Own the
    // whole lifecycle here, the way the Windows adapter does.
    final controller = StreamController<List<BleScannedDevice>>();
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;

    Future<void> cancelSubs() async {
      final results = resultsSub;
      final scanning = scanningSub;
      resultsSub = null;
      scanningSub = null;
      await results?.cancel();
      await scanning?.cancel();
    }

    Future<void> finish() async {
      await cancelSubs();
      if (!controller.isClosed) await controller.close();
    }

    controller.onListen = () async {
      lmLog('scan', 'startScan timeout=${timeout.inSeconds}s');
      try {
        // Awaited: startScan reports "bluetooth is off" and "unauthorised" —
        // both routine on macOS — by rejecting this future, never on
        // scanResults. Left fire-and-forget those become an unhandled async
        // error while the caller waits on a stream that will never emit.
        await FlutterBluePlus.startScan(timeout: timeout);
      } catch (e, s) {
        lmWarn('scan', 'startScan failed: $e');
        if (!controller.isClosed) controller.addError(e, s);
        await finish();
        return;
      }
      if (controller.isClosed) return; // cancelled while starting

      resultsSub = FlutterBluePlus.scanResults.listen(
        (results) {
          if (!controller.isClosed) controller.add(_mapResults(results));
        },
        onError: (Object e, StackTrace s) {
          if (!controller.isClosed) controller.addError(e, s);
        },
      );

      // `isScanning` re-emits its current value on listen, which is the `true`
      // the startScan above just caused; the next `false` is the timeout
      // firing. That transition is the only signal FlutterBluePlus gives that
      // a scan is over, so turn it into the `done` the caller is waiting for.
      scanningSub = FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .listen((_) {
            lmLog('scan', 'scan finished');
            unawaited(finish());
          });
    };

    controller.onCancel = () async {
      await cancelSubs();
      // Nothing else stops the platform scan once the caller walks away, and an
      // orphaned scan keeps the radio busy and blocks the next one.
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    };

    return controller.stream;
  }

  static List<BleScannedDevice> _mapResults(List<ScanResult> results) {
    final mapped = results
        .map(
          (r) => BleScannedDevice(
            id: r.device.remoteId.str,
            name: r.device.platformName,
            manufacturerDataHex: _flattenManufacturerData(
              r.advertisementData.manufacturerData,
            ),
          ),
        )
        .toList();
    // Log every device while we're hunting for the Omni's advertised name.
    // Tighten this back to a prefix filter once we know what it actually
    // calls itself.
    for (final d in mapped) {
      final isCandidate =
          d.name.toLowerCase().contains('square') ||
          d.name.toLowerCase().contains('omni') ||
          d.name.toLowerCase().contains('sg') ||
          d.manufacturerDataHex.toUpperCase().contains('3033303041');
      lmLog(
        'scan',
        '${isCandidate ? '★ ' : '  '}name="${d.name}" id=${d.id} '
            'mfg=${d.manufacturerDataHex}',
      );
    }
    return mapped;
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

    // Keep the GATT map with the capture, not just the debug log — a second
    // notify characteristic is a candidate home for the flight numbers the
    // device reports but never sends on the one we listen to.
    final entries = <String>[];
    final unsubscribed = <String>[];
    for (final service in services) {
      for (final char in service.characteristics) {
        final p = char.properties;
        final props = [
          if (p.read) 'read',
          if (p.write) 'write',
          if (p.writeWithoutResponse) 'writeNR',
          if (p.notify) 'notify',
          if (p.indicate) 'indicate',
        ].join(',');
        final uuid = normalizeUuid(char.uuid.toString());
        entries.add('$uuid  [$props]');
        if ((p.notify || p.indicate) &&
            uuid != normalizeUuid(notificationCharUuid)) {
          unsubscribed.add('$uuid  [$props]');
        }
      }
    }
    FrameCapture.recordGatt(entries, notifying: unsubscribed);
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
