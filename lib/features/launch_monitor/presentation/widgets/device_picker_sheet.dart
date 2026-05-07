import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/constants.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Modal bottom sheet that scans for nearby Square Golf devices and lets the
/// user pick one to connect to. Shows a Home/Omni badge per device based on
/// advertised manufacturer data.
class DevicePickerSheet extends ConsumerStatefulWidget {
  const DevicePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const DevicePickerSheet(),
    );
  }

  @override
  ConsumerState<DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends ConsumerState<DevicePickerSheet> {
  StreamSubscription<List<DiscoveredSquareGolfDevice>>? _sub;
  List<DiscoveredSquareGolfDevice> _devices = const [];
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    // Defer until after the current build — scanForDevices mutates Riverpod
    // state synchronously, which isn't permitted during a widget's mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startScan();
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _devices = const [];
    });
    final notifier = ref.read(launchMonitorProvider.notifier);
    // Make sure any previous scan is fully torn down before we start a new
    // one — flutter_blue_plus throws "scan already running" otherwise.
    await notifier.stopScan();
    if (!mounted) return;
    _sub = notifier
        .scanForDevices(timeout: const Duration(seconds: 30))
        .listen(
      (devices) => setState(() => _devices = devices),
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (Object _) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    ref.read(launchMonitorProvider.notifier).stopScan();
    super.dispose();
  }

  Future<void> _selectDevice(DiscoveredSquareGolfDevice device) async {
    await _sub?.cancel();
    final notifier = ref.read(launchMonitorProvider.notifier);
    if (!mounted) return;
    Navigator.of(context).pop();
    await notifier.connectToDevice(device.id, device.type);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  'Connect device',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
                const Spacer(),
                if (_scanning)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.accent,
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.refresh, size: 18, color: context.accent),
                    onPressed: _startScan,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _scanning
                  ? 'Scanning for nearby Square Golf devices…'
                  : _devices.isEmpty
                      ? 'No devices found.'
                      : 'Tap a device to connect.',
              style: AppTextStyles.sans(size: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: _devices.isEmpty
                  ? const SizedBox(
                      height: 80,
                      child: Center(child: SizedBox.shrink()),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _DeviceTile(device: _devices[i], onTap: _selectDevice),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DiscoveredSquareGolfDevice device;
  final ValueChanged<DiscoveredSquareGolfDevice> onTap;

  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(device),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          children: [
            Icon(Icons.bluetooth, size: 18, color: context.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    device.name.isEmpty ? 'Unknown' : device.name,
                    style: AppTextStyles.sans(size: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    device.id,
                    style: AppTextStyles.sans(
                      size: 10,
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _DeviceTypeBadge(type: device.type),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textDimmed),
          ],
        ),
      ),
    );
  }
}

class _DeviceTypeBadge extends StatelessWidget {
  final SquareGolfDeviceType type;
  const _DeviceTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      SquareGolfDeviceType.omni => ('OMNI', context.accent),
      SquareGolfDeviceType.home => ('HOME', AppColors.textMuted),
      SquareGolfDeviceType.unknown => ('?', AppColors.textDimmed),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: AppTextStyles.sans(
          size: 9,
          weight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
