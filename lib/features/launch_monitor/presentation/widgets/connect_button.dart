import 'package:flutter/material.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';

class ConnectButton extends StatelessWidget {
  final LaunchMonitorStatus status;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const ConnectButton({
    super.key,
    required this.status,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading =
        status == LaunchMonitorStatus.scanning ||
        status == LaunchMonitorStatus.connecting;

    return FloatingActionButton.extended(
      onPressed: isLoading
          ? null
          : status == LaunchMonitorStatus.connected
          ? onDisconnect
          : onConnect,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              status == LaunchMonitorStatus.connected
                  ? Icons.bluetooth_disabled
                  : Icons.bluetooth_searching,
            ),
      label: Text(
        isLoading
            ? status == LaunchMonitorStatus.scanning
                  ? 'Scanning...'
                  : 'Connecting...'
            : status == LaunchMonitorStatus.connected
            ? 'Disconnect'
            : 'Connect',
      ),
    );
  }
}
