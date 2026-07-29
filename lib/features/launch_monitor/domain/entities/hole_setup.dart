/// A simple hole to play shots into: a fairway of a given width running out to
/// a green at a given distance.
///
/// Every shot is played from the tee, so a configured hole behaves like a par
/// 3 — hit, see where it finishes relative to the green, hit again. Nothing
/// carries between shots.
///
/// The hole is not just scenery: [surfaceAt] feeds the flight model's ground
/// phase, so a ball that lands on the green checks, one on the fairway
/// releases, and one in the rough stops dead.
library;

import 'dart:math' as math;

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';

/// What the ball is sitting on.
enum Surface { fairway, green, rough }

class HoleSetup {
  /// When false the hole is off: everything plays as fairway, exactly as it
  /// did before holes existed.
  final bool enabled;

  /// Tee to the centre of the green, in yards.
  final double greenDistance;

  /// Green width across the target line, in yards.
  final double greenWidth;

  /// Green depth front-to-back, in yards.
  final double greenDepth;

  /// Lateral offset of the green centre from the target line (+ = right).
  final double greenOffset;

  /// Total fairway width, in yards.
  final double fairwayWidth;

  /// A hand-built hole, when there is one.
  ///
  /// Present, it is the authority: [terrainAt] reads it and the analytic
  /// fairway-and-green is ignored. Absent, everything behaves exactly as it
  /// did before holes could be painted, which is what keeps every shot already
  /// stamped with an analytic hole rendering and scoring the way it always
  /// has.
  final HoleGrid? grid;

  const HoleSetup({
    this.enabled = false,
    this.greenDistance = 165,
    this.greenWidth = 30,
    this.greenDepth = 25,
    this.greenOffset = 0,
    this.fairwayWidth = 40,
    this.grid,
  });

  /// No hole — fairway everywhere.
  static const off = HoleSetup();

  /// What a fresh install plays into: a mid-iron par 3. The feature is
  /// invisible when it defaults to off, and a green nobody can see is a green
  /// nobody knows they can move.
  static const standard = HoleSetup(enabled: true);

  // Bounds the UI and persistence layer clamp to. Wide enough for anything
  // playable, tight enough that a bad value can't break the renderer.
  static const minGreenDistance = 30.0;
  static const maxGreenDistance = 650.0;
  static const minGreenSize = 8.0;
  static const maxGreenSize = 90.0;
  static const maxGreenOffset = 80.0;
  static const minFairwayWidth = 10.0;
  static const maxFairwayWidth = 120.0;

  HoleSetup copyWith({
    bool? enabled,
    double? greenDistance,
    double? greenWidth,
    double? greenDepth,
    double? greenOffset,
    double? fairwayWidth,
    HoleGrid? grid,
    bool clearGrid = false,
  }) => HoleSetup(
    enabled: enabled ?? this.enabled,
    greenDistance: greenDistance ?? this.greenDistance,
    greenWidth: greenWidth ?? this.greenWidth,
    greenDepth: greenDepth ?? this.greenDepth,
    greenOffset: greenOffset ?? this.greenOffset,
    fairwayWidth: fairwayWidth ?? this.fairwayWidth,
    grid: clearGrid ? null : (grid ?? this.grid),
  ).clamped;

  /// Every dimension forced into a sane range.
  HoleSetup get clamped => HoleSetup(
    enabled: enabled,
    greenDistance: greenDistance
        .clamp(minGreenDistance, maxGreenDistance)
        .toDouble(),
    greenWidth: greenWidth.clamp(minGreenSize, maxGreenSize).toDouble(),
    greenDepth: greenDepth.clamp(minGreenSize, maxGreenSize).toDouble(),
    greenOffset: greenOffset.clamp(-maxGreenOffset, maxGreenOffset).toDouble(),
    fairwayWidth: fairwayWidth
        .clamp(minFairwayWidth, maxFairwayWidth)
        .toDouble(),
    grid: grid,
  );

  /// Downrange distance to the front edge of the green.
  double get greenFront => greenDistance - greenDepth / 2;

  /// Downrange distance to the back edge of the green.
  double get greenBack => greenDistance + greenDepth / 2;

  /// Where the pin is — the middle of the green.
  Vec3 get pin => Vec3(greenOffset, 0, greenDistance);

  /// The surface at a point on the ground.
  ///
  /// The green is an ellipse; the fairway is a strip from the tee to the front
  /// of the green; everything else — beside the fairway, around the green,
  /// past the back — is rough.
  /// The full terrain at a point — the grid's answer when there is one, and
  /// the analytic hole's three-way answer widened to fit when there is not.
  Terrain terrainAt(double x, double z) {
    final built = grid;
    if (built != null) return enabled ? built.terrainAt(x, z) : Terrain.fairway;
    return switch (surfaceAt(x, z)) {
      Surface.green => Terrain.green,
      Surface.fairway => Terrain.fairway,
      Surface.rough => Terrain.rough,
    };
  }

  Surface surfaceAt(double x, double z) {
    if (!enabled) return Surface.fairway;

    // A built hole overrides the fairway-and-green description entirely.
    // Anything the old three-way vocabulary has no word for is reported as
    // rough, which is what a caller that only knows Surface should assume.
    final built = grid;
    if (built != null) {
      return switch (built.terrainAt(x, z)) {
        Terrain.green => Surface.green,
        Terrain.fairway => Surface.fairway,
        _ => Surface.rough,
      };
    }

    final halfWidth = greenWidth / 2;
    final halfDepth = greenDepth / 2;
    if (halfWidth > 0 && halfDepth > 0) {
      final dx = (x - greenOffset) / halfWidth;
      final dz = (z - greenDistance) / halfDepth;
      if (dx * dx + dz * dz <= 1.0) return Surface.green;
    }

    if (x.abs() <= fairwayWidth / 2 && z >= 0 && z <= greenFront) {
      return Surface.fairway;
    }

    return Surface.rough;
  }

  /// Turf model for a point on the ground — what the flight model's ground
  /// phase asks at every contact.
  GroundModel groundAt(double x, double z) => terrainAt(x, z).ground;

  /// What finishing at a point means for the shot — in play, wet, or gone.
  ShotOutcome outcomeAt(double x, double z) =>
      enabled ? terrainAt(x, z).outcome : ShotOutcome.inPlay;

  /// Whether touching down here ends the shot on the spot. Handed to the
  /// flight model, which knows nothing about hazards beyond this answer.
  bool stopsAt(double x, double z) => enabled && terrainAt(x, z).stopsShot;

  /// Distance from the pin to a resting ball, in yards.
  ///
  /// A pin placed on a built hole wins; otherwise the analytic green's
  /// centre stands in for it, as it always has.
  double distanceFromPin(Vec3 rest) {
    final placed = grid?.pinCentre;
    final px = placed?.$1 ?? greenOffset;
    final pz = placed?.$2 ?? greenDistance;
    final dx = rest.x - px;
    final dz = rest.z - pz;
    return math.sqrt(dx * dx + dz * dz);
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'greenDistance': greenDistance,
    'greenWidth': greenWidth,
    'greenDepth': greenDepth,
    'greenOffset': greenOffset,
    'fairwayWidth': fairwayWidth,
    if (grid != null) 'grid': grid!.toJson(),
  };

  factory HoleSetup.fromJson(Map<String, dynamic> json) => HoleSetup(
    enabled: json['enabled'] as bool? ?? false,
    greenDistance: (json['greenDistance'] as num?)?.toDouble() ?? 165,
    greenWidth: (json['greenWidth'] as num?)?.toDouble() ?? 30,
    greenDepth: (json['greenDepth'] as num?)?.toDouble() ?? 25,
    greenOffset: (json['greenOffset'] as num?)?.toDouble() ?? 0,
    fairwayWidth: (json['fairwayWidth'] as num?)?.toDouble() ?? 40,
    grid: json['grid'] == null
        ? null
        : HoleGrid.fromJson((json['grid'] as Map).cast<String, dynamic>()),
  ).clamped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoleSetup &&
          enabled == other.enabled &&
          greenDistance == other.greenDistance &&
          greenWidth == other.greenWidth &&
          greenDepth == other.greenDepth &&
          greenOffset == other.greenOffset &&
          fairwayWidth == other.fairwayWidth &&
          grid == other.grid;

  @override
  int get hashCode => Object.hash(
    enabled,
    greenDistance,
    greenWidth,
    greenDepth,
    greenOffset,
    fairwayWidth,
    grid,
  );

  @override
  String toString() => enabled
      ? 'HoleSetup(green ${greenDistance}y '
            '${greenWidth}x${greenDepth}y, offset $greenOffset, '
            'fairway ${fairwayWidth}y)'
      : 'HoleSetup(off)';
}
