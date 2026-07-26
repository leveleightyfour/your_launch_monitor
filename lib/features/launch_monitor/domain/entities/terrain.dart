/// The surfaces a hole can be built from.
///
/// [Surface] in `hole_setup.dart` is the older three-way answer the analytic
/// hole gives — fairway, green, rough. This is the full vocabulary the hole
/// builder paints with, and every one of them resolves back to a [GroundModel]
/// or to an outcome, so a built hole drives the physics rather than decorating
/// it.
library;

import 'package:flutter/painting.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// What a shot ended up being, once it stopped moving.
///
/// Water and out of bounds are not surfaces the ball rolls on — they end the
/// shot where it lands. Keeping that as an outcome rather than a turf model is
/// what stops the ground phase having to invent a friction coefficient for a
/// pond.
enum ShotOutcome {
  inPlay,
  water,
  outOfBounds;

  bool get isPenalty => this != ShotOutcome.inPlay;
}

enum Terrain {
  fairway,
  green,
  rough,

  /// Sand. Plays through the ground phase, on the harshest turf model there
  /// is.
  bunker,

  /// Ends the shot. The ball is gone.
  water,

  /// Trees are scenery the ball flies through — the ground beneath them plays
  /// as rough, which is what it would be.
  ///
  /// Making them solid means testing the ball against a volume at every
  /// integration step, which is a change to the flight loop rather than to the
  /// ground phase, so it is deliberately not what this does.
  trees,

  /// Ends the shot, with a penalty.
  outOfBounds;

  /// Single letter used by the run-length encoding. Stable — changing one
  /// silently rewrites every stored hole, so these are treated as wire format.
  String get code => switch (this) {
        Terrain.fairway => 'f',
        Terrain.green => 'g',
        Terrain.rough => 'r',
        Terrain.bunker => 'b',
        Terrain.water => 'w',
        Terrain.trees => 't',
        Terrain.outOfBounds => 'o',
      };

  static Terrain fromCode(String code) => switch (code) {
        'f' => Terrain.fairway,
        'g' => Terrain.green,
        'r' => Terrain.rough,
        'b' => Terrain.bunker,
        'w' => Terrain.water,
        't' => Terrain.trees,
        'o' => Terrain.outOfBounds,
        // An unknown code means a hole written by a newer build. Rough is the
        // safe read: it is neither a free ride nor a penalty.
        _ => Terrain.rough,
      };

  /// How the ball behaves on it. Terrain that ends the shot still needs a
  /// model, because the ball has to touch down somewhere before it is
  /// declared lost.
  GroundModel get ground => switch (this) {
        Terrain.fairway => GroundModel.fairway,
        Terrain.green => GroundModel.green,
        Terrain.bunker => GroundModel.bunker,
        // Under the trees, in the long stuff, and over the line: all rough.
        Terrain.rough || Terrain.trees => GroundModel.rough,
        Terrain.water || Terrain.outOfBounds => GroundModel.rough,
      };

  /// What finishing here means for the shot.
  ShotOutcome get outcome => switch (this) {
        Terrain.water => ShotOutcome.water,
        Terrain.outOfBounds => ShotOutcome.outOfBounds,
        _ => ShotOutcome.inPlay,
      };

  /// Whether touching this ends the shot on contact rather than letting it
  /// run out.
  bool get stopsShot => outcome.isPenalty;

  String get label => switch (this) {
        Terrain.fairway => 'Fairway',
        Terrain.green => 'Green',
        Terrain.rough => 'Rough',
        Terrain.bunker => 'Bunker',
        Terrain.water => 'Water',
        Terrain.trees => 'Trees',
        Terrain.outOfBounds => 'Out of bounds',
      };
}

/// Colours the 3D view and the builder both paint terrain with, so a cell
/// looks the same in the editor as it does on the hole.
extension TerrainPalette on Terrain {
  Color get surfaceColor => switch (this) {
        Terrain.fairway => AppColors.turfFairway,
        Terrain.green => AppColors.turfGreen,
        Terrain.rough => AppColors.turfRough,
        Terrain.bunker => AppColors.turfBunker,
        Terrain.water => AppColors.turfWater,
        Terrain.trees => AppColors.turfTrees,
        Terrain.outOfBounds => AppColors.turfOob,
      };

  /// Alternate band, for the surfaces that are mown in stripes. Everything
  /// else returns its own colour, so the caller can stripe unconditionally.
  Color get stripeColor => switch (this) {
        Terrain.fairway => AppColors.turfFairwayStripe,
        Terrain.green => AppColors.turfGreenCollar,
        _ => surfaceColor,
      };
}
