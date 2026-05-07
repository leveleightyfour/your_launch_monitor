import 'dart:async';
import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter.dart';
import 'package:omni_sniffer/features/launch_monitor/data/ble_adapter_factory.dart';
import 'package:omni_sniffer/features/launch_monitor/data/seed_data.dart';
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/constants.dart'
    as sg;
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/launch_monitor_service.dart';
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/notifications.dart'
    as sg;
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

part 'providers.g.dart';

const _deviceNamePrefix = sg.bluetoothDevicePrefix;

/// m/s → mph constant for protocol-unit conversions.
const double _mpsToMph = 2.23694;

/// A Square Golf device discovered during a scan, tagged with its detected
/// model so the picker UI can show a Home/Omni badge before connecting.
class DiscoveredSquareGolfDevice {
  final String id;
  final String name;
  final sg.SquareGolfDeviceType type;

  const DiscoveredSquareGolfDevice({
    required this.id,
    required this.name,
    required this.type,
  });
}

@riverpod
class LaunchMonitor extends _$LaunchMonitor {
  final BleAdapter _ble = createBleAdapter();
  String? _deviceId;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _ballSub;
  StreamSubscription? _clubSub;
  LaunchMonitorService? _service;

  /// DB row ID for the in-progress session (created on first shot).
  int? _draftSessionId;
  DateTime? _draftCreatedAt;

  /// Held between a ball-metrics packet and the matching club-metrics packet.
  ShotData? _pendingShotInList;
  Timer? _pendingShotTimer;

  /// Exposed so the finish-session flow can pass the ID to [SessionsNotifier].
  int? get draftSessionId => _draftSessionId;
  DateTime? get draftCreatedAt => _draftCreatedAt;

  @override
  LaunchMonitorState build() {
    ref.onDispose(_cleanup);
    // Pre-seed with sample shots so the UI has data to render during development.
    return LaunchMonitorState(shots: List.from(activeSeedShots));
  }

  // ── Public connection API ────────────────────────────────────────────────

  /// Stream of nearby Square Golf devices — filtered to names starting with
  /// `SquareGolf`, tagged with their detected model. The picker UI listens to
  /// this; tapping an entry calls [connectToDevice].
  Stream<List<DiscoveredSquareGolfDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 30),
  }) {
    final Stream<List<BleScannedDevice>> raw;
    try {
      raw = _ble.scan(timeout: timeout);
    } catch (e) {
      _setError('Scan failed: $e');
      return const Stream<List<DiscoveredSquareGolfDevice>>.empty();
    }
    // Only flip to scanning once the underlying scan call has returned a
    // stream — otherwise a synchronous throw above leaves the chip stuck.
    state = state.copyWith(status: LaunchMonitorStatus.scanning, error: null);

    return raw.map((devices) {
      return devices
          .where((d) => d.name.startsWith(_deviceNamePrefix))
          .map((d) => DiscoveredSquareGolfDevice(
                id: d.id,
                name: d.name,
                type: sg.detectDeviceType(d.manufacturerDataHex),
              ))
          .toList();
    }).handleError((Object e) {
      _setError('Scan failed: $e');
    });
  }

  Future<void> stopScan() async {
    // Reset state first so the chip never gets stuck on "scanning" even if
    // the platform stop call hangs.
    if (state.status == LaunchMonitorStatus.scanning) {
      state = state.copyWith(status: LaunchMonitorStatus.disconnected);
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    // Awaited so callers can be sure the BT stack is back to idle before
    // they kick off another scan — flutter_blue_plus rejects startScan if a
    // previous one is still being torn down.
    try {
      await _ble.stopScan();
    } catch (_) {}
  }

  /// Connect to a specific device discovered via [scanForDevices], using the
  /// real Square Golf protocol (heartbeat, Omni init burst if applicable, and
  /// typed metric streams).
  Future<void> connectToDevice(
    String deviceId,
    sg.SquareGolfDeviceType type,
  ) async {
    if (state.status == LaunchMonitorStatus.connecting ||
        state.status == LaunchMonitorStatus.connected) {
      return;
    }
    await _ble.stopScan();
    state = state.copyWith(status: LaunchMonitorStatus.connecting, error: null);
    _deviceId = deviceId;

    final svc = LaunchMonitorService(
      ble: _ble,
      deviceId: deviceId,
      deviceType: type == sg.SquareGolfDeviceType.unknown
          ? sg.SquareGolfDeviceType.home
          : type,
    );
    _service = svc;

    _connectionSubscription = svc.connectionStatus.listen((s) {
      switch (s) {
        case sg.LmConnectionStatus.connected:
          state = state.copyWith(status: LaunchMonitorStatus.connected);
          break;
        case sg.LmConnectionStatus.disconnected:
          state = state.copyWith(status: LaunchMonitorStatus.disconnected);
          break;
        case sg.LmConnectionStatus.connecting:
        case sg.LmConnectionStatus.scanning:
        case sg.LmConnectionStatus.error:
          break;
      }
    });

    _ballSub = svc.ballMetrics.listen(_onBallMetrics);
    _clubSub = svc.clubMetrics.listen(_onClubMetrics);

    try {
      await svc.connect();
    } catch (e) {
      await _disposeService();
      _setError('Connection failed: $e');
    }
  }

  /// Legacy entry point kept for the existing UI. Scans for the first Square
  /// Golf device and connects immediately (no picker). Prefer [scanForDevices]
  /// + [connectToDevice] for new flows.
  Future<void> startScan() async {
    if (state.status != LaunchMonitorStatus.disconnected) return;

    final completer = Completer<DiscoveredSquareGolfDevice?>();
    _scanSubscription = scanForDevices(
      timeout: const Duration(seconds: 15),
    ).listen((devices) {
      if (devices.isNotEmpty && !completer.isCompleted) {
        completer.complete(devices.first);
      }
    }, onDone: () {
      if (!completer.isCompleted) completer.complete(null);
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    final found = await completer.future;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (found == null) {
      _setError('Device not found');
      return;
    }
    await connectToDevice(found.id, found.type);
  }

  Future<void> disconnect() async {
    await _disposeService();
    if (_deviceId != null) {
      try {
        await _ble.disconnect(_deviceId!);
      } catch (_) {}
    }
    _deviceId = null;
    state = const LaunchMonitorState();
  }

  // ── Shot management (existing behaviour) ─────────────────────────────────

  void clearShots() {
    _draftSessionId = null;
    _draftCreatedAt = null;
    state = state.copyWith(shots: []);
  }

  /// Deletes shots at the given indices (into [state.shots]) and removes from DB.
  Future<void> deleteShots(List<int> indices) async {
    final updated = List<ShotData>.from(state.shots);
    final db = ref.read(appDatabaseProvider);
    final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
    for (final i in sorted) {
      if (i < 0 || i >= updated.length) continue;
      final shot = updated[i];
      if (shot.dbId != null) await db.deleteShotById(shot.dbId!);
      updated.removeAt(i);
    }
    state = state.copyWith(shots: updated);
  }

  /// Updates the tag IDs on a live shot by its list index and persists to DB.
  Future<void> updateShotTags(int index, List<int> tagIds) async {
    final updated = List<ShotData>.from(state.shots);
    if (index < 0 || index >= updated.length) return;
    final shot = updated[index];
    updated[index] = shot.copyWith(tagIds: tagIds);
    state = state.copyWith(shots: updated);
    if (shot.dbId != null) {
      await ref.read(appDatabaseProvider).updateShotTagIds(shot.dbId!, tagIds);
    }
  }

  /// Synthesises a shot from the active club's seed pool with light jitter,
  /// runs it through the same persist + state-update path as a real BLE shot.
  Future<void> simulateShot() async {
    final club = ref.read(activeClubProvider);
    final base = _pickSimSource(club);
    final jittered = _jitterShot(base, clubId: club?.id);
    final dbReady = await _persistShot(jittered);
    state = state.copyWith(shots: [dbReady, ...state.shots]);
  }

  // ── Internal: bridging service streams to ShotData ───────────────────────

  Future<void> _onBallMetrics(sg.BallMetrics ball) async {
    final club = ref.read(activeClubProvider);
    final shot = _ballToShotData(ball, club?.id);
    final dbReady = await _persistShot(shot);

    _pendingShotInList = dbReady;
    state = state.copyWith(shots: [dbReady, ...state.shots]);

    // If club metrics don't arrive within 1.5s, drop the pending pointer so
    // a stale ball metrics packet doesn't get patched by a much later club
    // packet (defensive — the device usually replies in <100ms).
    _pendingShotTimer?.cancel();
    _pendingShotTimer =
        Timer(const Duration(milliseconds: 1500), () => _pendingShotInList = null);
  }

  Future<void> _onClubMetrics(sg.ClubMetrics club) async {
    final pending = _pendingShotInList;
    if (pending == null) return;

    final enriched = pending.copyWith().mergeClubMetrics(club);
    // Replace the head of the list with the enriched copy.
    final shots = List<ShotData>.from(state.shots);
    if (shots.isNotEmpty && identical(shots.first, pending)) {
      shots[0] = enriched;
    } else {
      // Fall back to dbId match if list reference changed.
      final idx = shots.indexWhere((s) => s.dbId == pending.dbId);
      if (idx != -1) shots[idx] = enriched;
    }
    state = state.copyWith(shots: shots);

    if (enriched.dbId != null) {
      try {
        await ref.read(appDatabaseProvider).updateShot(enriched);
      } catch (_) {}
    }

    _pendingShotInList = null;
    _pendingShotTimer?.cancel();
  }

  ShotData _ballToShotData(sg.BallMetrics b, String? clubId) {
    return ShotData(
      clubId: clubId,
      ballSpeed: b.ballSpeedMps * _mpsToMph,
      spinRate: b.totalSpinRpm.abs().toDouble(),
      spinAxis: b.spinAxis,
      launchDirection: b.horizontalAngle,
      launchAngle: b.verticalAngle,
      // Estimate club speed from a ~1.45 smash factor until club metrics land.
      clubSpeed: (b.ballSpeedMps * _mpsToMph) / 1.45,
    );
  }

  // ── Internal: persistence ────────────────────────────────────────────────

  Future<ShotData> _persistShot(ShotData shot) async {
    try {
      final db = ref.read(appDatabaseProvider);
      if (_draftSessionId == null) {
        _draftCreatedAt = DateTime.now();
        _draftSessionId = await db.saveDraftSession(_draftCreatedAt!);
      }
      return await db.insertShot(_draftSessionId!, shot);
    } catch (_) {
      return shot;
    }
  }

  // ── Internal: simulator helpers ──────────────────────────────────────────

  ShotData _pickSimSource(Club? club) {
    final pool = switch (club?.id) {
      '7i' => sevenIronSeedShots,
      'dr' || null => driverSeedShots,
      _ => driverSeedShots,
    };
    return pool[_simRand.nextInt(pool.length)];
  }

  ShotData _jitterShot(ShotData s, {String? clubId}) {
    double j(double v, double pct) =>
        v + v * pct * (_simRand.nextDouble() * 2 - 1);
    double? jn(double? v, double pct) => v == null ? null : j(v, pct);

    return ShotData(
      clubId: clubId,
      ballSpeed: j(s.ballSpeed, 0.015),
      spinRate: j(s.spinRate, 0.04),
      spinAxis: s.spinAxis + (_simRand.nextDouble() * 1.0 - 0.5),
      launchDirection:
          s.launchDirection + (_simRand.nextDouble() * 0.6 - 0.3),
      launchAngle: j(s.launchAngle, 0.03),
      clubSpeed: j(s.clubSpeed, 0.015),
      apex: jn(s.apex, 0.04),
      run: jn(s.run, 0.08),
      swingPath: s.swingPath == null
          ? null
          : s.swingPath! + (_simRand.nextDouble() * 0.6 - 0.3),
      faceAngle: s.faceAngle == null
          ? null
          : s.faceAngle! + (_simRand.nextDouble() * 0.6 - 0.3),
      angleOfAttack: s.angleOfAttack == null
          ? null
          : s.angleOfAttack! + (_simRand.nextDouble() * 0.4 - 0.2),
      dynamicLoft: jn(s.dynamicLoft, 0.02),
      horizontalImpact:
          s.horizontalImpact == null ? null : j(s.horizontalImpact!, 0.15),
      verticalImpact:
          s.verticalImpact == null ? null : j(s.verticalImpact!, 0.15),
    );
  }

  final _simRand = math.Random();

  // ── Internal: lifecycle ──────────────────────────────────────────────────

  void _setError(String message) {
    state = LaunchMonitorState(
      status: LaunchMonitorStatus.disconnected,
      error: message,
    );
  }

  Future<void> _disposeService() async {
    _pendingShotTimer?.cancel();
    _pendingShotTimer = null;
    _pendingShotInList = null;
    await _ballSub?.cancel();
    await _clubSub?.cancel();
    await _connectionSubscription?.cancel();
    _ballSub = null;
    _clubSub = null;
    _connectionSubscription = null;
    final svc = _service;
    _service = null;
    if (svc != null) {
      try {
        await svc.dispose();
      } catch (_) {}
    }
  }

  void _cleanup() {
    _scanSubscription?.cancel();
    _disposeService();
    if (_deviceId != null) _ble.disconnect(_deviceId!);
    _deviceId = null;
  }
}

/// Helper to merge a [ClubMetrics] into a [ShotData] without losing existing
/// fields. Returns a new instance.
extension on ShotData {
  ShotData mergeClubMetrics(sg.ClubMetrics c) {
    return ShotData(
      dbId: dbId,
      clubId: clubId,
      ballSpeed: ballSpeed,
      spinRate: spinRate,
      spinAxis: spinAxis,
      launchDirection: launchDirection,
      launchAngle: launchAngle,
      clubSpeed: c.isClubSpeedValid ? c.clubSpeed * _mpsToMph : clubSpeed,
      apex: apex,
      run: run,
      swingPath: c.isPathAngleValid ? c.pathAngle : swingPath,
      faceAngle: c.isFaceAngleValid ? c.faceAngle : faceAngle,
      angleOfAttack: c.isAttackAngleValid ? c.attackAngle : angleOfAttack,
      dynamicLoft: c.isDynamicLoftValid ? c.dynamicLoftAngle : dynamicLoft,
      horizontalImpact: c.isImpactHorizontalValid
          ? c.impactHorizontal
          : horizontalImpact,
      verticalImpact:
          c.isImpactVerticalValid ? c.impactVertical : verticalImpact,
      tagIds: tagIds,
    );
  }
}
