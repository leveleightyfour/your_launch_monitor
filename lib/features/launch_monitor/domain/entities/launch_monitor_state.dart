import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

enum LaunchMonitorStatus { disconnected, scanning, connecting, connected }

class LaunchMonitorState {
  final LaunchMonitorStatus status;
  final List<ShotData> shots;
  final String? error;

  // ── Connected-device info (populated from the BLE service) ────────────────
  /// Whether the connected device is a Square Golf Omni (vs Home).
  final bool isOmni;

  /// Battery percentage reported by the device, or null if unknown.
  final int? batteryPercent;

  /// Device serial number, or null if it couldn't be read.
  final String? serialNumber;

  /// Primary firmware version (`lm`), or null if it couldn't be read.
  final String? firmwareVersion;

  /// Whether the Omni capacitor has finished charging (ready to read shots).
  final bool capacitorReady;

  /// Whether ball detection is currently armed.
  final bool detecting;

  const LaunchMonitorState({
    this.status = LaunchMonitorStatus.disconnected,
    this.shots = const [],
    this.error,
    this.isOmni = false,
    this.batteryPercent,
    this.serialNumber,
    this.firmwareVersion,
    this.capacitorReady = false,
    this.detecting = false,
  });

  ShotData? get lastShot => shots.isEmpty ? null : shots.first;

  LaunchMonitorState copyWith({
    LaunchMonitorStatus? status,
    List<ShotData>? shots,
    String? error,
    bool? isOmni,
    int? batteryPercent,
    String? serialNumber,
    String? firmwareVersion,
    bool? capacitorReady,
    bool? detecting,
  }) {
    return LaunchMonitorState(
      status: status ?? this.status,
      shots: shots ?? this.shots,
      error: error ?? this.error,
      isOmni: isOmni ?? this.isOmni,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      serialNumber: serialNumber ?? this.serialNumber,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      capacitorReady: capacitorReady ?? this.capacitorReady,
      detecting: detecting ?? this.detecting,
    );
  }
}
