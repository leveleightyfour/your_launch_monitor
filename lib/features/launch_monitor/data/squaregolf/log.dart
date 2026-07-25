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

/// Master switch. Debug builds log by default; release builds do not.
///
/// Mutable rather than const so a release build can be asked to talk. Reading
/// the undecoded tail of an Omni ball frame means watching frames arrive
/// during a real range session, and a real range session is a TestFlight
/// build, where `kDebugMode` is false and nothing would print at all.
bool lmLoggingEnabled = kDebugMode;

/// Set to `true` to also log every heartbeat tick. Off by default because
/// they're sent every 5 s and clutter the console.
const bool kLmLogHeartbeats = false;

void lmLog(String tag, String message) {
  if (!lmLoggingEnabled) return;
  // debugPrint so lines reach the `flutter run` console — dart:developer.log
  // is only visible in DevTools' Logging view on some toolchains.
  debugPrint('[lm.$tag] $message');
  developer.log(message, name: 'lm.$tag');
}

void lmWarn(String tag, String message) {
  if (!lmLoggingEnabled) return;
  debugPrint('[lm.$tag] ⚠ $message');
  developer.log(message, name: 'lm.$tag', level: 900);
}

/// Render the undecoded int16 tail of a ball frame for the log line.
///
/// Empty string when there is no tail, so a Home-length 17-byte frame logs
/// exactly as it always did. Otherwise each value is shown raw and at the ×100
/// scale the rest of the frame uses, in metres and yards — the two units the
/// device itself can be set to display, so the numbers can be read straight
/// off the console and matched against the monitor.
String lmTailSummary(List<int> tail) {
  if (tail.isEmpty) return '';
  final parts = [
    for (final v in tail)
      '$v(${(v / 100).toStringAsFixed(2)}m/'
          '${(v / 100 * 1.09361).toStringAsFixed(1)}y)',
  ];
  return ' TAIL[${parts.join(' ')}]';
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
