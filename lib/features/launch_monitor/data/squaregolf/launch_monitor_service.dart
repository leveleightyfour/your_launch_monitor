/// High-level service that wraps the [BleAdapter] with the Square Golf
/// protocol — handles connection lifecycle, heartbeat, the Omni init handshake,
/// and decodes incoming notifications into typed streams.
///
/// Ported from `squaregolf-connector` (Go) — see `internal/core/launch_monitor.go`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble_adapter.dart';
import 'commands.dart';
import 'constants.dart';
import 'notifications.dart';

/// Inferred service UUIDs — the Go reference does not hard-code a service
/// because it discovers everything and matches by characteristic UUID. These
/// follow the standard Nordic-style convention where a service UUID shares a
/// prefix with its characteristics. If a real device exposes them under a
/// different service, swap [primaryServiceUuid] / [batteryServiceUuid].
const String primaryServiceUuid = '86602100-6b7e-439a-bdd1-489a3213e9bb';
const String deviceInfoServiceUuid = '86602000-6b7e-439a-bdd1-489a3213e9bb';
const String batteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb';

/// Typed packet emitted on [LaunchMonitorService.notifications].
sealed class LmEvent {
  const LmEvent();
}

class LmSensorEvent extends LmEvent {
  final SensorData data;
  const LmSensorEvent(this.data);
}

class LmBallMetricsEvent extends LmEvent {
  final BallMetrics data;
  const LmBallMetricsEvent(this.data);
}

class LmClubMetricsEvent extends LmEvent {
  final ClubMetrics data;
  const LmClubMetricsEvent(this.data);
}

class LmAlignmentEvent extends LmEvent {
  final AlignmentData data;
  const LmAlignmentEvent(this.data);
}

class LmStatusEvent extends LmEvent {
  final LaunchMonitorStatus status;
  const LmStatusEvent(this.status);
}

class LmBatteryEvent extends LmEvent {
  final int percent;
  const LmBatteryEvent(this.percent);
}

class LmRawEvent extends LmEvent {
  final List<String> bytes;
  const LmRawEvent(this.bytes);
}

class LaunchMonitorService {
  final BleAdapter _ble;
  final String deviceId;
  final SquareGolfDeviceType deviceType;

  /// Heartbeat cadence — matches the Go reference.
  static const Duration _heartbeatInterval = Duration(seconds: 5);

  /// Inter-command spacing for the Omni init burst (Go uses ~150ms/cmd).
  static const Duration _initStepDelay = Duration(milliseconds: 150);

  // ── Streams ────────────────────────────────────────────────────────────────

  final _connectionCtrl = StreamController<LmConnectionStatus>.broadcast();
  final _eventCtrl = StreamController<LmEvent>.broadcast();
  final _ballCtrl = StreamController<BallMetrics>.broadcast();
  final _clubCtrl = StreamController<ClubMetrics>.broadcast();
  final _sensorCtrl = StreamController<SensorData>.broadcast();
  final _alignmentCtrl = StreamController<AlignmentData>.broadcast();
  final _statusCtrl = StreamController<LaunchMonitorStatus>.broadcast();
  final _batteryCtrl = StreamController<int>.broadcast();

  Stream<LmConnectionStatus> get connectionStatus => _connectionCtrl.stream;
  Stream<LmEvent> get notifications => _eventCtrl.stream;
  Stream<BallMetrics> get ballMetrics => _ballCtrl.stream;
  Stream<ClubMetrics> get clubMetrics => _clubCtrl.stream;
  Stream<SensorData> get sensorData => _sensorCtrl.stream;
  Stream<AlignmentData> get alignment => _alignmentCtrl.stream;
  Stream<LaunchMonitorStatus> get monitorStatus => _statusCtrl.stream;
  Stream<int> get batteryLevel => _batteryCtrl.stream;

  // ── Internal state ─────────────────────────────────────────────────────────

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<int>>? _batterySub;
  StreamSubscription<bool>? _connSub;
  Timer? _heartbeat;
  int _sequence = 0;
  bool _connected = false;
  String? _lastBallRaw; // dedupe (matches Go behaviour)

  LaunchMonitorService({
    required BleAdapter ble,
    required this.deviceId,
    required this.deviceType,
  }) : _ble = ble;

  bool get isConnected => _connected;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> connect() async {
    _connectionCtrl.add(LmConnectionStatus.connecting);
    try {
      await _ble.connect(deviceId);

      _connSub = _ble.connectionStateOf(deviceId).listen((connected) {
        _connected = connected;
        _connectionCtrl.add(connected
            ? LmConnectionStatus.connected
            : LmConnectionStatus.disconnected);
        if (!connected) _stopHeartbeat();
      });

      // Subscribe to the protocol notification characteristic.
      final notifyStream = await _ble.subscribeToCharacteristic(
        deviceId: deviceId,
        serviceUuid: primaryServiceUuid,
        characteristicUuid: notificationCharUuid,
      );
      _notifySub = notifyStream.listen(
        _handleNotificationBytes,
        onError: (Object e, StackTrace s) {
          if (kDebugMode) debugPrint('LM notification error: $e');
        },
      );

      // Subscribe to the standard battery-level characteristic.
      try {
        final batteryStream = await _ble.subscribeToCharacteristic(
          deviceId: deviceId,
          serviceUuid: batteryServiceUuid,
          characteristicUuid: batteryLevelCharUuid,
        );
        _batterySub = batteryStream.listen((data) {
          if (data.isEmpty) return;
          final pct = data[0];
          _batteryCtrl.add(pct);
          _eventCtrl.add(LmBatteryEvent(pct));
        });
      } catch (_) {
        // Battery service is optional — some hosts don't expose it.
      }

      _connected = true;
      _connectionCtrl.add(LmConnectionStatus.connected);

      _startHeartbeat();

      if (deviceType == SquareGolfDeviceType.omni) {
        // Don't await — fire-and-forget, matches the Go init sequence.
        unawaited(_sendOmniInitSequence());
      }
    } catch (e) {
      _connectionCtrl.add(LmConnectionStatus.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _stopHeartbeat();
    await _notifySub?.cancel();
    await _batterySub?.cancel();
    await _connSub?.cancel();
    _notifySub = null;
    _batterySub = null;
    _connSub = null;
    _connected = false;
    try {
      await _ble.disconnect(deviceId);
    } catch (_) {}
    _connectionCtrl.add(LmConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionCtrl.close();
    await _eventCtrl.close();
    await _ballCtrl.close();
    await _clubCtrl.close();
    await _sensorCtrl.close();
    await _alignmentCtrl.close();
    await _statusCtrl.close();
    await _batteryCtrl.close();
  }

  // ── Public commands ────────────────────────────────────────────────────────

  /// Activate ball detection. Optionally specify [spinMode].
  Future<void> activateBallDetection({
    SpinMode spinMode = SpinMode.standard,
  }) =>
      _send(detectBallCommand(_nextSeq(), DetectBallMode.activate, spinMode));

  Future<void> deactivateBallDetection() => _send(
      detectBallCommand(_nextSeq(), DetectBallMode.deactivate, SpinMode.standard));

  Future<void> selectClub(ClubCode club, Handedness handedness) {
    final cmd = deviceType == SquareGolfDeviceType.omni
        ? omniClubCommand(_nextSeq(), club, handedness)
        : clubCommand(_nextSeq(), club, handedness);
    return _send(cmd);
  }

  Future<void> requestClubMetrics() =>
      _send(requestClubMetricsCommand(_nextSeq()));

  Future<void> setOmniHandedness(Handedness handedness) =>
      _send(omniSetHandedCommand(_nextSeq(), handedness));

  Future<void> setOmniUnits({
    required OmniSpeedUnit speed,
    required OmniDistanceUnit distance,
  }) =>
      _send(omniSetUnitsCommand(_nextSeq(), speed, distance));

  Future<void> setOmniGreenSpeed(int greenSpeedIndex) =>
      _send(omniSetGreenSpeedCommand(_nextSeq(), greenSpeedIndex));

  Future<void> setOmniCarryAdjustment(int adjustment) =>
      _send(omniSetCarryDistanceAdjustmentCommand(_nextSeq(), adjustment));

  Future<void> startAlignment() => _send(startAlignmentCommand(_nextSeq()));

  Future<void> stopAlignment(double targetAngle) =>
      _send(stopAlignmentCommand(_nextSeq(), targetAngle));

  Future<void> cancelAlignment(double targetAngle) =>
      _send(cancelAlignmentCommand(_nextSeq(), targetAngle));

  // ── Internal: command sending ──────────────────────────────────────────────

  int _nextSeq() {
    _sequence = (_sequence + 1) & 0xFF;
    return _sequence;
  }

  Future<void> _send(Uint8List command) async {
    if (!_connected) {
      throw StateError('LaunchMonitorService is not connected');
    }
    await _ble.writeCharacteristic(
      deviceId: deviceId,
      serviceUuid: primaryServiceUuid,
      characteristicUuid: commandCharUuid,
      data: command,
      withResponse: true,
    );
  }

  // ── Internal: heartbeat ────────────────────────────────────────────────────

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) async {
      if (!_connected) return;
      try {
        await _send(heartbeatCommand(_nextSeq()));
      } catch (e) {
        if (kDebugMode) debugPrint('LM heartbeat failed: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ── Internal: Omni init ────────────────────────────────────────────────────

  Future<void> _sendOmniInitSequence() async {
    // Default values — caller is expected to push their own settings via the
    // dedicated setter methods after connection. These keep the device alive
    // until the first user-triggered config arrives.
    final commands = <Uint8List>[
      omniSetUnitsCommand(
          _nextSeq(), OmniSpeedUnit.mph, OmniDistanceUnit.yardsFeet),
      omniSetCarryDistanceAdjustmentCommand(_nextSeq(), 0),
      omniSetGreenSpeedCommand(_nextSeq(), 2), // index 2 = 10
      omniSetHandedCommand(_nextSeq(), Handedness.rightHanded),
    ];

    for (final cmd in commands) {
      if (!_connected) return;
      try {
        await _send(cmd);
      } catch (e) {
        if (kDebugMode) debugPrint('LM Omni init step failed: $e');
      }
      await Future<void>.delayed(_initStepDelay);
    }
  }

  // ── Internal: notification routing ─────────────────────────────────────────

  void _handleNotificationBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    final list = bytesToHexList(Uint8List.fromList(bytes));
    _eventCtrl.add(LmRawEvent(list));

    final kind = classify(list);
    try {
      switch (kind) {
        case NotificationKind.sensor:
          final s = parseSensorData(list);
          _sensorCtrl.add(s);
          _eventCtrl.add(LmSensorEvent(s));
          break;
        case NotificationKind.ballMetrics:
          // Dedupe like the Go reference: identical raw bytes → same shot.
          final raw = list.join(' ');
          if (raw == _lastBallRaw) return;
          _lastBallRaw = raw;
          var b = parseShotBallMetrics(list);
          if (deviceType == SquareGolfDeviceType.omni) {
            b = applyOmniBallValidityBitmask(b);
          }
          _ballCtrl.add(b);
          _eventCtrl.add(LmBallMetricsEvent(b));
          // Auto-request club metrics after a fresh shot.
          unawaited(_send(requestClubMetricsCommand(_nextSeq()))
              .catchError((Object _) {}));
          break;
        case NotificationKind.clubMetrics:
          final c = deviceType == SquareGolfDeviceType.omni
              ? parseOmniShotClubMetrics(list)
              : parseShotClubMetrics(list);
          _clubCtrl.add(c);
          _eventCtrl.add(LmClubMetricsEvent(c));
          break;
        case NotificationKind.alignment:
          final a = parseAlignmentData(list);
          _alignmentCtrl.add(a);
          _eventCtrl.add(LmAlignmentEvent(a));
          break;
        case NotificationKind.status:
          if (list.length < 3) break;
          final statusIdx =
              deviceType == SquareGolfDeviceType.omni ? 3 : 2;
          if (list.length <= statusIdx) break;
          final status = switch (list[statusIdx]) {
            '00' => LaunchMonitorStatus.none,
            '01' => LaunchMonitorStatus.idle,
            '02' => LaunchMonitorStatus.init,
            '03' => LaunchMonitorStatus.detect,
            '04' => LaunchMonitorStatus.ready,
            '05' => LaunchMonitorStatus.shot,
            '06' => LaunchMonitorStatus.done,
            _ => null,
          };
          if (status != null) {
            _statusCtrl.add(status);
            _eventCtrl.add(LmStatusEvent(status));
          }
          break;
        case NotificationKind.battery:
          if (list.length >= 3) {
            final pct = int.tryParse(list[2], radix: 16);
            if (pct != null) {
              _batteryCtrl.add(pct);
              _eventCtrl.add(LmBatteryEvent(pct));
            }
          }
          break;
        case NotificationKind.charge:
        case NotificationKind.osVersion:
        case NotificationKind.unknown:
          // Not yet routed to a typed stream — raw event still emitted.
          break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LM parse error ($kind): $e');
    }
  }
}
