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
import 'log.dart';
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
    lmLog('conn', 'connect() deviceId=$deviceId type=${deviceType.name}');
    _connectionCtrl.add(LmConnectionStatus.connecting);
    try {
      await _ble.connect(deviceId);
      lmLog('conn', 'BLE link established');

      _connSub = _ble.connectionStateOf(deviceId).listen((connected) {
        _connected = connected;
        lmLog('conn',
            connected ? 'state → connected' : 'state → disconnected');
        _connectionCtrl.add(connected
            ? LmConnectionStatus.connected
            : LmConnectionStatus.disconnected);
        if (!connected) _stopHeartbeat();
      });

      // Subscribe to the protocol notification characteristic.
      lmLog('conn', 'subscribing notify char $notificationCharUuid');
      final notifyStream = await _ble.subscribeToCharacteristic(
        deviceId: deviceId,
        serviceUuid: primaryServiceUuid,
        characteristicUuid: notificationCharUuid,
      );
      _notifySub = notifyStream.listen(
        _handleNotificationBytes,
        onError: (Object e, StackTrace s) {
          lmWarn('notify', 'stream error: $e');
        },
      );

      // Subscribe to the standard battery-level characteristic.
      try {
        lmLog('conn', 'subscribing battery char $batteryLevelCharUuid');
        final batteryStream = await _ble.subscribeToCharacteristic(
          deviceId: deviceId,
          serviceUuid: batteryServiceUuid,
          characteristicUuid: batteryLevelCharUuid,
        );
        _batterySub = batteryStream.listen((data) {
          if (data.isEmpty) return;
          final pct = data[0];
          lmLog('notify', '<- battery $pct%');
          _batteryCtrl.add(pct);
          _eventCtrl.add(LmBatteryEvent(pct));
        });
      } catch (e) {
        lmLog('conn', 'no battery service exposed ($e)');
      }

      _connected = true;
      _connectionCtrl.add(LmConnectionStatus.connected);
      lmLog('conn', 'ready — starting heartbeat');

      _startHeartbeat();

      if (deviceType == SquareGolfDeviceType.omni) {
        // Don't await — fire-and-forget, matches the Go init sequence.
        unawaited(_sendOmniInitSequence());
      }
    } catch (e, s) {
      lmWarn('conn', 'connect failed: $e\n$s');
      _connectionCtrl.add(LmConnectionStatus.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    lmLog('conn', 'disconnect()');
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
    } catch (e) {
      lmWarn('conn', 'platform disconnect threw: $e');
    }
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
      _send(
        detectBallCommand(_nextSeq(), DetectBallMode.activate, spinMode),
        label: 'activateBallDetection(spin=${spinMode.name})',
      );

  Future<void> deactivateBallDetection() => _send(
        detectBallCommand(
            _nextSeq(), DetectBallMode.deactivate, SpinMode.standard),
        label: 'deactivateBallDetection',
      );

  Future<void> selectClub(ClubCode club, Handedness handedness) {
    final cmd = deviceType == SquareGolfDeviceType.omni
        ? omniClubCommand(_nextSeq(), club, handedness)
        : clubCommand(_nextSeq(), club, handedness);
    return _send(
      cmd,
      label: 'selectClub(${club.regularCode}, ${handedness.name})',
    );
  }

  Future<void> requestClubMetrics() => _send(
        requestClubMetricsCommand(_nextSeq()),
        label: 'requestClubMetrics',
      );

  Future<void> setOmniHandedness(Handedness handedness) => _send(
        omniSetHandedCommand(_nextSeq(), handedness),
        label: 'omniSetHanded(${handedness.name})',
      );

  Future<void> setOmniUnits({
    required OmniSpeedUnit speed,
    required OmniDistanceUnit distance,
  }) =>
      _send(
        omniSetUnitsCommand(_nextSeq(), speed, distance),
        label: 'omniSetUnits(${speed.name}, ${distance.name})',
      );

  Future<void> setOmniGreenSpeed(int greenSpeedIndex) => _send(
        omniSetGreenSpeedCommand(_nextSeq(), greenSpeedIndex),
        label: 'omniSetGreenSpeed($greenSpeedIndex)',
      );

  Future<void> setOmniCarryAdjustment(int adjustment) => _send(
        omniSetCarryDistanceAdjustmentCommand(_nextSeq(), adjustment),
        label: 'omniSetCarryAdjustment($adjustment)',
      );

  Future<void> startAlignment() => _send(
        startAlignmentCommand(_nextSeq()),
        label: 'startAlignment',
      );

  Future<void> stopAlignment(double targetAngle) => _send(
        stopAlignmentCommand(_nextSeq(), targetAngle),
        label: 'stopAlignment($targetAngle°)',
      );

  Future<void> cancelAlignment(double targetAngle) => _send(
        cancelAlignmentCommand(_nextSeq(), targetAngle),
        label: 'cancelAlignment($targetAngle°)',
      );

  // ── Internal: command sending ──────────────────────────────────────────────

  int _nextSeq() {
    _sequence = (_sequence + 1) & 0xFF;
    return _sequence;
  }

  Future<void> _send(Uint8List command, {String? label}) async {
    if (!_connected) {
      throw StateError('LaunchMonitorService is not connected');
    }
    final tag = label ?? 'cmd';
    final isHeartbeat = label == 'heartbeat';
    if (!isHeartbeat || kLmLogHeartbeats) {
      lmLog('cmd', '-> ${lmHex(command)}${label != null ? '  ($label)' : ''}');
    }
    try {
      await _ble.writeCharacteristic(
        deviceId: deviceId,
        serviceUuid: primaryServiceUuid,
        characteristicUuid: commandCharUuid,
        data: command,
        withResponse: true,
      );
    } catch (e) {
      lmWarn(tag, 'write failed: $e');
      rethrow;
    }
  }

  // ── Internal: heartbeat ────────────────────────────────────────────────────

  void _startHeartbeat() {
    _stopHeartbeat();
    lmLog('hb', 'heartbeat scheduled every ${_heartbeatInterval.inSeconds}s');
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) async {
      if (!_connected) return;
      try {
        await _send(heartbeatCommand(_nextSeq()), label: 'heartbeat');
      } catch (e) {
        lmWarn('hb', 'heartbeat failed: $e');
      }
    });
  }

  void _stopHeartbeat() {
    if (_heartbeat != null) lmLog('hb', 'heartbeat stopped');
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ── Internal: Omni init ────────────────────────────────────────────────────

  Future<void> _sendOmniInitSequence() async {
    lmLog('init', 'Omni init sequence starting');
    // Default values — caller is expected to push their own settings via the
    // dedicated setter methods after connection. These keep the device alive
    // until the first user-triggered config arrives.
    final steps = <(String, Uint8List)>[
      (
        'SetUnits(mph, yardsFeet)',
        omniSetUnitsCommand(
            _nextSeq(), OmniSpeedUnit.mph, OmniDistanceUnit.yardsFeet),
      ),
      (
        'SetCarryDistanceAdjustment(0)',
        omniSetCarryDistanceAdjustmentCommand(_nextSeq(), 0),
      ),
      (
        'SetGreenSpeed(idx=2 → 10)',
        omniSetGreenSpeedCommand(_nextSeq(), 2),
      ),
      (
        'SetHanded(right)',
        omniSetHandedCommand(_nextSeq(), Handedness.rightHanded),
      ),
    ];

    for (final (name, cmd) in steps) {
      if (!_connected) {
        lmLog('init', 'aborting — disconnected');
        return;
      }
      try {
        await _send(cmd, label: 'init: $name');
      } catch (e) {
        lmWarn('init', '$name failed: $e');
      }
      await Future<void>.delayed(_initStepDelay);
    }
    lmLog('init', 'Omni init sequence complete');
  }

  // ── Internal: notification routing ─────────────────────────────────────────

  void _handleNotificationBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    final list = bytesToHexList(Uint8List.fromList(bytes));
    final hex = lmHexList(list);
    _eventCtrl.add(LmRawEvent(list));

    final kind = classify(list);
    try {
      switch (kind) {
        case NotificationKind.sensor:
          final s = parseSensorData(list);
          lmLog(
            'notify',
            '<- $hex  → SENSOR ready=${s.ballReady} '
                'detected=${s.ballDetected} '
                'pos=(${s.positionX}, ${s.positionY}, ${s.positionZ})',
          );
          _sensorCtrl.add(s);
          _eventCtrl.add(LmSensorEvent(s));
          break;
        case NotificationKind.ballMetrics:
          // Dedupe like the Go reference: identical raw bytes → same shot.
          final raw = list.join(' ');
          if (raw == _lastBallRaw) {
            lmLog('notify', '<- $hex  → BALL (duplicate, ignored)');
            return;
          }
          _lastBallRaw = raw;
          var b = parseShotBallMetrics(list);
          if (deviceType == SquareGolfDeviceType.omni) {
            b = applyOmniBallValidityBitmask(b);
          }
          lmLog(
            'notify',
            '<- $hex  → BALL '
                'speed=${b.ballSpeedMps.toStringAsFixed(2)}m/s '
                'launch=${b.verticalAngle.toStringAsFixed(1)}°/'
                '${b.horizontalAngle.toStringAsFixed(1)}° '
                'spin=${b.totalSpinRpm}rpm@'
                '${b.spinAxis.toStringAsFixed(1)}° '
                '(back=${b.backspinRpm} side=${b.sidespinRpm}) '
                'valid[s=${b.isBallSpeedValid} t=${b.isTotalSpinValid} '
                'a=${b.isSpinAxisValid} b=${b.isBackspinValid} '
                'sd=${b.isSidespinValid}] '
                'mask=${b.validityBitmask}',
          );
          _ballCtrl.add(b);
          _eventCtrl.add(LmBallMetricsEvent(b));
          // Auto-request club metrics after a fresh shot.
          unawaited(_send(requestClubMetricsCommand(_nextSeq()),
                  label: 'auto requestClubMetrics')
              .catchError((Object _) {}));
          break;
        case NotificationKind.clubMetrics:
          final c = deviceType == SquareGolfDeviceType.omni
              ? parseOmniShotClubMetrics(list)
              : parseShotClubMetrics(list);
          lmLog(
            'notify',
            '<- $hex  → CLUB(${deviceType.name}) '
                'path=${c.pathAngle.toStringAsFixed(2)}° '
                'face=${c.faceAngle.toStringAsFixed(2)}° '
                'attack=${c.attackAngle.toStringAsFixed(2)}° '
                'loft=${c.dynamicLoftAngle.toStringAsFixed(2)}°'
                '${deviceType == SquareGolfDeviceType.omni ? ' '
                    'iH=${c.impactHorizontal.toStringAsFixed(2)} '
                    'iV=${c.impactVertical.toStringAsFixed(2)} '
                    'speed=${c.clubSpeed.toStringAsFixed(2)} '
                    'smash=${c.smashFactor.toStringAsFixed(2)}' : ''} '
                'valid[p=${c.isPathAngleValid} f=${c.isFaceAngleValid} '
                'a=${c.isAttackAngleValid} l=${c.isDynamicLoftValid}'
                '${deviceType == SquareGolfDeviceType.omni ? ' '
                    'iH=${c.isImpactHorizontalValid} '
                    'iV=${c.isImpactVerticalValid} '
                    'cs=${c.isClubSpeedValid} '
                    'sf=${c.isSmashFactorValid}' : ''}]',
          );
          _clubCtrl.add(c);
          _eventCtrl.add(LmClubMetricsEvent(c));
          break;
        case NotificationKind.alignment:
          final a = parseAlignmentData(list);
          lmLog(
            'notify',
            '<- $hex  → ALIGN '
                'angle=${a.aimAngle.toStringAsFixed(2)}° '
                'aligned=${a.isAligned}',
          );
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
          lmLog(
            'notify',
            '<- $hex  → STATUS ${status?.name ?? "unknown(${list[statusIdx]})"}',
          );
          if (status != null) {
            _statusCtrl.add(status);
            _eventCtrl.add(LmStatusEvent(status));
          }
          break;
        case NotificationKind.battery:
          if (list.length >= 3) {
            final pct = int.tryParse(list[2], radix: 16);
            lmLog('notify', '<- $hex  → BATTERY ${pct ?? "?"}%');
            if (pct != null) {
              _batteryCtrl.add(pct);
              _eventCtrl.add(LmBatteryEvent(pct));
            }
          }
          break;
        case NotificationKind.charge:
          lmLog('notify', '<- $hex  → CHARGE (not yet decoded)');
          break;
        case NotificationKind.osVersion:
          lmLog('notify', '<- $hex  → OS_VERSION (not yet decoded)');
          break;
        case NotificationKind.unknown:
          lmLog('notify', '<- $hex  → UNKNOWN');
          break;
      }
    } catch (e, s) {
      lmWarn('notify', 'parse error ($kind): $e\nframe=$hex\n$s');
    }
  }
}
