/// Remembers the last device the user successfully connected to so the app
/// can attempt a silent reconnect on next launch.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/constants.dart';

class LastConnectedDevice {
  final String id;
  final String name;
  final SquareGolfDeviceType type;

  const LastConnectedDevice({
    required this.id,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
      };

  factory LastConnectedDevice.fromJson(Map<String, dynamic> j) =>
      LastConnectedDevice(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        type: SquareGolfDeviceType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => SquareGolfDeviceType.home,
        ),
      );
}

final lastDeviceProvider =
    NotifierProvider<LastDeviceNotifier, LastConnectedDevice?>(
  LastDeviceNotifier.new,
);

class LastDeviceNotifier extends Notifier<LastConnectedDevice?> {
  static const _fileName = 'last_device.json';

  /// Call from `main()` before `runApp` so the first `build()` returns the
  /// persisted device synchronously — same pattern as
  /// [AccentColorNotifier.preload].
  static LastConnectedDevice? _preloaded;

  static Future<void> preload() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _preloaded = LastConnectedDevice.fromJson(json);
      }
    } catch (_) {}
  }

  @override
  LastConnectedDevice? build() => _preloaded;

  Future<void> save(LastConnectedDevice device) async {
    state = device;
    _preloaded = device;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode(device.toJson()));
    } catch (_) {}
  }

  Future<void> forget() async {
    state = null;
    _preloaded = null;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
