/// High-level service that wraps the [BleAdapter] with the Square Golf
/// protocol — handles connection lifecycle, post-connect reads, the heartbeat,
/// capacitor-charge polling, the Omni init handshake, a serialized command
/// queue, and decodes incoming notifications into typed streams.
///
/// Ported from `squaregolf-connector` (Go) — see `internal/core/launch_monitor.go`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ble_adapter.dart';
import 'commands.dart';
import 'constants.dart';
import 'log.dart';
import 'notifications.dart';

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

class LmCapacitorEvent extends LmEvent {
  final bool ready;
  const LmCapacitorEvent(this.ready);
}

class LmRawEvent extends LmEvent {
  final List<String> bytes;
  const LmRawEvent(this.bytes);
}

/// Firmware versions read from the device-info characteristic (JSON).
class FirmwareVersions {
  final String? launcher;
  final String? mmi;
  final String? lm;

  const FirmwareVersions({this.launcher, this.mmi, this.lm});

  /// The primary "firmware version" is the `lm` field.
  String? get primary => lm;

  @override
  String toString() => 'FirmwareVersions(launcher: $launcher, mmi: $mmi, lm: $lm)';
}

/// One queued outbound command awaiting serialized execution.
class _QueuedCommand {
  final Uint8List bytes;
  final String label;
  final Completer<void> completer;
  _QueuedCommand(this.bytes, this.label, this.completer);
}

class LaunchMonitorService {
  final BleAdapter _ble;
  final String deviceId;
  final SquareGolfDeviceType deviceType;

  /// Heartbeat cadence — matches the Go reference.
  static const Duration _heartbeatInterval = Duration(seconds: 5);

  /// Capacitor-charge polling cadence.
  static const Duration _chargePollInterval = Duration(seconds: 3);

  /// Inter-command spacing on the serialized queue (Go uses ~150ms/cmd).
  static const Duration _commandSpacing = Duration(milliseconds: 150);

  /// Per-command execution timeout while draining the queue.
  static const Duration _commandTimeout = Duration(seconds: 5);

  /// Omni club-metrics retry window (1s, then 1s more).
  static const Duration _clubMetricsRetry = Duration(seconds: 1);

  // ── Streams ────────────────────────────────────────────────────────────────

  final _connectionCtrl = StreamController<LmConnectionStatus>.broadcast();
  final _eventCtrl = StreamController<LmEvent>.broadcast();
  final _ballCtrl = StreamController<BallMetrics>.broadcast();
  final _clubCtrl = StreamController<ClubMetrics>.broadcast();
  final _sensorCtrl = StreamController<SensorData>.broadcast();
  final _alignmentCtrl = StreamController<AlignmentData>.broadcast();
  final _statusCtrl = StreamController<LaunchMonitorStatus>.broadcast();
  final _batteryCtrl = StreamController<int>.broadcast();
  final _capacitorCtrl = StreamController<bool>.broadcast();

  Stream<LmConnectionStatus> get connectionStatus => _connectionCtrl.stream;
  Stream<LmEvent> get notifications => _eventCtrl.stream;
  Stream<BallMetrics> get ballMetrics => _ballCtrl.stream;
  Stream<ClubMetrics> get clubMetrics => _clubCtrl.stream;
  Stream<SensorData> get sensorData => _sensorCtrl.stream;
  Stream<AlignmentData> get alignment => _alignmentCtrl.stream;
  Stream<LaunchMonitorStatus> get monitorStatus => _statusCtrl.stream;
  Stream<int> get batteryLevel => _batteryCtrl.stream;
  Stream<bool> get capacitorReadyStream => _capacitorCtrl.stream;

  // ── Device info (populated during connect) ──────────────────────────────────

  String? serialNumber;
  int? batteryPercent;
  FirmwareVersions firmware = const FirmwareVersions();
  String? osVersion;

  bool get capacitorReady => _capacitorReady;

  // ── Internal state ─────────────────────────────────────────────────────────

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<int>>? _batterySub;
  StreamSubscription<bool>? _connSub;
  Timer? _heartbeat;
  Timer? _chargeTimer;
  Timer? _clubRetry1;
  Timer? _clubRetry2;
  int _sequence = 0;
  bool _connected = false;
  bool _capacitorReady = false;
  String? _lastBallRaw; // dedupe (matches Go behaviour)
  bool _awaitingClubMetrics = false;

  // Ball-detection / arming state (for idle-recovery + putter handling).
  bool _detectActive = false;
  SpinMode _currentSpin = SpinMode.advanced;
  ClubCode _currentClub = ClubCodes.driver;
  Handedness _currentHand = Handedness.rightHanded;
  int _idleStatusCount = 0;

  /// Optional starting handedness. The reference only sends SetHanded during
  /// the Omni init burst when handedness is *known*; null means "skip it".
  final Handedness? _initialHandedness;

  // Serialized command queue.
  final List<_QueuedCommand> _queue = [];
  bool _queueProcessing = false;

  LaunchMonitorService({
    required BleAdapter ble,
    required this.deviceId,
    required this.deviceType,
    Handedness? initialHandedness,
  })  : _ble = ble,
        _initialHandedness = initialHandedness;

  bool get isConnected => _connected;

  bool get _isPutter => _currentClub.regularCode == ClubCodes.putter.regularCode;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> connect() async {
    lmLog('conn', 'connect() deviceId=$deviceId type=${deviceType.name}');
    _connectionCtrl.add(LmConnectionStatus.connecting);
    try {
      await _ble.connect(deviceId);
      lmLog('conn', 'BLE link established');

      // Discover all services/characteristics up front; everything is matched
      // by characteristic UUID (no hard-coded service UUID).
      await _ble.discoverServices(deviceId);

      _connSub = _ble.connectionStateOf(deviceId).listen((connected) {
        _connected = connected;
        lmLog('conn',
            connected ? 'state → connected' : 'state → disconnected');
        if (!connected) {
          _connectionCtrl.add(LmConnectionStatus.disconnected);
          _stopHeartbeat();
          _stopChargePolling();
        }
      });

      // ── Post-connect reads (in reference order) ──────────────────────────
      serialNumber = await _readSerialWithRetry();
      lmLog('conn', 'serial=${serialNumber ?? "?"}');

      batteryPercent = await _readBatteryLevel();
      if (batteryPercent != null) {
        _batteryCtrl.add(batteryPercent!);
        _eventCtrl.add(LmBatteryEvent(batteryPercent!));
      }

      firmware = await _readFirmware();
      lmLog('conn', 'firmware=$firmware');

      // Subscribe to the protocol notification characteristic.
      lmLog('conn', 'subscribing notify char $notificationCharUuid');
      final notifyStream = await _ble.subscribeToCharacteristic(
        deviceId: deviceId,
        characteristicUuid: notificationCharUuid,
      );
      _notifySub = notifyStream.listen(
        _handleNotificationBytes,
        onError: (Object e, StackTrace s) {
          lmWarn('notify', 'stream error: $e');
        },
      );

      // Subscribe to the standard battery-level characteristic (non-fatal).
      try {
        lmLog('conn', 'subscribing battery char $batteryLevelCharUuid');
        final batteryStream = await _ble.subscribeToCharacteristic(
          deviceId: deviceId,
          characteristicUuid: batteryLevelCharUuid,
        );
        _batterySub = batteryStream.listen((data) {
          if (data.isEmpty) return;
          final pct = data[0];
          lmLog('notify', '<- battery $pct%');
          batteryPercent = pct;
          _batteryCtrl.add(pct);
          _eventCtrl.add(LmBatteryEvent(pct));
        });
      } catch (e) {
        lmLog('conn', 'battery notify unavailable, continuing ($e)');
      }

      _connected = true;
      _connectionCtrl.add(LmConnectionStatus.connected);
      lmLog('conn', 'ready — starting heartbeat + charge polling');

      _startHeartbeat();
      _startChargePolling();

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
    // Pre-disconnect hook: leave the device in a clean state by deactivating
    // ball detection first (best-effort, short timeout).
    if (_connected) {
      try {
        await _ble
            .writeCharacteristic(
              deviceId: deviceId,
              characteristicUuid: commandCharUuid,
              data: detectBallCommand(
                  _nextSeq(), DetectBallMode.deactivate, _currentSpin),
              withResponse: true,
            )
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        lmLog('conn', 'pre-disconnect deactivate skipped: $e');
      }
    }

    _stopHeartbeat();
    _stopChargePolling();
    _cancelClubMetricsRetry();
    await _notifySub?.cancel();
    await _batterySub?.cancel();
    await _connSub?.cancel();
    _notifySub = null;
    _batterySub = null;
    _connSub = null;
    _connected = false;
    _detectActive = false;
    _idleStatusCount = 0;
    _drainQueue();

    // Reset derived state.
    _capacitorReady = false;
    _lastBallRaw = null;

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
    await _capacitorCtrl.close();
  }

  // ── Post-connect reads ───────────────────────────────────────────────────

  Future<String?> _readSerialWithRetry() async {
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        final bytes = await _ble.readCharacteristic(
          deviceId: deviceId,
          characteristicUuid: serialNumberCharUuid,
        );
        final value = _decodeText(bytes);
        if (value.isNotEmpty) return value;
      } catch (e) {
        lmLog('conn', 'serial read attempt $attempt failed: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    lmWarn('conn', 'serial number unavailable after 5 attempts');
    return null;
  }

  Future<int?> _readBatteryLevel() async {
    try {
      final bytes = await _ble.readCharacteristic(
        deviceId: deviceId,
        characteristicUuid: batteryLevelCharUuid,
      );
      if (bytes.isNotEmpty) return bytes[0];
    } catch (e) {
      lmLog('conn', 'battery read failed: $e');
    }
    return null;
  }

  Future<FirmwareVersions> _readFirmware() async {
    try {
      final bytes = await _ble.readCharacteristic(
        deviceId: deviceId,
        characteristicUuid: firmwareVersionCharUuid,
      );
      final text = _decodeText(bytes);
      final json = jsonDecode(text);
      if (json is Map) {
        return FirmwareVersions(
          launcher: json['launcher']?.toString(),
          mmi: json['mmi']?.toString(),
          lm: json['lm']?.toString(),
        );
      }
    } catch (e) {
      lmWarn('conn', 'firmware read/parse failed: $e');
    }
    return const FirmwareVersions();
  }

  String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true).replaceAll(' ', '').trim();
    } catch (_) {
      return '';
    }
  }

  // ── Public commands ────────────────────────────────────────────────────────

  /// Activate ball detection. Defaults to advanced spin (matches reference).
  Future<void> activateBallDetection({
    SpinMode spinMode = SpinMode.advanced,
  }) {
    _currentSpin = spinMode;
    _detectActive = true;
    _idleStatusCount = 0;
    return _send(
      detectBallCommand(_nextSeq(), DetectBallMode.activate, spinMode),
      label: 'activateBallDetection(spin=${spinMode.name})',
    );
  }

  Future<void> deactivateBallDetection() {
    _detectActive = false;
    _idleStatusCount = 0;
    return _send(
      detectBallCommand(_nextSeq(), DetectBallMode.deactivate, _currentSpin),
      label: 'deactivateBallDetection',
    );
  }

  /// Arm for a shot: select [club] + [handedness], then activate detection.
  /// Matches the reference's two-step activate sequence (§6).
  Future<void> armBallDetection({
    ClubCode? club,
    Handedness? handedness,
    SpinMode spinMode = SpinMode.advanced,
  }) async {
    await selectClub(
      club ?? _currentClub,
      handedness ?? _currentHand,
    );
    await activateBallDetection(spinMode: spinMode);
  }

  /// Enter alignment mode (red LED aim calibration, §6): select the alignment
  /// stick, wait ~1s, then activate detect-ball mode 2.
  Future<void> enterAlignmentMode({Handedness? handedness}) async {
    await selectClub(ClubCodes.alignmentStick, handedness ?? _currentHand);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _send(
      detectBallCommand(
          _nextSeq(), DetectBallMode.activateAlignmentMode, SpinMode.advanced),
      label: 'enterAlignmentMode',
    );
  }

  Future<void> selectClub(ClubCode club, Handedness handedness) {
    _currentClub = club;
    _currentHand = handedness;
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

  Future<void> setOmniHandedness(Handedness handedness) {
    _currentHand = handedness;
    return _send(
      omniSetHandedCommand(_nextSeq(), handedness),
      label: 'omniSetHanded(${handedness.name})',
    );
  }

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

  // ── Internal: command queue (serialized, 150ms spacing) ────────────────────

  int _nextSeq() {
    _sequence = (_sequence + 1) & 0xFF;
    return _sequence;
  }

  Future<void> _send(Uint8List command, {String? label}) {
    if (!_connected) {
      return Future.error(
          StateError('LaunchMonitorService is not connected'));
    }
    final completer = Completer<void>();
    _queue.add(_QueuedCommand(command, label ?? 'cmd', completer));
    unawaited(_processQueue());
    // Mirror the Go reference's 5s execution budget.
    return completer.future.timeout(_commandTimeout);
  }

  Future<void> _processQueue() async {
    if (_queueProcessing) return;
    _queueProcessing = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        if (!_connected) {
          item.completer.completeError(
              StateError('disconnected before command executed'));
          continue;
        }
        final isHeartbeat = item.label == 'heartbeat';
        if (!isHeartbeat || kLmLogHeartbeats) {
          lmLog('cmd', '-> ${lmHex(item.bytes)}  (${item.label})');
        }
        try {
          await _ble
              .writeCharacteristic(
                deviceId: deviceId,
                characteristicUuid: commandCharUuid,
                data: item.bytes,
                withResponse: true,
              )
              .timeout(_commandTimeout);
          if (!item.completer.isCompleted) item.completer.complete();
        } catch (e) {
          lmWarn(item.label, 'write failed: $e');
          if (!item.completer.isCompleted) item.completer.completeError(e);
        }
        // Spacing between writes — the device drops commands sent too fast.
        await Future<void>.delayed(_commandSpacing);
      }
    } finally {
      _queueProcessing = false;
    }
  }

  void _drainQueue() {
    for (final item in _queue) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(StateError('command queue drained'));
      }
    }
    _queue.clear();
  }

  // ── Internal: heartbeat ────────────────────────────────────────────────────

  void _startHeartbeat() {
    _stopHeartbeat();
    lmLog('hb', 'heartbeat scheduled every ${_heartbeatInterval.inSeconds}s');
    // Reference sends one immediately, then on the ticker.
    unawaited(_send(heartbeatCommand(_nextSeq()), label: 'heartbeat')
        .catchError((Object _) {}));
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

  // ── Internal: capacitor charge polling ──────────────────────────────────────

  void _startChargePolling() {
    _stopChargePolling();
    _capacitorReady = false;
    lmLog('chg', 'charge polling every ${_chargePollInterval.inSeconds}s');
    unawaited(_send(getChargeCommand(_nextSeq()), label: 'getCharge')
        .catchError((Object _) {}));
    _chargeTimer = Timer.periodic(_chargePollInterval, (_) async {
      if (!_connected || _capacitorReady) return;
      try {
        await _send(getChargeCommand(_nextSeq()), label: 'getCharge');
      } catch (e) {
        lmWarn('chg', 'getCharge failed: $e');
      }
    });
  }

  void _stopChargePolling() {
    if (_chargeTimer != null) lmLog('chg', 'charge polling stopped');
    _chargeTimer?.cancel();
    _chargeTimer = null;
  }

  // ── Internal: Omni init ────────────────────────────────────────────────────

  Future<void> _sendOmniInitSequence() async {
    lmLog('init', 'Omni init sequence starting');
    final handed = _initialHandedness;
    // Reference defaults: m/s, meters, carry 0, stimp 10 (idx 2). SetHanded
    // is only sent when handedness is known.
    final steps = <(String, Uint8List)>[
      (
        'SetUnits(m/s, meters)',
        omniSetUnitsCommand(
            _nextSeq(), OmniSpeedUnit.metersPerSecond, OmniDistanceUnit.meters),
      ),
      (
        'SetCarryDistanceAdjustment(0)',
        omniSetCarryDistanceAdjustmentCommand(_nextSeq(), 0),
      ),
      (
        'SetGreenSpeed(idx=2 → 10)',
        omniSetGreenSpeedCommand(_nextSeq(), 2),
      ),
      if (handed != null)
        (
          'SetHanded(${handed.name})',
          omniSetHandedCommand(_nextSeq(), handed),
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
    }
    lmLog('init', 'Omni init sequence complete');
  }

  // ── Internal: club-metrics retry (Omni) ─────────────────────────────────────

  void _scheduleClubMetricsRetry() {
    if (deviceType != SquareGolfDeviceType.omni) return;
    _cancelClubMetricsRetry();
    _awaitingClubMetrics = true;
    _clubRetry1 = Timer(_clubMetricsRetry, () {
      if (!_awaitingClubMetrics || !_connected) return;
      lmLog('club', 'no club metrics after 1s — re-requesting');
      unawaited(_send(requestClubMetricsCommand(_nextSeq()),
              label: 'retry requestClubMetrics')
          .catchError((Object _) {}));
      _clubRetry2 = Timer(_clubMetricsRetry, () {
        if (!_awaitingClubMetrics) return;
        lmLog('club', 'club metrics timed out — emitting empty result');
        _awaitingClubMetrics = false;
        final empty = ClubMetrics(rawData: const []);
        _clubCtrl.add(empty);
        _eventCtrl.add(LmClubMetricsEvent(empty));
      });
    });
  }

  void _cancelClubMetricsRetry() {
    _clubRetry1?.cancel();
    _clubRetry2?.cancel();
    _clubRetry1 = null;
    _clubRetry2 = null;
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
            // Putter + Omni: spin fields are not measured.
            if (_isPutter) {
              b = b.copyWith(
                isTotalSpinValid: false,
                isSpinAxisValid: false,
                isBackspinValid: false,
                isSidespinValid: false,
              );
            }
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
          // Auto-request club metrics after a fresh shot, with Omni retry.
          _scheduleClubMetricsRetry();
          unawaited(_send(requestClubMetricsCommand(_nextSeq()),
                  label: 'auto requestClubMetrics')
              .catchError((Object _) {}));
          break;
        case NotificationKind.clubMetrics:
          _awaitingClubMetrics = false;
          _cancelClubMetricsRetry();
          var c = deviceType == SquareGolfDeviceType.omni
              ? parseOmniShotClubMetrics(list)
              : parseShotClubMetrics(list);
          // Putter: club metrics are not measured — force all fields invalid.
          if (_isPutter) c = ClubMetrics(rawData: c.rawData);
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
          // Omni: sync handedness from byte[6] (00=right, 01=left).
          if (deviceType == SquareGolfDeviceType.omni && list.length > 6) {
            final hb = list[6];
            if (hb == '00') {
              _currentHand = Handedness.rightHanded;
            } else if (hb == '01') {
              _currentHand = Handedness.leftHanded;
            }
          }
          lmLog(
            'notify',
            '<- $hex  → STATUS ${status?.name ?? "unknown(${list[statusIdx]})"}',
          );
          if (status != null) {
            _statusCtrl.add(status);
            _eventCtrl.add(LmStatusEvent(status));
            _handleOmniIdleRecovery(status);
          }
          break;
        case NotificationKind.battery:
          // 91 frame: byte[1] = level, byte[2] (if present) = charging status.
          if (list.length >= 2) {
            final pct = int.tryParse(list[1], radix: 16);
            lmLog('notify', '<- $hex  → BATTERY ${pct ?? "?"}%');
            if (pct != null) {
              batteryPercent = pct;
              _batteryCtrl.add(pct);
              _eventCtrl.add(LmBatteryEvent(pct));
            }
          }
          break;
        case NotificationKind.charge:
          // byte[3] == 01 ⇒ capacitor ready.
          final ready = list.length > 3 && list[3] == '01';
          lmLog('notify', '<- $hex  → CHARGE ready=$ready');
          if (ready && !_capacitorReady) {
            _capacitorReady = true;
            _stopChargePolling();
            _capacitorCtrl.add(true);
            _eventCtrl.add(const LmCapacitorEvent(true));
          }
          break;
        case NotificationKind.osVersion:
          // version = "{int(byte[2])}.{int(byte[3])}"
          if (list.length > 3) {
            final major = int.tryParse(list[2], radix: 16);
            final minor = int.tryParse(list[3], radix: 16);
            if (major != null && minor != null) {
              osVersion = '$major.$minor';
              lmLog('notify', '<- $hex  → OS_VERSION $osVersion');
            }
          }
          break;
        case NotificationKind.unknown:
          lmLog('notify', '<- $hex  → UNKNOWN');
          break;
      }
    } catch (e, s) {
      lmWarn('notify', 'parse error ($kind): $e\nframe=$hex\n$s');
    }
  }

  /// Omni idle-recovery: if detect mode is active and the device reports
  /// none/idle on two consecutive status packets, re-arm by re-sending the
  /// detect-ball activate command. Any non-idle status resets the counter.
  void _handleOmniIdleRecovery(LaunchMonitorStatus status) {
    if (deviceType != SquareGolfDeviceType.omni || !_detectActive) return;
    final isIdle = status == LaunchMonitorStatus.none ||
        status == LaunchMonitorStatus.idle;
    if (!isIdle) {
      _idleStatusCount = 0;
      return;
    }
    _idleStatusCount++;
    if (_idleStatusCount >= 2) {
      _idleStatusCount = 0;
      lmLog('detect', 'idle x2 — re-arming ball detection');
      unawaited(_send(
        detectBallCommand(_nextSeq(), DetectBallMode.activate, _currentSpin),
        label: 're-arm detectBall',
      ).catchError((Object _) {}));
    }
  }
}
