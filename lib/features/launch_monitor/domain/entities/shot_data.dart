import 'dart:math' as math;

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
  });

  ShotData copyWith({int? dbId, List<int>? tagIds}) {
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
    );
  }

  /// Estimated carry distance in yards (simplified ballistic + ~20% lift correction).
  /// Replaced by device value once protocol is decoded.
  double get carry {
    final vFps = ballSpeed * 1.46667;
    final thetaRad = launchAngle * math.pi / 180.0;
    final rangeFeet = vFps * vFps * math.sin(2.0 * thetaRad) / 32.174;
    return (rangeFeet / 3.0) * 1.2;
  }

  double get totalDistance => carry + (run ?? 0.0);

  /// Estimated lateral offset in yards (positive = right of target).
  double get lateralOffset =>
      carry * math.tan(launchDirection * math.pi / 180.0);

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
    );
  }
}
