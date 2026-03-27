import 'package:flutter/material.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';

class StatusIndicator extends StatelessWidget {
  final LaunchMonitorStatus status;

  const StatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      LaunchMonitorStatus.connected => (Colors.green, 'Connected'),
      LaunchMonitorStatus.connecting => (Colors.orange, 'Connecting'),
      LaunchMonitorStatus.scanning => (Colors.blue, 'Scanning'),
      LaunchMonitorStatus.disconnected => (Colors.red, 'Disconnected'),
    };

    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
