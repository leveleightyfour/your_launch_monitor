/// Tiny logging helper used by the BT layer + the Square Golf protocol code.
///
/// Output goes through `dart:developer.log` so it shows up in DevTools, Xcode,
/// and `flutter logs` with proper stream names. Everything is gated on
/// [kDebugMode] so release builds emit nothing.
///
/// Convention — every log line carries a short tag:
///   [lm.scan]    BLE scan results
///   [lm.conn]    BLE connect / discover lifecycle
///   [lm.notify]  raw notification frames (hex + parsed summary)
///   [lm.cmd]     commands written to the device
///   [lm.hb]      heartbeat ticks
///   [lm.init]    Omni init burst
///   [lm.bridge]  ball/club → ShotData conversion in the notifier
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Master switch — debug builds only.
const bool kLmLoggingEnabled = kDebugMode;

/// Set to `true` to also log every heartbeat tick. Off by default because
/// they're sent every 5 s and clutter the console.
const bool kLmLogHeartbeats = false;

void lmLog(String tag, String message) {
  if (!kLmLoggingEnabled) return;
  developer.log(message, name: 'lm.$tag');
}

void lmWarn(String tag, String message) {
  if (!kLmLoggingEnabled) return;
  developer.log(message, name: 'lm.$tag', level: 900);
}

/// Encode raw bytes as a space-separated lower-case hex string.
String lmHex(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    if (i > 0) buf.write(' ');
    buf.write((bytes[i] & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

/// Encode a list of pre-split hex byte strings the same way (used by the
/// protocol code which already splits incoming frames).
String lmHexList(Iterable<String> bytesHex) =>
    bytesHex.map((b) => b.toLowerCase()).join(' ');
