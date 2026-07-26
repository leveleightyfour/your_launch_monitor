import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

/// Simulated flights are cached per shot — the integration is cheap but it runs
/// on every rebuild of the dispersion plot and the 3D flight view otherwise.
final Expando<ShotTrajectory> _trajectoryCache = Expando('shotTrajectory');

class ShotData {
  /// Database row ID. Null for shots that haven't been persisted yet.
  final int? dbId;
  final String? clubId;

  // Ball data
  final double ballSpeed;
  final double spinRate;
  final double spinAxis;
  final double launchDirection; // horizontal launch angle (deg)
  final double launchAngle;    // vertical launch angle (deg)

  // Club data
  final double clubSpeed;

  // Nullable — populated once BLE protocol is decoded
  final double? apex;          // max height (yds)
  final double? run;           // rolling distance (yds)
  final double? swingPath;     // club path angle (deg)
  final double? faceAngle;     // face angle relative to target (deg)
  final double? angleOfAttack; // (deg)
  final double? dynamicLoft;   // (deg)
  final double? horizontalImpact; // impact position (mm, + = toe)
  final double? verticalImpact;   // impact position (mm, + = high)

  /// IDs referencing persisted [Tag] rows.
  final List<int> tagIds;

  /// The hole this shot was played to, if one was configured.
  ///
  /// It travels with the shot rather than being read from settings, so a saved
  /// session keeps reporting the totals it was played to even after the hole
  /// settings change. Null means no hole: fairway everywhere.
  final HoleSetup? hole;

  const ShotData({
    this.dbId,
    this.clubId,
    required this.ballSpeed,
    required this.spinRate,
    required this.spinAxis,
    required this.launchDirection,
    required this.launchAngle,
    required this.clubSpeed,
    this.apex,
    this.run,
    this.swingPath,
    this.faceAngle,
    this.angleOfAttack,
    this.dynamicLoft,
    this.horizontalImpact,
    this.verticalImpact,
    this.tagIds = const [],
    this.hole,
  });

  ShotData copyWith({
    int? dbId,
    List<int>? tagIds,
    HoleSetup? hole,
    bool clearHole = false,
  }) {
    return ShotData(
      dbId: dbId ?? this.dbId,
      clubId: clubId,
      ballSpeed: ballSpeed,
      spinRate: spinRate,
      spinAxis: spinAxis,
      launchDirection: launchDirection,
      launchAngle: launchAngle,
      clubSpeed: clubSpeed,
      apex: apex,
      run: run,
      swingPath: swingPath,
      faceAngle: faceAngle,
      angleOfAttack: angleOfAttack,
      dynamicLoft: dynamicLoft,
      horizontalImpact: horizontalImpact,
      verticalImpact: verticalImpact,
      tagIds: tagIds ?? this.tagIds,
      hole: clearHole ? null : (hole ?? this.hole),
    );
  }

  /// Simulated ball flight for this shot's launch conditions.
  ///
  /// The Omni measures launch only, so carry, apex, curvature and the shape of
  /// the flight all come from integrating the trajectory. When the shot was
  /// played to a [hole], the ground phase resolves turf from it, so where the
  /// ball lands decides how it releases. Cached per shot.
  ShotTrajectory get trajectory {
    final cached = _trajectoryCache[this];
    if (cached != null) return cached;
    final playedHole = hole;
    final computed = BallFlightModel.standard.simulate(
      ballSpeedMph: ballSpeed,
      launchAngleDeg: launchAngle,
      launchDirectionDeg: launchDirection,
      spinRpm: spinRate,
      spinAxisDeg: spinAxis,
      measuredRollYds: run,
      groundAt: playedHole != null && playedHole.enabled
          ? playedHole.groundAt
          : null,
      stopsAt: playedHole != null && playedHole.enabled
          ? playedHole.stopsAt
          : null,
    );
    _trajectoryCache[this] = computed;
    return computed;
  }

  /// Where the ball finished up in the rules sense — in play, wet, or gone.
  ///
  /// Derived from the resting position rather than tracked through the
  /// simulation, which keeps the flight model free of golf: it reports where
  /// the ball stopped, and the hole says what that means.
  ShotOutcome get outcome {
    final playedHole = hole;
    if (playedHole == null || !playedHole.enabled) return ShotOutcome.inPlay;
    final rest = trajectory.restPosition;
    return playedHole.outcomeAt(rest.x, rest.z);
  }

  /// Carry distance in yards, from the simulated flight.
  double get carry => trajectory.carry;

  double get totalDistance => trajectory.totalDistance;

  /// Apex height in yards — the device value when available, otherwise the
  /// simulated one.
  double get apexHeight => apex ?? trajectory.apex;

  /// Roll-out in yards — the device value when available, otherwise estimated
  /// from the landing angle.
  double get rollDistance => run ?? trajectory.roll;

  /// Lateral offset at landing in yards (positive = right of target). Includes
  /// the ball's curvature, not just the launch direction.
  double get lateralOffset => trajectory.offline;

  /// Sideways yards the ball curved in the air, independent of start line.
  double get curveDistance => trajectory.curve;

  /// Angle the ball lands at, in degrees below horizontal.
  double get descentAngle => trajectory.descentAngle;

  /// Ball speed / club speed ratio.
  double get smashFactor => clubSpeed > 0 ? ballSpeed / clubSpeed : 0.0;

  /// Returns a synthetic ShotData representing the average of [shots].
  static ShotData averageOf(List<ShotData> shots) {
    assert(shots.isNotEmpty);
    double avg(double Function(ShotData) f) =>
        shots.map(f).reduce((a, b) => a + b) / shots.length;
    double? avgNullable(double? Function(ShotData) f) {
      final vals = shots.map(f).whereType<double>().toList();
      return vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
    }

    return ShotData(
      clubId: shots.first.clubId,
      ballSpeed: avg((s) => s.ballSpeed),
      spinRate: avg((s) => s.spinRate),
      spinAxis: avg((s) => s.spinAxis),
      launchDirection: avg((s) => s.launchDirection),
      launchAngle: avg((s) => s.launchAngle),
      clubSpeed: avg((s) => s.clubSpeed),
      apex: avgNullable((s) => s.apex),
      run: avgNullable((s) => s.run),
      swingPath: avgNullable((s) => s.swingPath),
      faceAngle: avgNullable((s) => s.faceAngle),
      angleOfAttack: avgNullable((s) => s.angleOfAttack),
      dynamicLoft: avgNullable((s) => s.dynamicLoft),
      horizontalImpact: avgNullable((s) => s.horizontalImpact),
      verticalImpact: avgNullable((s) => s.verticalImpact),
      tagIds: const [],
      hole: shots.first.hole,
    );
  }
}
