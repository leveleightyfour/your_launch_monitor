import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'ble_adapter.dart';
import 'flutter_blue_plus_adapter.dart';
import 'win_ble_adapter.dart';

/// When set, [createBleAdapter] returns this instead of the platform adapter.
/// The launch-monitor notifier builds its adapter in a field initialiser, so
/// this is the seam tests use to drive scan and connection behaviour. Always
/// clear it again in a `tearDown`.
@visibleForTesting
BleAdapter Function()? debugBleAdapterFactory;

/// Returns the platform-appropriate [BleAdapter].
BleAdapter createBleAdapter() {
  final override = debugBleAdapterFactory;
  if (override != null) return override();
  if (Platform.isWindows) return WinBleAdapter();
  return FlutterBluePlusAdapter();
}
