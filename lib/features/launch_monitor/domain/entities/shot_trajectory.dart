/// Physics-based golf ball flight, bounce and roll model.
///
/// The Omni reports launch conditions only — ball speed, launch angle, launch
/// direction, total spin and spin axis. Everything downstream of impact
/// (carry, apex, descent angle, curvature, how the ball behaves when it lands,
/// where it finishes) has to be simulated. This module integrates the ball's
/// equations of motion so the 3D flight view, the dispersion plot and the shot
/// table all describe the same shot.
///
/// Airborne forces: gravity, aerodynamic drag and the Magnus force from the
/// spinning ball. On the ground the ball is bounced with a speed-dependent
/// restitution and a friction impulse that couples spin to the turf, then
/// slides and rolls out. Conditions are sea-level ISA (1.225 kg/m³), no wind.
///
/// See `docs/flight_model.md` and `docs/flight_model_validation.md`.
library;

import 'dart:math' as math;

// ── Unit conversions ─────────────────────────────────────────────────────────

const double _mphToMps = 0.44704;
const double _mpsToMph = 1 / _mphToMps;
const double _mToYd = 1.0936133;
const double _rpmToRadPerSec = 2 * math.pi / 60.0;
const double _radPerSecToRpm = 1 / _rpmToRadPerSec;
const double _degToRad = math.pi / 180.0;
const double _radToDeg = 180.0 / math.pi;

// ── Ball / atmosphere constants ──────────────────────────────────────────────

/// Mass of a conforming golf ball (kg) — R&A/USGA maximum is 45.93 g.
const double _ballMassKg = 0.04593;

/// Radius of a conforming golf ball (m) — minimum diameter is 42.67 mm.
const double _ballRadiusM = 0.021335;

/// Air density at sea level, 15 °C (kg/m³).
const double _airDensity = 1.225;

const double _gravity = 9.80665;

/// ½ρA/m — the common factor in both the drag and Magnus terms (1/m).
final double _forceFactor =
    _airDensity * math.pi * _ballRadiusM * _ballRadiusM / (2 * _ballMassKg);

// ── Vector helper ────────────────────────────────────────────────────────────

/// Minimal 3-vector. World axes: +x right of the target line, +y up,
/// +z downrange towards the target.
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);
  static const up = Vec3(0, 1, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);

  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);

  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 get normalized {
    final len = length;
    return len == 0 ? zero : Vec3(x / len, y / len, z / len);
  }

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, '
      '${z.toStringAsFixed(2)})';
}

// ── Sampled flight ───────────────────────────────────────────────────────────

/// One sampled instant of a ball flight. Distances are yards, speed is mph.
class TrajectoryPoint {
  /// Seconds since impact.
  final double t;

  /// Lateral offset from the target line (+ = right).
  final double x;

  /// Height above the ground.
  final double y;

  /// Distance downrange.
  final double z;

  /// Ball speed at this instant (mph).
  final double speed;

  const TrajectoryPoint({
    required this.t,
    required this.x,
    required this.y,
    required this.z,
    required this.speed,
  });

  Vec3 get position => Vec3(x, y, z);
}

/// Result of a shot simulation. All distances are yards, angles degrees.
class ShotTrajectory {
  /// Airborne path, first point at impact, last point at touchdown.
  final List<TrajectoryPoint> points;

  /// Bounce-and-roll path, from touchdown to rest. Empty when the ball stops
  /// dead. Hops rise above `y == 0`; the roll-out runs along it.
  final List<TrajectoryPoint> groundPoints;

  /// Distance down the target line to the first bounce.
  final double carry;

  /// Maximum height reached.
  final double apex;

  /// Downrange distance at which [apex] occurs.
  final double apexDistance;

  /// Seconds from impact to touchdown.
  final double flightTime;

  /// Seconds from touchdown to rest.
  final double groundTime;

  /// Angle of the flight path below horizontal at touchdown.
  final double descentAngle;

  /// Ball speed at touchdown (mph).
  final double landingSpeed;

  /// Spin remaining at touchdown (rpm) — what drives the bounce behaviour.
  final double landingSpin;

  /// Lateral offset at touchdown (+ = right of the target line).
  final double offline;

  /// Sideways deviation from the initial launch line — the amount the ball
  /// actually curved in the air, independent of where it started.
  final double curve;

  /// Downrange yards gained after touchdown. Negative when a steep, heavily
  /// spinning shot checks and spins back.
  final double roll;

  /// Where the ball comes to rest.
  final Vec3 restPosition;

  /// Number of bounces before the ball settled into a roll.
  final int bounces;

  const ShotTrajectory({
    required this.points,
    required this.groundPoints,
    required this.carry,
    required this.apex,
    required this.apexDistance,
    required this.flightTime,
    required this.groundTime,
    required this.descentAngle,
    required this.landingSpeed,
    required this.landingSpin,
    required this.offline,
    required this.curve,
    required this.roll,
    required this.restPosition,
    required this.bounces,
  });

  /// Carry plus roll — the downrange distance to where the ball rests.
  double get totalDistance => carry + roll;

  /// Lateral offset where the ball comes to rest (+ = right).
  double get totalOffline => restPosition.x;

  /// An empty flight, used for shots with no usable launch data.
  static const empty = ShotTrajectory(
    points: [],
    groundPoints: [],
    carry: 0,
    apex: 0,
    apexDistance: 0,
    flightTime: 0,
    groundTime: 0,
    descentAngle: 0,
    landingSpeed: 0,
    landingSpin: 0,
    offline: 0,
    curve: 0,
    roll: 0,
    restPosition: Vec3.zero,
    bounces: 0,
  );

  bool get isEmpty => points.length < 2;
}

// ── Turf ─────────────────────────────────────────────────────────────────────

/// Turf properties governing the bounce and roll.
///
/// [slidingFriction] is the ball–turf friction coefficient during contact; it
/// sets how much of the ball's spin and forward speed the ground can take in
/// one bounce. [rollingResistance] decelerates the ball once it is rolling
/// without slipping. [restitutionScale] softens or firms up the rebound
/// relative to the measured baseline for fairway turf.
class GroundModel {
  final double slidingFriction;
  final double rollingResistance;
  final double restitutionScale;

  /// How much forward speed the ball loses digging into, and climbing out of,
  /// its own pitch mark. Friction alone cannot account for this: it is a
  /// reaction from the leading wall of the crater, so it is not capped by the
  /// no-slip limit, and it scales with how steeply the ball arrives.
  final double ploughing;

  const GroundModel({
    required this.slidingFriction,
    required this.rollingResistance,
    required this.restitutionScale,
    required this.ploughing,
  });

  /// Typical mown fairway — the default for range and simulator work.
  static const fairway = GroundModel(
    ploughing: 0.19,
    slidingFriction: 0.40,
    rollingResistance: 0.42,
    restitutionScale: 1.0,
  );

  /// Watered green: grabs hard, barely rebounds, so spin bites.
  static const green = GroundModel(
    ploughing: 0.26,
    slidingFriction: 0.50,
    rollingResistance: 0.32,
    restitutionScale: 0.70,
  );

  /// Baked-out links fairway.
  static const firm = GroundModel(
    ploughing: 0.11,
    slidingFriction: 0.34,
    rollingResistance: 0.26,
    restitutionScale: 1.25,
  );

  /// Rough — kills the ball on landing.
  static const rough = GroundModel(
    ploughing: 0.45,
    slidingFriction: 0.60,
    rollingResistance: 1.10,
    restitutionScale: 0.45,
  );
}

// ── Model ────────────────────────────────────────────────────────────────────

/// Aerodynamic coefficients, turf and integration settings.
///
/// The drag and lift coefficients are functions of the spin ratio
/// `S = ωr/v`, following the shape of published wind-tunnel fits for dimpled
/// spheres. The constants in [standard] were fitted against Trackman tour
/// averages for driver through pitching wedge — see
/// `docs/flight_model_validation.md`.
class BallFlightModel {
  /// Drag coefficient at zero spin.
  final double dragBase;

  /// Additional drag per unit of spin ratio.
  final double dragPerSpin;

  /// Additional drag as the ball slows below [dragSpeedRefMps]. A dimpled ball
  /// sits in the low-drag supercritical regime at driver speeds and drifts back
  /// towards subcritical drag as it decelerates.
  final double dragAtLowSpeed;

  /// Asymptotic lift coefficient at very high spin ratio.
  final double liftMax;

  /// Spin ratio at which the lift coefficient reaches half of [liftMax].
  final double liftHalfSpin;

  /// Time constant of the exponential spin decay (seconds).
  final double spinDecaySeconds;

  /// Integration step (seconds).
  final double stepSeconds;

  /// Turf the ball lands on.
  final GroundModel ground;

  const BallFlightModel({
    this.dragBase = 0.205,
    this.dragPerSpin = 0.15,
    this.dragAtLowSpeed = 0.18,
    this.liftMax = 0.40,
    this.liftHalfSpin = 0.15,
    this.spinDecaySeconds = 24.0,
    this.stepSeconds = 0.005,
    this.ground = GroundModel.fairway,
  });

  /// Speed above which the ball sees its lowest drag (m/s).
  static const double dragSpeedRefMps = 55.0;

  /// Below this rebound speed the ball is treated as down for good.
  static const double _minBounceSpeedMps = 0.4;

  /// Contact-point speed below which the ball is rolling, not slipping.
  static const double _slipEpsilonMps = 0.05;

  /// Ceiling on the share of ground speed one bounce can plough away.
  static const double _maxPloughFraction = 0.55;

  /// The ball is at rest below this speed.
  static const double _restSpeedMps = 0.22;

  static const int _maxBounces = 8;
  static const double _maxGroundSeconds = 15.0;
  static const double _maxFlightSeconds = 20.0;

  /// Fitted sea-level model used throughout the app.
  static const standard = BallFlightModel();

  BallFlightModel copyWith({GroundModel? ground}) => BallFlightModel(
        dragBase: dragBase,
        dragPerSpin: dragPerSpin,
        dragAtLowSpeed: dragAtLowSpeed,
        liftMax: liftMax,
        liftHalfSpin: liftHalfSpin,
        spinDecaySeconds: spinDecaySeconds,
        stepSeconds: stepSeconds,
        ground: ground ?? this.ground,
      );

  double dragCoefficient(double spinRatio, double speedMps) {
    final slowFactor =
        ((dragSpeedRefMps - speedMps) / dragSpeedRefMps).clamp(0.0, 1.0);
    // Upper bound only: a zero-drag configuration has to stay representable
    // so the integrator can be checked against the analytic vacuum solution.
    return (dragBase + dragPerSpin * spinRatio + dragAtLowSpeed * slowFactor)
        .clamp(0.0, 0.52);
  }

  double liftCoefficient(double spinRatio) =>
      liftMax * spinRatio / (liftHalfSpin + spinRatio);

  /// Coefficient of restitution for a ball striking turf at [impactSpeedMps]
  /// normal to the surface.
  ///
  /// Follows Penner's fit to measured golf-ball/turf impacts: fast, steep
  /// arrivals bury into the turf and barely rebound, slow ones bounce more.
  double restitution(double impactSpeedMps, [GroundModel? turf]) {
    final v = impactSpeedMps.abs();
    final e = 0.510 - 0.0375 * v + 0.000903 * v * v;
    return (e * (turf ?? ground).restitutionScale).clamp(0.03, 0.75);
  }

  /// Simulate a shot from launch to rest.
  ///
  /// [spinAxisDeg] follows the launch-monitor convention: positive tilts the
  /// spin axis to the right, curving the ball right (a fade for a right-hander).
  ///
  /// When the device reports its own roll, pass it as [measuredRollYds]: the
  /// bounce and roll are still simulated for their shape, then scaled so the
  /// downrange roll-out matches the measurement.
  ///
  /// [groundAt] resolves the turf under a point on the ground, in yards, and is
  /// consulted at every ground contact — so a ball can land on a green and
  /// check, or land short and release across the fairway onto it. Omit it and
  /// the whole world is [ground].
  ShotTrajectory simulate({
    required double ballSpeedMph,
    required double launchAngleDeg,
    required double launchDirectionDeg,
    required double spinRpm,
    required double spinAxisDeg,
    double? measuredRollYds,
    GroundModel Function(double xYards, double zYards)? groundAt,
  }) {
    if (ballSpeedMph <= 0 || launchAngleDeg <= 0) return ShotTrajectory.empty;

    final v0 = ballSpeedMph * _mphToMps;
    final theta = launchAngleDeg * _degToRad;
    final phi = launchDirectionDeg * _degToRad;

    var velocity = Vec3(
      v0 * math.cos(theta) * math.sin(phi),
      v0 * math.sin(theta),
      v0 * math.cos(theta) * math.cos(phi),
    );
    var position = Vec3.zero;
    var spin = _spinAxisVector(velocity.normalized, spinAxisDeg) *
        (spinRpm.abs() * _rpmToRadPerSec);

    final points = <TrajectoryPoint>[
      TrajectoryPoint(t: 0, x: 0, y: 0, z: 0, speed: ballSpeedMph),
    ];

    var t = 0.0;
    var apex = 0.0;
    var apexDistance = 0.0;
    // Sample every 4th step (~50 Hz) — plenty for a smooth curve on screen.
    const sampleEvery = 4;
    var step = 0;
    final maxSteps = (_maxFlightSeconds / stepSeconds).round();
    final spinDecayPerStep = math.exp(-stepSeconds / spinDecaySeconds);

    var previousPosition = position;
    var previousVelocity = velocity;
    var previousSpin = spin;

    while (step < maxSteps) {
      previousPosition = position;
      previousVelocity = velocity;
      previousSpin = spin;

      final next = _rk4Step(position, velocity, spin);
      position = next.$1;
      velocity = next.$2;
      spin = spin * spinDecayPerStep;
      t += stepSeconds;
      step++;

      if (position.y > apex) {
        apex = position.y;
        apexDistance = position.z;
      }

      if (position.y <= 0) break;

      if (step % sampleEvery == 0) {
        points.add(_toPoint(t, position, velocity));
      }
    }

    // Interpolate the touchdown state back onto the ground plane.
    final dy = previousPosition.y - position.y;
    final frac =
        dy.abs() < 1e-9 ? 1.0 : (previousPosition.y / dy).clamp(0.0, 1.0);
    final landPosition = Vec3(
      previousPosition.x + (position.x - previousPosition.x) * frac,
      0,
      previousPosition.z + (position.z - previousPosition.z) * frac,
    );
    final landVelocity =
        previousVelocity + (velocity - previousVelocity) * frac;
    final landSpin = previousSpin + (spin - previousSpin) * frac;
    final landTime = t - stepSeconds * (1 - frac);

    points.add(
      TrajectoryPoint(
        t: landTime,
        x: landPosition.x * _mToYd,
        y: 0,
        z: landPosition.z * _mToYd,
        speed: landVelocity.length * _mpsToMph,
      ),
    );

    final carry = landPosition.z * _mToYd;
    final offline = landPosition.x * _mToYd;
    final horizontalSpeed = math
        .sqrt(landVelocity.x * landVelocity.x + landVelocity.z * landVelocity.z);
    final descentAngle = horizontalSpeed <= 0
        ? 90.0
        : math.atan2(-landVelocity.y, horizontalSpeed) * _radToDeg;

    final ground = _simulateGround(
      position: landPosition,
      velocity: landVelocity,
      spin: landSpin,
      startTime: landTime,
      groundAt: groundAt,
    );

    var groundPoints = ground.points;
    var rest = ground.rest;

    // Honour a device-measured roll by scaling the simulated ground path.
    if (measuredRollYds != null) {
      final simulatedRoll = (rest.z - landPosition.z) * _mToYd;
      final scale = simulatedRoll.abs() < 0.05
          ? 0.0
          : (measuredRollYds / simulatedRoll).clamp(-5.0, 5.0);
      groundPoints = [
        for (final p in groundPoints)
          TrajectoryPoint(
            t: p.t,
            x: offline + (p.x - offline) * scale,
            y: p.y * scale.abs().clamp(0.0, 1.0),
            z: carry + (p.z - carry) * scale,
            speed: p.speed,
          ),
      ];
      rest = Vec3(
        landPosition.x + (rest.x - landPosition.x) * scale,
        0,
        landPosition.z + (rest.z - landPosition.z) * scale,
      );
    }

    final restYards = Vec3(rest.x * _mToYd, 0, rest.z * _mToYd);

    return ShotTrajectory(
      points: points,
      groundPoints: groundPoints,
      carry: carry,
      apex: apex * _mToYd,
      apexDistance: apexDistance * _mToYd,
      flightTime: landTime,
      groundTime: ground.duration,
      descentAngle: descentAngle,
      landingSpeed: landVelocity.length * _mpsToMph,
      landingSpin: landSpin.length * _radPerSecToRpm,
      offline: offline,
      // Curve: how far the ball finished from the line it started out on.
      curve: offline - carry * math.tan(phi),
      roll: restYards.z - carry,
      restPosition: restYards,
      bounces: ground.bounces,
    );
  }

  // ── Airborne ───────────────────────────────────────────────────────────────

  TrajectoryPoint _toPoint(double t, Vec3 p, Vec3 v) => TrajectoryPoint(
        t: t,
        x: p.x * _mToYd,
        y: p.y * _mToYd,
        z: p.z * _mToYd,
        speed: v.length * _mpsToMph,
      );

  /// Classic RK4 over the coupled position/velocity state. Spin is held
  /// constant across the step; it decays two orders of magnitude more slowly
  /// than the step size.
  (Vec3, Vec3) _rk4Step(Vec3 p, Vec3 v, Vec3 spin) {
    final h = stepSeconds;

    final k1v = _acceleration(v, spin);
    final k2v = _acceleration(v + k1v * (h / 2), spin);
    final k3v = _acceleration(v + k2v * (h / 2), spin);
    final k4v = _acceleration(v + k3v * h, spin);

    final k1p = v;
    final k2p = v + k1v * (h / 2);
    final k3p = v + k2v * (h / 2);
    final k4p = v + k3v * h;

    return (
      p + (k1p + k2p * 2 + k3p * 2 + k4p) * (h / 6),
      v + (k1v + k2v * 2 + k3v * 2 + k4v) * (h / 6),
    );
  }

  /// Gravity + drag + Magnus, in m/s².
  Vec3 _acceleration(Vec3 velocity, Vec3 spin) {
    final speed = velocity.length;
    if (speed < 1e-6) return const Vec3(0, -_gravity, 0);

    final spinRatio = spin.length * _ballRadiusM / speed;
    final cd = dragCoefficient(spinRatio, speed);
    final cl = liftCoefficient(spinRatio);

    final vHat = velocity * (1 / speed);
    final drag = vHat * (-_forceFactor * cd * speed * speed);
    final magnus =
        spin.normalized.cross(vHat) * (_forceFactor * cl * speed * speed);

    return drag + magnus + const Vec3(0, -_gravity, 0);
  }

  /// Unit spin-axis vector for the given launch direction and axis tilt.
  ///
  /// Pure backspin is perpendicular to both the velocity and vertical; a
  /// positive [spinAxisDeg] rotates that vector about the velocity so the
  /// Magnus force tips to the right.
  static Vec3 _spinAxisVector(Vec3 vHat, double spinAxisDeg) {
    var backspinAxis = vHat.cross(Vec3.up);
    if (backspinAxis.length < 1e-6) {
      // Straight up: any perpendicular axis will do.
      backspinAxis = const Vec3(-1, 0, 0);
    }
    backspinAxis = backspinAxis.normalized;

    // Rodrigues rotation about vHat by -spinAxis. The axis is perpendicular to
    // vHat, so the (n·k) term vanishes.
    final a = spinAxisDeg * _degToRad;
    return (backspinAxis * math.cos(a) - vHat.cross(backspinAxis) * math.sin(a))
        .normalized;
  }

  // ── Ground ─────────────────────────────────────────────────────────────────

  /// Bounce and roll from touchdown to rest.
  ///
  /// Each impact applies a normal impulse from [restitution] and a tangential
  /// friction impulse limited by the turf's friction. The tangential impulse is
  /// what makes spin matter on the ground: the contact patch of a backspinning
  /// ball is racing forwards, so friction acts backwards, killing forward speed
  /// and the spin with it — a steep, high-spin wedge checks, and can walk
  /// backwards. A ball with sidespin gets kicked sideways the same way.
  _GroundResult _simulateGround({
    required Vec3 position,
    required Vec3 velocity,
    required Vec3 spin,
    required double startTime,
    GroundModel Function(double xYards, double zYards)? groundAt,
  }) {
    /// Turf under the ball right now. Resolved per contact, not once at
    /// landing, so crossing from fairway onto a green changes the behaviour
    /// mid-roll.
    GroundModel turfAt(Vec3 p) =>
        groundAt?.call(p.x * _mToYd, p.z * _mToYd) ?? ground;

    var p = position;
    var v = velocity;
    var w = spin;
    var t = startTime;
    var bounces = 0;
    var airborne = false;

    final samples = <TrajectoryPoint>[];
    void sample() => samples.add(_toPoint(t, p, v));

    // The arrival itself is the first bounce.
    final firstImpact = _bounce(v, w, turfAt(p));
    v = firstImpact.$1;
    w = firstImpact.$2;
    bounces = 1;
    if (v.y > _minBounceSpeedMps) {
      airborne = true;
    } else {
      v = Vec3(v.x, 0, v.z);
    }
    sample();

    final h = stepSeconds;
    final spinDecayPerStep = math.exp(-h / spinDecaySeconds);
    final maxSteps = (_maxGroundSeconds / h).round();
    // ~25 Hz is plenty for a bounce path.
    const sampleEvery = 8;

    for (var step = 1; step <= maxSteps; step++) {
      if (airborne) {
        final previousY = p.y;
        final next = _rk4Step(p, v, w);
        p = next.$1;
        v = next.$2;
        w = w * spinDecayPerStep;
        t += h;

        if (p.y <= 0) {
          // Land on the plane, then bounce.
          final drop = previousY - p.y;
          final frac = drop.abs() < 1e-9 ? 1.0 : (previousY / drop).clamp(0.0, 1.0);
          p = Vec3(p.x, 0, p.z);
          t -= h * (1 - frac);
          final impact = _bounce(v, w, turfAt(p));
          v = impact.$1;
          w = impact.$2;
          bounces++;
          if (v.y <= _minBounceSpeedMps || bounces >= _maxBounces) {
            airborne = false;
            v = Vec3(v.x, 0, v.z);
          }
          sample();
          continue;
        }
      } else {
        final rolling = _groundStep(v, w, h, turfAt(p));
        v = rolling.$1;
        w = rolling.$2;
        p = Vec3(p.x + v.x * h, 0, p.z + v.z * h);
        t += h;

        final contact = _contactVelocity(v, w);
        if (v.length < _restSpeedMps && contact.length < 3 * _restSpeedMps) {
          break;
        }
      }

      if (step % sampleEvery == 0) sample();
    }

    sample();

    return _GroundResult(
      points: samples,
      rest: Vec3(p.x, 0, p.z),
      duration: t - startTime,
      bounces: bounces,
    );
  }

  /// Velocity of the ball's contact patch relative to the ground.
  ///
  /// Backspin drives it forwards, topspin backwards; sidespin drives it
  /// sideways. Friction always opposes it.
  static Vec3 _contactVelocity(Vec3 v, Vec3 spin) {
    final tangential = Vec3(v.x, 0, v.z);
    return tangential - spin.cross(Vec3.up) * _ballRadiusM;
  }

  /// Impulse-based bounce. Returns the post-impact velocity and spin.
  (Vec3, Vec3) _bounce(Vec3 v, Vec3 spin, GroundModel turf) {
    final normalSpeed = v.y.abs();
    final e = restitution(normalSpeed, turf);

    final contact = _contactVelocity(v, spin);
    final contactSpeed = contact.length;
    if (contactSpeed < 1e-6) {
      return (Vec3(v.x, normalSpeed * e, v.z), spin);
    }
    final contactDir = contact * (1 / contactSpeed);

    // Impulse per unit mass: enough to stop the contact patch slipping, capped
    // by what friction can deliver against the normal impulse.
    final gripImpulse = (2.0 / 7.0) * contactSpeed;
    final frictionLimit = turf.slidingFriction * (1 + e) * normalSpeed;
    final j = math.min(gripImpulse, frictionLimit);

    // Ploughing: the crater wall shoves back along the ground track, harder
    // the steeper the arrival. Capped so a bounce can stop the ball but never
    // fling it backwards on its own.
    final tangential = Vec3(v.x, 0, v.z);
    final tangentialSpeed = tangential.length;
    var slowed = Vec3(v.x - j * contactDir.x, 0, v.z - j * contactDir.z);
    if (tangentialSpeed > 1e-6) {
      // Loss grows with how steeply the ball arrives, but is capped as a
      // fraction of the speed it has. Expressing it that way keeps the model
      // self-similar over a bounce sequence: a bouncier surface cannot end up
      // killing the ball dead on its fourth, gentlest hop.
      final dig = math.min(
        turf.ploughing * normalSpeed,
        _maxPloughFraction * tangentialSpeed,
      );
      final track = tangential * (1 / tangentialSpeed);
      slowed = slowed - track * dig;
    }

    final newVelocity = Vec3(slowed.x, normalSpeed * e, slowed.z);
    // Δω = 5j/(2r) · (n̂ × û) — the same impulse spins the ball down.
    final newSpin =
        spin + Vec3.up.cross(contactDir) * (5 * j / (2 * _ballRadiusM));

    return (newVelocity, newSpin);
  }

  /// One step of ground contact: sliding friction while the contact patch
  /// slips, rolling resistance once it grips.
  (Vec3, Vec3) _groundStep(Vec3 v, Vec3 spin, double h, GroundModel turf) {
    final contact = _contactVelocity(v, spin);
    final contactSpeed = contact.length;

    if (contactSpeed > _slipEpsilonMps) {
      final dir = contact * (1 / contactSpeed);
      final decel = turf.slidingFriction * _gravity * h;
      // Don't overshoot past the no-slip condition inside one step.
      final maxImpulse = (2.0 / 7.0) * contactSpeed;
      final j = math.min(decel, maxImpulse);
      return (
        Vec3(v.x - j * dir.x, 0, v.z - j * dir.z),
        spin + Vec3.up.cross(dir) * (5 * j / (2 * _ballRadiusM)),
      );
    }

    // Rolling without slipping: rolling resistance only, spin tracks speed.
    final speed = math.sqrt(v.x * v.x + v.z * v.z);
    if (speed < 1e-6) return (Vec3.zero, Vec3.zero);
    final decel = math.min(turf.rollingResistance * _gravity * h, speed);
    final rolled = Vec3(
      v.x - decel * v.x / speed,
      0,
      v.z - decel * v.z / speed,
    );
    return (rolled, Vec3.up.cross(rolled) * (1 / _ballRadiusM));
  }
}

class _GroundResult {
  final List<TrajectoryPoint> points;
  final Vec3 rest;
  final double duration;
  final int bounces;

  const _GroundResult({
    required this.points,
    required this.rest,
    required this.duration,
    required this.bounces,
  });
}
