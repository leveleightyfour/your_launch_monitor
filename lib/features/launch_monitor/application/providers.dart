import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/data/seed_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

const _serviceUuid = '0000xxxx-0000-1000-8000-00805f9b34fb';
const _characteristicUuid = '0000xxxx-0000-1000-8000-00805f9b34fb';
const _deviceNamePrefix = 'Square';

@riverpod
class LaunchMonitor extends _$LaunchMonitor {
  BluetoothDevice? _device;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _shotSubscription;
  StreamSubscription? _connectionSubscription;

  /// DB row ID for the in-progress session (created on first shot).
  int? _draftSessionId;
  DateTime? _draftCreatedAt;

  /// Exposed so the finish-session flow can pass the ID to [SessionsNotifier].
  int? get draftSessionId => _draftSessionId;
  DateTime? get draftCreatedAt => _draftCreatedAt;

  @override
  LaunchMonitorState build() {
    ref.onDispose(_cleanup);
    // Pre-seed with sample shots so the UI has data to render during development.
    return LaunchMonitorState(shots: List.from(activeSeedShots));
  }

  Future<void> startScan() async {
    if (state.status != LaunchMonitorStatus.disconnected) return;

    state = state.copyWith(status: LaunchMonitorStatus.scanning, error: null);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final hasMatch = results.any(
        (r) => r.device.platformName.startsWith(_deviceNamePrefix),
      );

      if (hasMatch) {
        final match = results.firstWhere(
          (r) => r.device.platformName.startsWith(_deviceNamePrefix),
        );
        FlutterBluePlus.stopScan();
        _connect(match.device);
      }
    }, onError: (e) => _setError('Scan failed: $e'));

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    if (state.status == LaunchMonitorStatus.scanning) {
      _setError('Device not found');
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _cleanup();
    state = const LaunchMonitorState();
  }

  void clearShots() {
    _draftSessionId = null;
    _draftCreatedAt = null;
    state = state.copyWith(shots: []);
  }

  /// Updates the tag IDs on a live shot by its list index and persists to DB.
  Future<void> updateShotTags(int index, List<int> tagIds) async {
    final updated = List<ShotData>.from(state.shots);
    if (index < 0 || index >= updated.length) return;
    final shot = updated[index];
    updated[index] = shot.copyWith(tagIds: tagIds);
    state = state.copyWith(shots: updated);
    // Persist to DB if this shot has already been saved.
    if (shot.dbId != null) {
      await ref.read(appDatabaseProvider).updateShotTagIds(shot.dbId!, tagIds);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    state = state.copyWith(status: LaunchMonitorStatus.connecting);
    _device = device;

    try {
      await device.connect(autoConnect: false);

      _connectionSubscription = device.connectionState.listen((
        connectionState,
      ) {
        if (connectionState == BluetoothConnectionState.disconnected) {
          state = const LaunchMonitorState(
            status: LaunchMonitorStatus.disconnected,
            error: 'Device disconnected',
          );
        }
      });

      await _discoverAndSubscribe(device);
      state = state.copyWith(status: LaunchMonitorStatus.connected);
    } catch (e) {
      _setError('Connection failed: $e');
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();

    for (final service in services) {
      if (service.uuid.toString() != _serviceUuid) continue;

      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toString() != _characteristicUuid) continue;

        await _performHandshakeIfRequired(characteristic);
        await characteristic.setNotifyValue(true);

        _shotSubscription = characteristic.onValueReceived.listen((data) async {
          final shot = await _parseAndPersistShot(data);
          if (shot != null) {
            state = state.copyWith(shots: [shot, ...state.shots]);
          }
        }, onError: (e) => _setError('Shot read error: $e'));

        return;
      }
    }

    throw Exception('Required characteristic not found');
  }

  Future<void> _performHandshakeIfRequired(
    BluetoothCharacteristic characteristic,
  ) async {
    // Populate with handshake bytes once discovered via Wireshark
    // await characteristic.write([0x01, 0x02, 0x03], withoutResponse: false);
  }

  /// Parses the BLE packet, creates a draft activity on the first shot,
  /// persists the shot to DB, and returns it with [ShotData.dbId] set.
  Future<ShotData?> _parseAndPersistShot(List<int> bytes) async {
    final shot = _parseShot(bytes);
    if (shot == null) return null;

    try {
      final db = ref.read(appDatabaseProvider);
      if (_draftSessionId == null) {
        _draftCreatedAt = DateTime.now();
        _draftSessionId = await db.saveDraftSession(_draftCreatedAt!);
      }
      return await db.insertShot(_draftSessionId!, shot);
    } catch (_) {
      // If DB write fails, still return the in-memory shot so the session
      // can continue — it will be re-persisted on session finish.
      return shot;
    }
  }

  ShotData? _parseShot(List<int> bytes) {
    if (bytes.length < 24) return null;

    try {
      final data = ByteData.view(Uint8List.fromList(bytes).buffer);
      final selectedClub = ref.read(activeClubProvider);

      return ShotData(
        clubId: selectedClub?.id,
        ballSpeed: data.getFloat32(2, Endian.little),
        spinRate: data.getFloat32(6, Endian.little),
        spinAxis: data.getFloat32(10, Endian.little),
        launchDirection: data.getFloat32(14, Endian.little),
        launchAngle: data.getFloat32(18, Endian.little),
        clubSpeed: data.getFloat32(22, Endian.little),
      );
    } catch (_) {
      return null;
    }
  }

  void _setError(String message) {
    state = LaunchMonitorState(
      status: LaunchMonitorStatus.disconnected,
      error: message,
    );
  }

  void _cleanup() {
    _scanSubscription?.cancel();
    _shotSubscription?.cancel();
    _connectionSubscription?.cancel();
    _device?.disconnect();
    _device = null;
  }
}
