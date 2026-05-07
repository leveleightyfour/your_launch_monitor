/// Parsers for Square Golf BLE notification packets.
///
/// Notification frames arrive on the notification characteristic as raw bytes;
/// this module turns them into typed [SensorData], [BallMetrics],
/// [ClubMetrics], and [AlignmentData] records.
///
/// Ported from `squaregolf-connector` (Go) — see
/// `internal/core/parse_notifications.go`. The Go reference splits the frame
/// into a `[]string` of two-char hex bytes; we accept either raw bytes (for
/// the BLE service) or that pre-split form (for tests / debugging).
library;

import 'dart:math' as math;
import 'dart:typed_data';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Encode raw bytes as a list of two-character lower-case hex strings.
List<String> bytesToHexList(Uint8List bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];

/// Result of parsing a 2-byte little-endian int16 metric.
class _Int16Parse {
  final int value;
  final bool valid;

  /// `false` if the underlying hex couldn't be decoded.
  final bool ok;

  const _Int16Parse(this.value, this.valid, this.ok);

  static const _failed = _Int16Parse(0, false, false);
}

/// Mirrors Go's `parseInt16Metric` — sentinel `-32768` → value 0, valid=false.
_Int16Parse _parseInt16(String lo, String hi) {
  final loByte = int.tryParse(lo, radix: 16);
  final hiByte = int.tryParse(hi, radix: 16);
  if (loByte == null || hiByte == null) return _Int16Parse._failed;
  if (loByte < 0 || loByte > 0xFF || hiByte < 0 || hiByte > 0xFF) {
    return _Int16Parse._failed;
  }
  final raw = loByte | (hiByte << 8);
  // sign-extend 16-bit two's complement
  final value = raw < 0x8000 ? raw : raw - 0x10000;
  if (value == -32768) return const _Int16Parse(0, false, true);
  return _Int16Parse(value, true, true);
}

class _ScaledParse {
  final double value;
  final bool valid;
  final bool ok;

  const _ScaledParse(this.value, this.valid, this.ok);
}

_ScaledParse _parseScaledInt16(String lo, String hi, double scale) {
  final r = _parseInt16(lo, hi);
  if (!r.ok) return const _ScaledParse(0, false, false);
  return _ScaledParse(r.value / scale, r.valid, true);
}

// ── Sensor data (format 11 01) ───────────────────────────────────────────────

class SensorData {
  final List<String> rawData;
  final bool ballReady;
  final bool ballDetected;
  final int positionX;
  final int positionY;
  final int positionZ;

  const SensorData({
    required this.rawData,
    required this.ballReady,
    required this.ballDetected,
    required this.positionX,
    required this.positionY,
    required this.positionZ,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorData &&
          _listEq(rawData, other.rawData) &&
          ballReady == other.ballReady &&
          ballDetected == other.ballDetected &&
          positionX == other.positionX &&
          positionY == other.positionY &&
          positionZ == other.positionZ;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(rawData),
        ballReady,
        ballDetected,
        positionX,
        positionY,
        positionZ,
      );

  @override
  String toString() => 'SensorData(ready: $ballReady, detected: $ballDetected, '
      'pos: ($positionX, $positionY, $positionZ))';
}

class ParseException implements Exception {
  final String message;
  ParseException(this.message);
  @override
  String toString() => 'ParseException: $message';
}

int _parseInt32LE(String b0, String b1, String b2, String b3) {
  final v0 = int.tryParse(b0, radix: 16);
  final v1 = int.tryParse(b1, radix: 16);
  final v2 = int.tryParse(b2, radix: 16);
  final v3 = int.tryParse(b3, radix: 16);
  if (v0 == null || v1 == null || v2 == null || v3 == null) return 0;
  final raw = v0 | (v1 << 8) | (v2 << 16) | (v3 << 24);
  // sign-extend 32-bit
  return raw < 0x80000000 ? raw : raw - 0x100000000;
}

SensorData parseSensorData(List<String> bytesList) {
  if (bytesList.length < 17) {
    throw ParseException('insufficient data for parsing sensor data');
  }
  return SensorData(
    rawData: List.unmodifiable(bytesList),
    ballReady: bytesList[3] == '01' || bytesList[3] == '02',
    ballDetected: bytesList[4] == '01',
    positionX: _parseInt32LE(
        bytesList[5], bytesList[6], bytesList[7], bytesList[8]),
    positionY: _parseInt32LE(
        bytesList[9], bytesList[10], bytesList[11], bytesList[12]),
    positionZ: _parseInt32LE(
        bytesList[13], bytesList[14], bytesList[15], bytesList[16]),
  );
}

// ── Ball metrics (format 11 02) ──────────────────────────────────────────────

class BallMetrics {
  final List<String> rawData;
  final double ballSpeedMps;
  final double verticalAngle;
  final double horizontalAngle;
  final int totalSpinRpm;
  final double spinAxis;
  final int backspinRpm;
  final int sidespinRpm;
  final bool isBallSpeedValid;
  final bool isTotalSpinValid;
  final bool isSpinAxisValid;
  final bool isBackspinValid;
  final bool isSidespinValid;

  /// Raw validity bitmask byte (Omni only). Empty for Home devices.
  final String validityBitmask;

  const BallMetrics({
    required this.rawData,
    required this.ballSpeedMps,
    required this.verticalAngle,
    required this.horizontalAngle,
    required this.totalSpinRpm,
    required this.spinAxis,
    required this.backspinRpm,
    required this.sidespinRpm,
    required this.isBallSpeedValid,
    required this.isTotalSpinValid,
    required this.isSpinAxisValid,
    required this.isBackspinValid,
    required this.isSidespinValid,
    required this.validityBitmask,
  });

  BallMetrics copyWith({
    bool? isBallSpeedValid,
    bool? isTotalSpinValid,
    bool? isSpinAxisValid,
    bool? isBackspinValid,
    bool? isSidespinValid,
  }) =>
      BallMetrics(
        rawData: rawData,
        ballSpeedMps: ballSpeedMps,
        verticalAngle: verticalAngle,
        horizontalAngle: horizontalAngle,
        totalSpinRpm: totalSpinRpm,
        spinAxis: spinAxis,
        backspinRpm: backspinRpm,
        sidespinRpm: sidespinRpm,
        isBallSpeedValid: isBallSpeedValid ?? this.isBallSpeedValid,
        isTotalSpinValid: isTotalSpinValid ?? this.isTotalSpinValid,
        isSpinAxisValid: isSpinAxisValid ?? this.isSpinAxisValid,
        isBackspinValid: isBackspinValid ?? this.isBackspinValid,
        isSidespinValid: isSidespinValid ?? this.isSidespinValid,
        validityBitmask: validityBitmask,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BallMetrics &&
          _listEq(rawData, other.rawData) &&
          ballSpeedMps == other.ballSpeedMps &&
          verticalAngle == other.verticalAngle &&
          horizontalAngle == other.horizontalAngle &&
          totalSpinRpm == other.totalSpinRpm &&
          spinAxis == other.spinAxis &&
          backspinRpm == other.backspinRpm &&
          sidespinRpm == other.sidespinRpm &&
          isBallSpeedValid == other.isBallSpeedValid &&
          isTotalSpinValid == other.isTotalSpinValid &&
          isSpinAxisValid == other.isSpinAxisValid &&
          isBackspinValid == other.isBackspinValid &&
          isSidespinValid == other.isSidespinValid &&
          validityBitmask == other.validityBitmask;

  @override
  int get hashCode => Object.hashAll([
        Object.hashAll(rawData),
        ballSpeedMps,
        verticalAngle,
        horizontalAngle,
        totalSpinRpm,
        spinAxis,
        backspinRpm,
        sidespinRpm,
        isBallSpeedValid,
        isTotalSpinValid,
        isSpinAxisValid,
        isBackspinValid,
        isSidespinValid,
        validityBitmask,
      ]);

  @override
  String toString() => 'BallMetrics(speed: ${ballSpeedMps}mps, '
      'angle: $verticalAngle°/$horizontalAngle°, '
      'spin: $totalSpinRpm@$spinAxis° '
      '(back: $backspinRpm, side: $sidespinRpm))';
}

BallMetrics parseShotBallMetrics(List<String> bytesList) {
  if (bytesList.length < 17) {
    throw ParseException('insufficient data for parsing ball metrics');
  }

  final validityBitmask = bytesList[2];

  final speed = _parseScaledInt16(bytesList[3], bytesList[4], 100.0);
  final vAng = _parseScaledInt16(bytesList[5], bytesList[6], 100.0);
  final hAng = _parseScaledInt16(bytesList[7], bytesList[8], 100.0);
  final totSpin = _parseInt16(bytesList[9], bytesList[10]);
  final axis = _parseScaledInt16(bytesList[11], bytesList[12], 100.0);
  final backSpin = _parseInt16(bytesList[13], bytesList[14]);
  final sideSpin = _parseInt16(bytesList[15], bytesList[16]);

  // Defaults match the Go implementation: validity flags start true and are
  // only flipped to false when a parse fails or hits the int16 sentinel.
  var isBallSpeedValid = speed.ok ? speed.valid : false;
  var isTotalSpinValid = totSpin.ok ? totSpin.valid : false;
  var isSpinAxisValid = axis.ok ? axis.valid : false;
  var isBackspinValid = backSpin.ok ? backSpin.valid : false;
  var isSidespinValid = sideSpin.ok ? sideSpin.valid : false;

  // Vertical/horizontal angles: Go stores the value when ok, but does not
  // mutate any validity flag. We keep the value (or 0) similarly.
  final verticalAngle = vAng.ok ? vAng.value : 0.0;
  final horizontalAngle = hAng.ok ? hAng.value : 0.0;

  var totalSpinRpm = totSpin.ok ? totSpin.value : 0;
  var backspinRpm = backSpin.ok ? backSpin.value : 0;
  var sidespinRpm = sideSpin.ok ? sideSpin.value : 0;

  // Negative backspin orientation flip.
  if (backspinRpm < 0) totalSpinRpm = -totalSpinRpm;

  // Decompose total spin into back/side when one component is missing.
  if (isTotalSpinValid && isSpinAxisValid) {
    final spinAxisRad = axis.value * math.pi / 180.0;
    if (!isBackspinValid) {
      backspinRpm = (totalSpinRpm * math.cos(spinAxisRad)).truncate();
    }
    if (!isSidespinValid) {
      sidespinRpm = (totalSpinRpm * math.sin(spinAxisRad)).truncate();
    }
  }

  return BallMetrics(
    rawData: List.unmodifiable(bytesList),
    ballSpeedMps: speed.ok ? speed.value : 0.0,
    verticalAngle: verticalAngle,
    horizontalAngle: horizontalAngle,
    totalSpinRpm: totalSpinRpm,
    spinAxis: axis.ok ? axis.value : 0.0,
    backspinRpm: backspinRpm,
    sidespinRpm: sidespinRpm,
    isBallSpeedValid: isBallSpeedValid,
    isTotalSpinValid: isTotalSpinValid,
    isSpinAxisValid: isSpinAxisValid,
    isBackspinValid: isBackspinValid,
    isSidespinValid: isSidespinValid,
    validityBitmask: validityBitmask,
  );
}

/// Apply the Omni's per-field validity bitmask to ball metrics.
/// A field is valid only if both the existing flag and the bitmask bit are set.
BallMetrics applyOmniBallValidityBitmask(BallMetrics metrics) {
  if (metrics.validityBitmask.isEmpty) return metrics;
  final bm = int.tryParse(metrics.validityBitmask, radix: 16);
  if (bm == null) return metrics;
  return metrics.copyWith(
    isBallSpeedValid: metrics.isBallSpeedValid && (bm & 0x01) != 0,
    isTotalSpinValid: metrics.isTotalSpinValid && (bm & 0x02) != 0,
    isSpinAxisValid: metrics.isSpinAxisValid && (bm & 0x04) != 0,
    isBackspinValid: metrics.isBackspinValid && (bm & 0x10) != 0,
    isSidespinValid: metrics.isSidespinValid && (bm & 0x20) != 0,
  );
}

// ── Club metrics (format 11 07) ──────────────────────────────────────────────

class ClubMetrics {
  final List<String> rawData;
  final double pathAngle;
  final double faceAngle;
  final double attackAngle;
  final double dynamicLoftAngle;
  final double impactHorizontal;
  final double impactVertical;
  final double clubSpeed;
  final double smashFactor;
  final bool isPathAngleValid;
  final bool isFaceAngleValid;
  final bool isAttackAngleValid;
  final bool isDynamicLoftValid;
  final bool isImpactHorizontalValid;
  final bool isImpactVerticalValid;
  final bool isClubSpeedValid;
  final bool isSmashFactorValid;

  const ClubMetrics({
    required this.rawData,
    this.pathAngle = 0,
    this.faceAngle = 0,
    this.attackAngle = 0,
    this.dynamicLoftAngle = 0,
    this.impactHorizontal = 0,
    this.impactVertical = 0,
    this.clubSpeed = 0,
    this.smashFactor = 0,
    this.isPathAngleValid = false,
    this.isFaceAngleValid = false,
    this.isAttackAngleValid = false,
    this.isDynamicLoftValid = false,
    this.isImpactHorizontalValid = false,
    this.isImpactVerticalValid = false,
    this.isClubSpeedValid = false,
    this.isSmashFactorValid = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClubMetrics &&
          _listEq(rawData, other.rawData) &&
          pathAngle == other.pathAngle &&
          faceAngle == other.faceAngle &&
          attackAngle == other.attackAngle &&
          dynamicLoftAngle == other.dynamicLoftAngle &&
          impactHorizontal == other.impactHorizontal &&
          impactVertical == other.impactVertical &&
          clubSpeed == other.clubSpeed &&
          smashFactor == other.smashFactor &&
          isPathAngleValid == other.isPathAngleValid &&
          isFaceAngleValid == other.isFaceAngleValid &&
          isAttackAngleValid == other.isAttackAngleValid &&
          isDynamicLoftValid == other.isDynamicLoftValid &&
          isImpactHorizontalValid == other.isImpactHorizontalValid &&
          isImpactVerticalValid == other.isImpactVerticalValid &&
          isClubSpeedValid == other.isClubSpeedValid &&
          isSmashFactorValid == other.isSmashFactorValid;

  @override
  int get hashCode => Object.hashAll([
        Object.hashAll(rawData),
        pathAngle,
        faceAngle,
        attackAngle,
        dynamicLoftAngle,
        impactHorizontal,
        impactVertical,
        clubSpeed,
        smashFactor,
        isPathAngleValid,
        isFaceAngleValid,
        isAttackAngleValid,
        isDynamicLoftValid,
        isImpactHorizontalValid,
        isImpactVerticalValid,
        isClubSpeedValid,
        isSmashFactorValid,
      ]);

  @override
  String toString() =>
      'ClubMetrics(path: $pathAngle°, face: $faceAngle°, attack: $attackAngle°, '
      'loft: $dynamicLoftAngle°, impact: ($impactHorizontal, $impactVertical), '
      'speed: $clubSpeed, smash: $smashFactor)';
}

/// Parse Home-device club metrics (4 fields: path, face, attack, loft).
ClubMetrics parseShotClubMetrics(List<String> bytesList) {
  if (bytesList.length < 11) {
    throw ParseException('insufficient data for parsing club metrics');
  }
  final path = _parseScaledInt16(bytesList[3], bytesList[4], 100.0);
  final face = _parseScaledInt16(bytesList[5], bytesList[6], 100.0);
  final attack = _parseScaledInt16(bytesList[7], bytesList[8], 100.0);
  final loft = _parseScaledInt16(bytesList[9], bytesList[10], 100.0);

  return ClubMetrics(
    rawData: List.unmodifiable(bytesList),
    pathAngle: path.ok ? path.value : 0,
    faceAngle: face.ok ? face.value : 0,
    attackAngle: attack.ok ? attack.value : 0,
    dynamicLoftAngle: loft.ok ? loft.value : 0,
    isPathAngleValid: path.ok ? path.valid : false,
    isFaceAngleValid: face.ok ? face.valid : false,
    isAttackAngleValid: attack.ok ? attack.valid : false,
    isDynamicLoftValid: loft.ok ? loft.valid : false,
  );
}

/// Parse Omni-device club metrics (8 fields with validity bitmask byte).
ClubMetrics parseOmniShotClubMetrics(List<String> bytesList) {
  if (bytesList.length < 19) {
    throw ParseException(
      'insufficient data for parsing Omni club metrics '
      '(need 19, got ${bytesList.length})',
    );
  }

  final validity = int.tryParse(bytesList[2], radix: 16) ?? 0;

  ({double value, bool valid}) parse(int loIdx, int hiIdx, int bit) {
    final bitmaskValid = (validity & (1 << bit)) != 0;
    final r = _parseScaledInt16(bytesList[loIdx], bytesList[hiIdx], 100.0);
    if (!r.ok) return (value: 0, valid: false);
    return (value: r.value, valid: bitmaskValid && r.valid);
  }

  final p = parse(3, 4, 0);
  final f = parse(5, 6, 1);
  final a = parse(7, 8, 2);
  final l = parse(9, 10, 3);
  final ih = parse(11, 12, 4);
  final iv = parse(13, 14, 5);
  final cs = parse(15, 16, 6);
  final sf = parse(17, 18, 7);

  return ClubMetrics(
    rawData: List.unmodifiable(bytesList),
    pathAngle: p.value,
    faceAngle: f.value,
    attackAngle: a.value,
    dynamicLoftAngle: l.value,
    impactHorizontal: ih.value,
    impactVertical: iv.value,
    clubSpeed: cs.value,
    smashFactor: sf.value,
    isPathAngleValid: p.valid,
    isFaceAngleValid: f.valid,
    isAttackAngleValid: a.valid,
    isDynamicLoftValid: l.valid,
    isImpactHorizontalValid: ih.valid,
    isImpactVerticalValid: iv.valid,
    isClubSpeedValid: cs.valid,
    isSmashFactorValid: sf.valid,
  );
}

// ── Alignment data (format 11 04) ────────────────────────────────────────────

class AlignmentData {
  final List<String> rawData;

  /// Degrees left (negative) or right (positive) of target.
  final double aimAngle;

  /// Whether the device is pointing at the target (within ±2°).
  final bool isAligned;

  const AlignmentData({
    required this.rawData,
    required this.aimAngle,
    required this.isAligned,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlignmentData &&
          _listEq(rawData, other.rawData) &&
          aimAngle == other.aimAngle &&
          isAligned == other.isAligned;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(rawData), aimAngle, isAligned);

  @override
  String toString() => 'AlignmentData(angle: $aimAngle°, aligned: $isAligned)';
}

AlignmentData parseAlignmentData(List<String> bytesList) {
  if (bytesList.length < 7) {
    throw ParseException(
      'insufficient data for parsing alignment data '
      '(need at least 7 bytes, got ${bytesList.length})',
    );
  }
  final r = _parseInt16(bytesList[5], bytesList[6]);
  final angle = r.ok ? r.value / 100.0 : 0.0;
  const threshold = 2.0;
  return AlignmentData(
    rawData: List.unmodifiable(bytesList),
    aimAngle: angle,
    isAligned: angle >= -threshold && angle <= threshold,
  );
}

// ── Frame routing helper ─────────────────────────────────────────────────────

enum NotificationKind {
  sensor, // 11 01
  ballMetrics, // 11 02
  status, // 11 03
  alignment, // 11 04
  charge, // 11 06
  clubMetrics, // 11 07
  osVersion, // 11 10
  battery, // 91 ..
  unknown,
}

NotificationKind classify(List<String> bytesList) {
  if (bytesList.isEmpty) return NotificationKind.unknown;
  if (bytesList[0] == '91') return NotificationKind.battery;
  if (bytesList.length < 2 || bytesList[0] != '11') {
    return NotificationKind.unknown;
  }
  return switch (bytesList[1]) {
    '01' => NotificationKind.sensor,
    '02' => NotificationKind.ballMetrics,
    '03' => NotificationKind.status,
    '04' => NotificationKind.alignment,
    '06' => NotificationKind.charge,
    '07' => NotificationKind.clubMetrics,
    '10' => NotificationKind.osVersion,
    _ => NotificationKind.unknown,
  };
}

// ── Internal: list equality ──────────────────────────────────────────────────

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
