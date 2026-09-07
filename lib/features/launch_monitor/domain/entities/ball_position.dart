/// Where the ball is sitting on the mat, decoded from the `11 01` sensor
/// frame's position words.
///
/// **Scale and axes** come from the `squaregolf-connector` reference's own
/// ball-position view (`web/static/js/features/ShotMonitor.js`), the only place
/// the semantics are written down: it divides the raw words by 10, plots
/// protocol Y horizontally and protocol X vertically — so X is depth and Y is
/// lateral — and draws its grid at exactly 200 of the resulting units. That
/// last number is the unit tell: a 200 mm grid over a metre of mat is a
/// sensible drawing, where centimetres would make it a 2 m grid and raw ticks
/// a 2 cm one. So the working unit is millimetres and a raw tick is a tenth.
/// Readings off a real device bear this out — the height word sits near a
/// constant −100 mm, which is what a ball on the mat looks like to a sensor
/// mounted above it.
///
/// **The origin is the middle of what the monitor can see**, not the monitor
/// itself. Walking the ball to the edges of the hitting area gives readings
/// spread either side of zero on both axes, while the device physically stands
/// off to the golfer's right — so zero is the centre of its field of view. That
/// is why the manual's ready-zone offsets never fitted: it quotes them from the
/// device's body, and these coordinates are not measured from there. There is deliberately no ready-zone
/// geometry here. The manual quotes the zone as 5 cm to the side and 35 cm in
/// front, but that only holds with the monitor standing where its illustration
/// puts it; a real setup read a metre in front, and every attempt to infer the
/// zone from those numbers produced confident verdicts about a box in the wrong
/// place. The device already answers the only question that mattered — its
/// light goes green when the ball is ready — so that answer is used directly
/// instead of being re-derived from arithmetic that cannot be trusted.
library;

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/notifications.dart';

/// Raw position words per millimetre.
///
/// Twenty, not the ten the `squaregolf-connector` reference divides by. Its
/// own view plots `position / 10`, and its grid works out to exactly 200 of the
/// resulting units — which I read as a 200 mm grid over a metre of mat, and
/// therefore as millimetres. A 100 mm grid over half a metre fits that drawing
/// just as well, and that is the one the hardware agrees with.
///
/// The mat settles it. The manual's ready zone is 25 cm square beginning 35 cm
/// in front of the monitor, so a ball can only ever sit 350–600 mm out. Pushed
/// to the front of the square and still recognised, the device reported
/// `12460`: at ÷10 that is 1246 mm, more than twice as far as the zone extends
/// and further than the camera can see; at ÷20 it is 623 mm, a couple of
/// centimetres past the zone's far edge, which is precisely where detection
/// should give out. A second careful reading, `10150 / 3090`, lands at
/// 508 mm × 155 mm — inside the zone on both axes.
const double ticksPerMm = 20.0;

/// Mown band width on the drawn mat, in millimetres.
const double mapGridMm = 100.0;

/// Positive is toward the target, confirmed on the mat: the front edge of the
/// hitting area reads +570 at the corners and +623 through the middle.
const double depthSign = 1.0;

/// Negated, so positive is the golfer's right.
///
/// The device reports positive to the golfer's *left*: standing at the mat
/// facing the target, the front-left corner of the hitting area reads +596 and
/// the front-right reads -542. The map is a down-the-line view with the target
/// at the top, so the golfer's left is the picture's left — drawing the raw
/// value straight put every ball on the wrong side.
///
/// Negating here fixes the drawing and puts the readout on golf's own
/// convention at the same time, where a positive lateral figure means right of
/// the target line.
const double lateralSign = -1.0;

// ── Drawn area ───────────────────────────────────────────────────────────────
// Centred on where the ball actually sits, not on the monitor.
//
// The monitor stands off to one side and well behind the hitting area — real
// readings put the ball around a metre in front of it and a few hundred
// millimetres to the side. A window centred on the monitor therefore spent its
// left half on empty mat, pushed the ball up toward the front edge, and clipped
// a reading that ran past the right edge at +1231 mm.
//
// Fixed, not fitted to the live ball: a window that rescales itself to chase
// the ball makes everything drawn on it appear to move while the ball sits
// still.

// ── The area the monitor can actually see ────────────────────────────────────
// Walked out on the mat, corner by corner, until the ball stopped being
// recognised. Signs as the app reports them, positive to the golfer's right.
//
//   front-left  +570 / -596        back-left  -601 / -507
//   front-right +570 / +542        centre-front +623
//
// The corners fall short of the centre — +570 against +623 — so the boundary is
// rounded rather than square, matching the shape in the manual's figure.

const double detectedFrontMm = 623;
const double detectedBackMm = -601;
const double detectedRightMm = 542;
const double detectedLeftMm = -596;

/// How much mat the window covers on each axis. Square, so the picture is not
/// stretched when it is drawn into the square status-bar indicator, and only
/// fractionally larger than the area above.
///
/// Sized to the measurement rather than to a round number: every earlier window
/// drew mat the sensor cannot reach, which is why a ball pushed to the front of
/// the hitting area never reached the front of the picture.
const double mapSpanMm = 1300;

/// Centred on the middle of that area.
const double mapCentreDepthMm = (detectedFrontMm + detectedBackMm) / 2;
const double mapCentreLateralMm = (detectedRightMm + detectedLeftMm) / 2;

/// The rectangle of mat the map draws, in device coordinates.
class MatBounds {
  final double minLateralMm;
  final double maxLateralMm;
  final double minDepthMm;
  final double maxDepthMm;

  const MatBounds({
    required this.minLateralMm,
    required this.maxLateralMm,
    required this.minDepthMm,
    required this.maxDepthMm,
  });

  double get widthMm => maxLateralMm - minLateralMm;
  double get depthMm => maxDepthMm - minDepthMm;

  /// The mat as drawn: [mapSpanMm] square about the visible area.
  static const MatBounds mat = MatBounds(
    minLateralMm: mapCentreLateralMm - mapSpanMm / 2,
    maxLateralMm: mapCentreLateralMm + mapSpanMm / 2,
    minDepthMm: mapCentreDepthMm - mapSpanMm / 2,
    maxDepthMm: mapCentreDepthMm + mapSpanMm / 2,
  );
}

class BallPosition {
  /// Millimetres in front of the launch monitor, along the target line.
  final double depthMm;

  /// Millimetres to the side of the launch monitor, across the target line.
  final double lateralMm;

  /// Millimetres on the remaining axis — height above the mat, most likely,
  /// though nothing confirms it. Carried so a tee-height reading is one step
  /// away, and unused by the map.
  final double heightMm;

  /// Whether the device currently sees a ball at all. When false the position
  /// is stale and must not be drawn.
  final bool detected;

  /// Whether the device says the ball is ready to hit.
  ///
  /// The monitor's own verdict, and the one this app trusts. Per the manual its
  /// light goes solid green with the ball placed correctly and blinks while it
  /// waits — so this answers "is the ball where it needs to be" without the app
  /// having to work out where that is.
  final bool ready;

  /// Byte 3 of the sensor frame, verbatim.
  ///
  /// [ready] folds two distinct values (`01` and `02`) into one bool, following
  /// the Go reference. The manual's two light behaviours — solid versus
  /// blinking — suggest those values mean different things, so the raw number
  /// is kept in case the difference turns out to matter.
  final int readyState;

  /// The position words exactly as they came off the wire, before any scale or
  /// sign was applied.
  ///
  /// Everything above them is inference drawn from a third-party connector's
  /// rendering code rather than vendor documentation. When the drawing and the
  /// mat disagree, these are the numbers that settle it.
  final int rawX;
  final int rawY;
  final int rawZ;

  const BallPosition({
    required this.depthMm,
    required this.lateralMm,
    required this.heightMm,
    required this.detected,
    required this.ready,
    this.readyState = 0,
    this.rawX = 0,
    this.rawY = 0,
    this.rawZ = 0,
  });

  /// Decode a sensor frame into mat coordinates.
  factory BallPosition.fromSensor(SensorData s) => BallPosition(
    depthMm: depthSign * s.positionX / ticksPerMm,
    lateralMm: lateralSign * s.positionY / ticksPerMm,
    heightMm: s.positionZ / ticksPerMm,
    detected: s.ballDetected,
    ready: s.ballReady,
    readyState: s.readyState,
    rawX: s.positionX,
    rawY: s.positionY,
    rawZ: s.positionZ,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BallPosition &&
          depthMm == other.depthMm &&
          lateralMm == other.lateralMm &&
          heightMm == other.heightMm &&
          detected == other.detected &&
          ready == other.ready &&
          readyState == other.readyState &&
          rawX == other.rawX &&
          rawY == other.rawY &&
          rawZ == other.rawZ;

  @override
  int get hashCode => Object.hash(
    depthMm,
    lateralMm,
    heightMm,
    detected,
    ready,
    readyState,
    rawX,
    rawY,
    rawZ,
  );

  @override
  String toString() =>
      'BallPosition(depth: ${depthMm}mm, lateral: ${lateralMm}mm, '
      'height: ${heightMm}mm, detected: $detected, ready: $ready, '
      'raw: ($rawX, $rawY, $rawZ))';
}
