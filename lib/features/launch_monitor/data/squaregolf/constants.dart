/// Protocol-level constants for the Square Golf Home / Omni launch monitors.
///
/// Ported from `squaregolf-connector` (Go) — see `internal/core/constants.go`.
library;

// ── BLE characteristic UUIDs ─────────────────────────────────────────────────

const String commandCharUuid = '86602101-6b7e-439a-bdd1-489a3213e9bb';
const String notificationCharUuid = '86602102-6b7e-439a-bdd1-489a3213e9bb';
const String batteryLevelCharUuid = '00002a19-0000-1000-8000-00805f9b34fb';
const String firmwareVersionCharUuid = '86602003-6b7e-439a-bdd1-489a3213e9bb';
const String serialNumberCharUuid = '86602001-6b7e-439a-bdd1-489a3213e9bb';

/// Devices advertise their name with this prefix.
const String bluetoothDevicePrefix = 'SquareGolf';

/// Manufacturer-data substring identifying an Omni device (ASCII "0300A").
const String omniManufacturerDataHex = '3033303041';

// ── Device type ──────────────────────────────────────────────────────────────

enum SquareGolfDeviceType { unknown, home, omni }

/// Detect device type from advertised manufacturer data (hex string).
SquareGolfDeviceType detectDeviceType(String mfgDataHex) {
  if (mfgDataHex.isNotEmpty &&
      mfgDataHex.toUpperCase().contains(omniManufacturerDataHex.toUpperCase())) {
    return SquareGolfDeviceType.omni;
  }
  return SquareGolfDeviceType.home;
}

// ── Connection / monitor status ──────────────────────────────────────────────

enum LmConnectionStatus { disconnected, scanning, connecting, connected, error }

/// Status reported by `11 03` packets.
enum LaunchMonitorStatus { none, idle, init, detect, ready, shot, done }

// ── Player / shot configuration ──────────────────────────────────────────────

enum Handedness { rightHanded, leftHanded }

extension HandednessByte on Handedness {
  int get byte => this == Handedness.rightHanded ? 0 : 1;
}

enum DetectBallMode {
  /// 0 = deactivate ball detection.
  deactivate,

  /// 1 = activate ball detection (standard mode).
  activate,

  /// 2 = activate in alignment mode.
  activateAlignmentMode,
}

enum SpinMode { standard, advanced }

enum ShotType { full, putt }

// ── Club codes ───────────────────────────────────────────────────────────────

class ClubCode {
  final String regularCode;
  final String swingStickCode;

  const ClubCode({required this.regularCode, required this.swingStickCode});
}

class ClubCodes {
  ClubCodes._();

  // Putter
  static const putter = ClubCode(regularCode: '0107', swingStickCode: '0103');

  // Drivers and woods
  static const driver = ClubCode(regularCode: '0204', swingStickCode: '0202');
  static const wood3 = ClubCode(regularCode: '0305', swingStickCode: '0301');
  static const wood5 = ClubCode(regularCode: '0505', swingStickCode: '0501');
  static const wood7 = ClubCode(regularCode: '0705', swingStickCode: '0701');

  // Irons
  static const iron4 = ClubCode(regularCode: '0406', swingStickCode: '0400');
  static const iron5 = ClubCode(regularCode: '0506', swingStickCode: '0500');
  static const iron6 = ClubCode(regularCode: '0606', swingStickCode: '0600');
  static const iron7 = ClubCode(regularCode: '0706', swingStickCode: '0700');
  static const iron8 = ClubCode(regularCode: '0806', swingStickCode: '0900');
  static const iron9 = ClubCode(regularCode: '0906', swingStickCode: '0900');

  // Wedges
  static const pitchingWedge =
      ClubCode(regularCode: '0a06', swingStickCode: '0a00');
  static const approachWedge =
      ClubCode(regularCode: '0b06', swingStickCode: '0b00');
  static const sandWedge =
      ClubCode(regularCode: '0c06', swingStickCode: '0c00');

  /// Special club code that activates alignment mode.
  static const alignmentStick =
      ClubCode(regularCode: '0008', swingStickCode: '0008');
}
