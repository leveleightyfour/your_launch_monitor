import 'dart:io' show Platform;

import 'ble_adapter.dart';
import 'flutter_blue_plus_adapter.dart';
import 'win_ble_adapter.dart';

/// Returns the platform-appropriate [BleAdapter].
BleAdapter createBleAdapter() {
  if (Platform.isWindows) return WinBleAdapter();
  return FlutterBluePlusAdapter();
}
