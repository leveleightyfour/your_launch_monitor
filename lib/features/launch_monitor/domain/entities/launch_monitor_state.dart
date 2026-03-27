import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

enum LaunchMonitorStatus { disconnected, scanning, connecting, connected }

class LaunchMonitorState {
  final LaunchMonitorStatus status;
  final List<ShotData> shots;
  final String? error;

  const LaunchMonitorState({
    this.status = LaunchMonitorStatus.disconnected,
    this.shots = const [],
    this.error,
  });

  ShotData? get lastShot => shots.isEmpty ? null : shots.first;

  LaunchMonitorState copyWith({
    LaunchMonitorStatus? status,
    List<ShotData>? shots,
    String? error,
  }) {
    return LaunchMonitorState(
      status: status ?? this.status,
      shots: shots ?? this.shots,
      error: error ?? this.error,
    );
  }
}
