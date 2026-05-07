/// Command builders for the Square Golf BLE protocol.
///
/// Each builder returns the raw bytes to write to the command characteristic.
/// Sequence numbers wrap at 0xFF — the caller is responsible for incrementing.
///
/// Ported from `squaregolf-connector` (Go) — see `internal/core/commands.go`.
library;

import 'dart:typed_data';

import 'constants.dart';

String _hex2(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0');

Uint8List _decodeHex(String hex) {
  final cleaned = hex.replaceAll(' ', '');
  if (cleaned.length.isOdd) {
    throw ArgumentError('hex string must have even length: $cleaned');
  }
  final out = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Heartbeat — must be sent every ~5s to keep the connection alive.
Uint8List heartbeatCommand(int sequence) =>
    _decodeHex('1183${_hex2(sequence)}0000000000');

/// Configures ball-detection and spin-measurement modes.
Uint8List detectBallCommand(
  int sequence,
  DetectBallMode mode,
  SpinMode spinMode,
) {
  // Original Go format: "1181%02x0%d1%d00000000"
  // (mode is a single hex digit and so is spinMode).
  return _decodeHex(
    '1181${_hex2(sequence)}0${mode.index}1${spinMode.index}00000000',
  );
}

/// Selects a club for the Home device.
Uint8List clubCommand(int sequence, ClubCode club, Handedness handedness) =>
    _decodeHex(
      '1182${_hex2(sequence)}${club.regularCode}0${handedness.index}000000',
    );

/// Selects a club for the Omni device. The Omni encodes `clubSel - 4`.
Uint8List omniClubCommand(int sequence, ClubCode club, Handedness handedness) {
  if (club.regularCode.length != 4) {
    throw ArgumentError('regularCode must be 4 hex chars: ${club.regularCode}');
  }
  final clubNumber = int.parse(club.regularCode.substring(0, 2), radix: 16);
  final clubSel = int.parse(club.regularCode.substring(2, 4), radix: 16);
  final omniSel = (clubSel - 4) < 0 ? 0 : clubSel - 4;
  return _decodeHex(
    '1182${_hex2(sequence)}${_hex2(clubNumber)}${_hex2(omniSel)}'
    '${_hex2(handedness.index)}000000',
  );
}

/// Selects a club in swing-stick mode.
Uint8List swingStickCommand(
  int sequence,
  ClubCode club,
  Handedness handedness,
) =>
    _decodeHex(
      '1182${_hex2(sequence)}${club.swingStickCode}0${handedness.index}0000',
    );

/// Alignment command (0x85). [confirm]: 0 = cancel, 1 = save.
/// [targetAngle] is in degrees (encoded × 100 as int32-LE).
Uint8List alignmentCommand(int sequence, int confirm, double targetAngle) {
  final angleInt = (targetAngle * 100).truncate();
  return _decodeHex(
    '1185${_hex2(sequence)}${_hex2(confirm)}'
    '${_hex2(angleInt)}'
    '${_hex2(angleInt >> 8)}'
    '${_hex2(angleInt >> 16)}'
    '${_hex2(angleInt >> 24)}',
  );
}

Uint8List startAlignmentCommand(int sequence) =>
    alignmentCommand(sequence, 0, 0.0);

Uint8List stopAlignmentCommand(int sequence, double targetAngle) =>
    alignmentCommand(sequence, 1, targetAngle);

Uint8List cancelAlignmentCommand(int sequence, double targetAngle) =>
    alignmentCommand(sequence, 0, targetAngle);

/// Requests club metrics for the most recent shot.
Uint8List requestClubMetricsCommand(int sequence) =>
    _decodeHex('1187${_hex2(sequence)}000000000000');

/// Requests firmware/OS version (command 0x92).
Uint8List getOsVersionCommand(int sequence) =>
    _decodeHex('1192${_hex2(sequence)}0000000000');

/// Queries capacitor charge status (command 0x86).
Uint8List getChargeCommand(int sequence) =>
    _decodeHex('1186${_hex2(sequence)}0000000000');

// ── Omni-specific commands ───────────────────────────────────────────────────

enum OmniSpeedUnit { metersPerSecond, mph }

extension OmniSpeedUnitByte on OmniSpeedUnit {
  int get byte => this == OmniSpeedUnit.metersPerSecond ? 0 : 1;
}

enum OmniDistanceUnit {
  /// 0 = meters
  meters,

  /// 1 = yards (carry) / feet (run)
  yardsFeet,

  /// 2 = yards (carry) / yards (run)
  yardsYards,
}

extension OmniDistanceUnitByte on OmniDistanceUnit {
  int get byte => index;
}

/// Configures the Omni's display units (command 0x88).
Uint8List omniSetUnitsCommand(
  int sequence,
  OmniSpeedUnit speedUnit,
  OmniDistanceUnit distanceUnit,
) {
  final distMarker = distanceUnit == OmniDistanceUnit.meters ? 0 : 1;
  final distSub = distanceUnit == OmniDistanceUnit.meters ? 0 : distanceUnit.byte;
  return _decodeHex(
    '1188${_hex2(sequence)}${_hex2(speedUnit.byte)}'
    '${_hex2(distMarker)}${_hex2(distSub)}0000',
  );
}

/// Configures the Omni's green speed (command 0x89).
/// [greenSpeed] index: 0=8, 1=9, 2=10, 3=11, 4=12, 5=13.
Uint8List omniSetGreenSpeedCommand(int sequence, int greenSpeed) =>
    _decodeHex('1189${_hex2(sequence)}${_hex2(greenSpeed)}00000000');

/// Configures carry-distance adjustment (command 0x8a).
/// [adjustment] is a signed int (e.g. -5..+5). Encoded as `adjustment + 100`.
Uint8List omniSetCarryDistanceAdjustmentCommand(
  int sequence,
  int adjustment,
) {
  final encoded = (adjustment + 100) & 0xFF;
  return _decodeHex(
    '118a${_hex2(sequence)}${_hex2(encoded)}00000000',
  );
}

/// Sends handedness to the Omni using clubSel = 0x63 (command 0x82).
Uint8List omniSetHandedCommand(int sequence, Handedness handedness) =>
    _decodeHex(
      '1182${_hex2(sequence)}0063${_hex2(handedness.index)}000000',
    );
