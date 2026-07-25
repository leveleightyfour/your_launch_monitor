import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Camera positions offered by the view chips.
enum FlightCamera {
  behind('Behind', Icons.arrow_upward),
  side('Side', Icons.arrow_forward),
  angled('Angled', Icons.filter_hdr),
  top('Top', Icons.vertical_align_top),
  follow('Follow', Icons.videocam);

  final String label;
  final IconData icon;

  const FlightCamera(this.label, this.icon);
}

/// A 3D ball-flight view: the shot's simulated trajectory drawn over a range,
/// with an orbiting camera and a shot replay.
///
/// The Omni only measures launch conditions, so the flight itself comes from
/// [ShotData.trajectory] — the same simulation that feeds the carry and
/// dispersion numbers elsewhere in the app.
class Flight3DTab extends ConsumerStatefulWidget {
  /// Shots in the current club filter, newest first.
  final List<ShotData> shots;

  /// Shot to render. Falls back to the newest shot in [shots].
  final ShotData? selectedShot;

  final List<Club> clubs;

  const Flight3DTab({
    super.key,
    required this.shots,
    this.selectedShot,
    this.clubs = const [],
  });

  @override
  ConsumerState<Flight3DTab> createState() => _Flight3DTabState();
}

class _Flight3DTabState extends ConsumerState<Flight3DTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _replay;

  FlightCamera _camera = FlightCamera.behind;

  // Orbit state, in radians. Yaw 0 looks straight down the target line from
  // behind the ball; pitch raises the camera above the ground.
  double _yaw = 0;
  double _pitch = 0.24;
  double _zoom = 1.0;

  // Gesture anchors.
  double _gestureYaw = 0;
  double _gesturePitch = 0;
  double _gestureZoom = 1;
  Offset _gestureFocal = Offset.zero;

  bool _showTrails = false;

  ShotData? _lastAnimatedShot;

  static const _minPitch = -0.10;
  static const _maxPitch = 1.40;
  static const _minZoom = 0.35;
  static const _maxZoom = 3.0;

  @override
  void initState() {
    super.initState();
    _replay = AnimationController(vsync: this, duration: _replayDuration());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shot != null) _play();
    });
  }

  @override
  void didUpdateWidget(Flight3DTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shot = _shot;
    if (shot != null && !_isSameShot(shot, _lastAnimatedShot)) _play();
  }

  @override
  void dispose() {
    _replay.dispose();
    super.dispose();
  }

  ShotData? get _shot =>
      widget.selectedShot ?? (widget.shots.isEmpty ? null : widget.shots.first);

  /// Shot rows are rebuilt when tags change, so identity alone would restart
  /// the replay for no reason.
  static bool _isSameShot(ShotData? a, ShotData? b) {
    if (a == null || b == null) return a == b;
    if (identical(a, b)) return true;
    return a.dbId != null && a.dbId == b.dbId;
  }

  Duration _replayDuration() {
    final flight = _shot?.trajectory.flightTime ?? 3.0;
    // Slightly slower than real time reads better on a small screen.
    final seconds = (flight * 1.15).clamp(1.2, 6.0);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  void _play() {
    _lastAnimatedShot = _shot;
    _replay
      ..duration = _replayDuration()
      ..forward(from: 0);
  }

  void _applyPreset(FlightCamera preset) {
    setState(() {
      _camera = preset;
      _zoom = 1.0;
      switch (preset) {
        case FlightCamera.behind:
          _yaw = 0;
          _pitch = 0.24;
        case FlightCamera.side:
          // Positive yaw puts the camera left of the target line, so the ball
          // flies away to the right.
          _yaw = math.pi / 2;
          _pitch = 0.10;
        case FlightCamera.angled:
          _yaw = 0.42;
          _pitch = 0.55;
        case FlightCamera.top:
          _yaw = 0;
          _pitch = _maxPitch;
        case FlightCamera.follow:
          _yaw = 0;
          _pitch = 0.22;
      }
    });
  }

  Club? _clubFor(ShotData shot) {
    for (final club in widget.clubs) {
      if (club.id == shot.clubId) return club;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(unitPrefsProvider);
    final shot = _shot;

    if (shot == null) {
      return Center(
        child: Text(
          'Hit a shot to see it in 3D',
          style: AppTextStyles.sans(color: AppColors.textMuted),
        ),
      );
    }

    final trajectory = shot.trajectory;
    if (trajectory.isEmpty) {
      return Center(
        child: Text(
          'Not enough launch data to model this flight',
          style: AppTextStyles.sans(color: AppColors.textMuted),
        ),
      );
    }

    final shotColor = _clubFor(shot)?.color ?? context.accent;

    final ghosts = _showTrails
        ? widget.shots
            .where((s) => !_isSameShot(s, shot) && s.clubId == shot.clubId)
            .take(12)
            .map((s) => s.trajectory)
            .where((t) => !t.isEmpty)
            .toList()
        : const <ShotTrajectory>[];

    return Column(
      children: [
        _FlightStatBar(shot: shot, trajectory: trajectory, prefs: prefs),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => _applyPreset(_camera),
                  onScaleStart: (details) {
                    _gestureYaw = _yaw;
                    _gesturePitch = _pitch;
                    _gestureZoom = _zoom;
                    _gestureFocal = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      if (details.pointerCount > 1 && details.scale != 1.0) {
                        _zoom = (_gestureZoom / details.scale)
                            .clamp(_minZoom, _maxZoom);
                      }
                      final delta = details.localFocalPoint - _gestureFocal;
                      _yaw = _gestureYaw + delta.dx * 0.006;
                      _pitch = (_gesturePitch + delta.dy * 0.005)
                          .clamp(_minPitch, _maxPitch);
                    });
                  },
                  child: AnimatedBuilder(
                    animation: _replay,
                    builder: (context, _) => CustomPaint(
                      painter: _FlightPainter(
                        trajectory: trajectory,
                        ghosts: ghosts,
                        progress: _replay.value,
                        yaw: _yaw,
                        pitch: _pitch,
                        zoom: _zoom,
                        follow: _camera == FlightCamera.follow,
                        shotColor: shotColor,
                        accent: context.accent,
                        prefs: prefs,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(
                  children: [
                    Expanded(child: _cameraChips()),
                    const SizedBox(width: 8),
                    _RoundAction(
                      icon: _showTrails ? Icons.layers : Icons.layers_outlined,
                      active: _showTrails,
                      tooltip: 'Previous shots with this club',
                      onTap: () => setState(() => _showTrails = !_showTrails),
                    ),
                    const SizedBox(width: 8),
                    _RoundAction(
                      icon: Icons.replay,
                      active: false,
                      tooltip: 'Replay',
                      onTap: _play,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cameraChips() {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FlightCamera.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final preset = FlightCamera.values[i];
          final active = preset == _camera;
          return GestureDetector(
            onTap: () => _applyPreset(preset),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? context.accentSubtle : AppColors.card,
                border: Border.all(
                  color: active ? context.accent : AppColors.border2,
                  width: active ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    preset.icon,
                    size: 12,
                    color: active ? context.accent : AppColors.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    preset.label,
                    style: AppTextStyles.sans(
                      size: 11,
                      weight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? context.accent : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Stat bar ─────────────────────────────────────────────────────────────────

class _FlightStatBar extends StatelessWidget {
  final ShotData shot;
  final ShotTrajectory trajectory;
  final UnitPrefs prefs;

  const _FlightStatBar({
    required this.shot,
    required this.trajectory,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    String side(double yards) {
      final v = prefs.dist(yards);
      if (v.abs() < 0.05) return '0.0';
      return '${v.abs().toStringAsFixed(1)}${v < 0 ? 'L' : 'R'}';
    }

    final stats = <(String, String, String)>[
      ('Carry', prefs.dist(trajectory.carry).toStringAsFixed(1),
          prefs.distLabel),
      ('Total', prefs.dist(shot.totalDistance).toStringAsFixed(1),
          prefs.distLabel),
      ('Apex', prefs.dist(shot.apexHeight).toStringAsFixed(1), prefs.distLabel),
      ('Descent', trajectory.descentAngle.toStringAsFixed(1), '°'),
      ('Side', side(trajectory.offline), prefs.distLabel),
      ('Curve', side(trajectory.curve), prefs.distLabel),
    ];

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          for (final (label, value, unit) in stats)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: AppTextStyles.sans(
                      size: 10,
                      color: AppColors.textDimmed,
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(value, style: AppTextStyles.mono(size: 18)),
                        const SizedBox(width: 2),
                        Text(
                          unit,
                          style: AppTextStyles.sans(
                            size: 9,
                            color: AppColors.textDimmed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Round action button ──────────────────────────────────────────────────────

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active ? context.accentSubtle : AppColors.card,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? context.accent : AppColors.border2,
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: active ? context.accent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Camera ───────────────────────────────────────────────────────────────────

/// Pinhole camera with a near plane — enough to project the flight and the
/// ground grid without pulling in a 3D engine.
class _Camera {
  final Vec3 position;
  final Vec3 right;
  final Vec3 up;
  final Vec3 forward;
  final double focal;
  final Offset centre;

  static const double near = 1.0;

  const _Camera._({
    required this.position,
    required this.right,
    required this.up,
    required this.forward,
    required this.focal,
    required this.centre,
  });

  factory _Camera.orbit({
    required Vec3 focus,
    required double yaw,
    required double pitch,
    required double distance,
    required Size size,
    Offset? principalPoint,
    double fovDegrees = 52,
  }) {
    final offset = Vec3(
      math.sin(yaw) * math.cos(pitch),
      math.sin(pitch),
      -math.cos(yaw) * math.cos(pitch),
    );
    final position = focus + offset * distance;
    final forward = (focus - position).normalized;
    const worldUp = Vec3(0, 1, 0);
    var right = worldUp.cross(forward);
    if (right.length < 1e-5) right = const Vec3(1, 0, 0);
    right = right.normalized;
    final up = forward.cross(right).normalized;

    return _Camera._(
      position: position,
      right: right,
      up: up,
      forward: forward,
      focal: size.height / (2 * math.tan(fovDegrees * math.pi / 360.0)),
      centre: principalPoint ?? Offset(size.width / 2, size.height / 2),
    );
  }

  /// World point → camera space (x right, y up, z into the screen).
  Vec3 toCamera(Vec3 world) {
    final d = world - position;
    return Vec3(d.dot(right), d.dot(up), d.dot(forward));
  }

  /// Camera-space point → screen. Only valid for points with `z >= near`.
  Offset toScreen(Vec3 cam) => Offset(
        centre.dx + focal * cam.x / cam.z,
        centre.dy - focal * cam.y / cam.z,
      );

  /// Project a world point, or null when it sits behind the near plane.
  Offset? project(Vec3 world) {
    final cam = toCamera(world);
    if (cam.z < near) return null;
    return toScreen(cam);
  }

  double depthOf(Vec3 world) => toCamera(world).z;
}

/// Clip a camera-space segment against the near plane. Null when the whole
/// segment sits behind the camera.
(Vec3, Vec3)? _clipSegment(Vec3 a, Vec3 b) {
  const near = _Camera.near;
  final aIn = a.z >= near;
  final bIn = b.z >= near;
  if (!aIn && !bIn) return null;
  if (aIn && bIn) return (a, b);
  final t = (near - a.z) / (b.z - a.z);
  final crossing = a + (b - a) * t;
  return aIn ? (a, crossing) : (crossing, b);
}

/// Sutherland–Hodgman clip of a camera-space polygon against the near plane.
List<Vec3> _clipPolygon(List<Vec3> poly) {
  const near = _Camera.near;
  if (poly.isEmpty) return const [];
  final out = <Vec3>[];
  for (var i = 0; i < poly.length; i++) {
    final current = poly[i];
    final previous = poly[(i - 1 + poly.length) % poly.length];
    final currentIn = current.z >= near;
    final previousIn = previous.z >= near;
    if (currentIn != previousIn) {
      final t = (near - previous.z) / (current.z - previous.z);
      out.add(previous + (current - previous) * t);
    }
    if (currentIn) out.add(current);
  }
  return out;
}

// ── Painter ──────────────────────────────────────────────────────────────────

class _FlightPainter extends CustomPainter {
  final ShotTrajectory trajectory;
  final List<ShotTrajectory> ghosts;
  final double progress;
  final double yaw;
  final double pitch;
  final double zoom;
  final bool follow;
  final Color shotColor;
  final Color accent;
  final UnitPrefs prefs;

  _FlightPainter({
    required this.trajectory,
    required this.ghosts,
    required this.progress,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.follow,
    required this.shotColor,
    required this.accent,
    required this.prefs,
  });

  static const _groundColor = Color(0xFF101619);
  static const _fairwayColor = Color(0xFF13201A);
  static const _gridColor = Color(0xFF2A3A38);
  static const _skyBottom = Color(0xFF0E1418);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || trajectory.isEmpty) return;

    final rest = trajectory.restPosition;
    final range = math.max(trajectory.totalDistance, 40.0);
    final ball = _ballPosition();

    // Grid spacing follows the display unit so the labels stay round numbers.
    final gridStep = prefs.distance == DistanceUnit.meters ? 25 / 0.9144 : 25.0;
    final halfWidth = math.max(
      math.max(rest.x.abs() + 2 * gridStep, 3 * gridStep),
      range * 0.3,
    );
    final maxDepth = range + 2 * gridStep;

    final _Camera camera;
    if (follow) {
      final heading = math.atan2(rest.x, math.max(rest.z, 1));
      camera = _Camera.orbit(
        focus: Vec3(ball.x, ball.y + 3, ball.z),
        yaw: yaw + heading,
        pitch: pitch,
        distance: (55.0 + trajectory.apex * 0.6) * zoom,
        size: size,
      );
    } else {
      camera = _fitCamera(size, rest);
    }

    _paintBackdrop(canvas, size);
    _paintGround(canvas, camera, halfWidth, maxDepth, gridStep);
    _paintDistanceLabels(canvas, camera, gridStep, maxDepth, halfWidth);

    for (final ghost in ghosts) {
      final path = _pathFor(camera, ghost.points, ghost.points.length - 1);
      if (path != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = shotColor.withAlpha(50)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
      }
    }

    if (progress >= 0.999) _paintLanding(canvas, camera);

    final upTo = _visibleSegments(trajectory.points, progress);
    _paintCurtain(canvas, camera, upTo);
    _paintShadow(canvas, camera, upTo);
    _paintFlightPath(canvas, camera, upTo);
    _paintApexMarker(canvas, camera, ball);
    _paintBall(canvas, camera, ball);
  }

  // ── Framing ────────────────────────────────────────────────────────────────

  /// Points the camera has to keep on screen: the flight itself plus where the
  /// ball comes to rest.
  List<Vec3> _framingPoints(Vec3 rest) {
    final points = trajectory.points;
    final stride = math.max(1, points.length ~/ 24);
    return [
      Vec3.zero,
      for (var i = 0; i < points.length; i += stride)
        Vec3(points[i].x, points[i].y, points[i].z),
      Vec3(points.last.x, points.last.y, points.last.z),
      rest,
    ];
  }

  /// Pull the camera back until the whole shot fits, whatever the orbit angle.
  ///
  /// Overflow shrinks monotonically as the camera retreats, so a bisection
  /// finds the closest distance that still frames the shot. (Scaling the
  /// distance by the overflow directly does not converge: points near the
  /// camera grow far faster than 1/distance.)
  _Camera _fitCamera(Size size, Vec3 rest) {
    final frame = _framingPoints(rest);

    var minX = frame.first.x, maxX = minX;
    var minY = frame.first.y, maxY = minY;
    var minZ = frame.first.z, maxZ = minZ;
    for (final p in frame) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      minZ = math.min(minZ, p.z);
      maxZ = math.max(maxZ, p.z);
    }
    final focus = Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
    final span = Vec3(maxX - minX, maxY - minY, maxZ - minZ).length;

    // Keep content clear of the chip row along the bottom.
    final marginX = size.width * 0.5 * 0.88;
    final marginY = size.height * 0.5 * 0.80;

    final viewportCentre = Offset(size.width / 2, size.height / 2);
    var principal = viewportCentre;

    _Camera cameraAt(double distance) => _Camera.orbit(
          focus: focus,
          yaw: yaw,
          pitch: pitch,
          distance: distance,
          size: size,
          principalPoint: principal,
        );

    /// How far outside the safe frame the worst point sits; ≤ 1 means it fits.
    double overflow(double distance) {
      final camera = cameraAt(distance);
      var worst = 0.0;
      for (final p in frame) {
        final cam = camera.toCamera(p);
        if (cam.z < _Camera.near) return double.infinity;
        final screen = camera.toScreen(cam);
        worst = math.max(worst, (screen.dx - viewportCentre.dx).abs() / marginX);
        worst = math.max(worst, (screen.dy - viewportCentre.dy).abs() / marginY);
      }
      return worst;
    }

    double fitDistance() {
      var near = 12.0;
      var far = math.max(span * 6, 240.0);
      // Guarantee the upper bound frames the shot before bisecting into it.
      for (var i = 0; i < 6 && overflow(far) > 1.0; i++) {
        far *= 2;
      }
      for (var i = 0; i < 22; i++) {
        final mid = (near + far) / 2;
        if (overflow(mid) <= 1.0) {
          far = mid;
        } else {
          near = mid;
        }
      }
      return far;
    }

    // Perspective means the world-space centre of the shot rarely lands in the
    // middle of the screen. Nudge the principal point so the projected shot is
    // centred, then re-fit into the space that frees up.
    final rough = cameraAt(fitDistance());
    var minSx = double.infinity, maxSx = -double.infinity;
    var minSy = double.infinity, maxSy = -double.infinity;
    for (final p in frame) {
      final screen = rough.project(p);
      if (screen == null) continue;
      minSx = math.min(minSx, screen.dx);
      maxSx = math.max(maxSx, screen.dx);
      minSy = math.min(minSy, screen.dy);
      maxSy = math.max(maxSy, screen.dy);
    }
    if (minSx.isFinite) {
      final shift = Offset(
        (viewportCentre.dx - (minSx + maxSx) / 2)
            .clamp(-size.width * 0.3, size.width * 0.3),
        (viewportCentre.dy - (minSy + maxSy) / 2)
            .clamp(-size.height * 0.3, size.height * 0.3),
      );
      principal = viewportCentre + shift;
    }

    return cameraAt(math.max(fitDistance() * zoom, 12.0));
  }

  // ── Geometry helpers ───────────────────────────────────────────────────────

  static int _visibleSegments(List<TrajectoryPoint> points, double progress) =>
      (progress * (points.length - 1)).ceil().clamp(1, points.length - 1);

  Vec3 _ballPosition() {
    final points = trajectory.points;
    if (points.isEmpty) return Vec3.zero;
    final scaled = (progress.clamp(0.0, 1.0)) * (points.length - 1);
    final i = scaled.floor().clamp(0, points.length - 1);
    final j = math.min(i + 1, points.length - 1);
    final t = scaled - i;
    final a = points[i];
    final b = points[j];
    return Vec3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }

  /// Build a screen-space polyline for the first [upTo] segments, splitting
  /// into subpaths wherever the line crosses behind the camera.
  Path? _pathFor(
    _Camera camera,
    List<TrajectoryPoint> points,
    int upTo, {
    bool flatten = false,
  }) {
    if (points.length < 2 || upTo < 1) return null;
    final path = Path();
    var open = false;
    Offset? lastEnd;

    for (var i = 0; i < upTo; i++) {
      final a = Vec3(points[i].x, flatten ? 0 : points[i].y, points[i].z);
      final b =
          Vec3(points[i + 1].x, flatten ? 0 : points[i + 1].y, points[i + 1].z);
      final clipped = _clipSegment(camera.toCamera(a), camera.toCamera(b));
      if (clipped == null) {
        open = false;
        continue;
      }
      final start = camera.toScreen(clipped.$1);
      final end = camera.toScreen(clipped.$2);
      if (!open || lastEnd != start) {
        path.moveTo(start.dx, start.dy);
        open = true;
      }
      path.lineTo(end.dx, end.dy);
      lastEnd = end;
    }
    return open || lastEnd != null ? path : null;
  }

  void _line3(Canvas canvas, _Camera camera, Vec3 a, Vec3 b, Paint paint) {
    final clipped = _clipSegment(camera.toCamera(a), camera.toCamera(b));
    if (clipped == null) return;
    canvas.drawLine(
      camera.toScreen(clipped.$1),
      camera.toScreen(clipped.$2),
      paint,
    );
  }

  void _polygon3(Canvas canvas, _Camera camera, List<Vec3> world, Paint paint) {
    final clipped = _clipPolygon([for (final w in world) camera.toCamera(w)]);
    if (clipped.length < 3) return;
    final path = Path();
    final first = camera.toScreen(clipped.first);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < clipped.length; i++) {
      final p = camera.toScreen(clipped[i]);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // ── Scene ──────────────────────────────────────────────────────────────────

  void _paintBackdrop(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [AppColors.background, _skyBottom],
        ),
    );
  }

  void _paintGround(
    Canvas canvas,
    _Camera camera,
    double halfWidth,
    double maxDepth,
    double gridStep,
  ) {
    const behind = -25.0;

    // The ground runs well past the shot so the far edge reads as a horizon
    // rather than as the end of a floating platform.
    final outerWidth = halfWidth * 5;
    final outerDepth = maxDepth * 3;
    _polygon3(
      canvas,
      camera,
      [
        Vec3(-outerWidth, 0, -outerDepth),
        Vec3(outerWidth, 0, -outerDepth),
        Vec3(outerWidth, 0, outerDepth),
        Vec3(-outerWidth, 0, outerDepth),
      ],
      Paint()..color = _groundColor,
    );

    // Fairway strip down the target line.
    final fairwayHalf = math.min(halfWidth * 0.5, 30.0);
    _polygon3(
      canvas,
      camera,
      [
        Vec3(-fairwayHalf, 0, behind),
        Vec3(fairwayHalf, 0, behind),
        Vec3(fairwayHalf, 0, maxDepth),
        Vec3(-fairwayHalf, 0, maxDepth),
      ],
      Paint()..color = _fairwayColor,
    );

    // Cross lines — faded with distance so the horizon doesn't turn solid.
    for (var z = 0.0; z <= maxDepth; z += gridStep) {
      final fade =
          (1 - camera.depthOf(Vec3(0, 0, z)) / (maxDepth * 1.6)).clamp(0.12, 1.0);
      _line3(
        canvas,
        camera,
        Vec3(-halfWidth, 0, z),
        Vec3(halfWidth, 0, z),
        Paint()
          ..color = _gridColor.withAlpha((150 * fade).round())
          ..strokeWidth = 1,
      );
    }

    // Lines running downrange, on the same lattice as the cross lines.
    final columns = (halfWidth / gridStep).ceil();
    for (var i = -columns; i <= columns; i++) {
      _line3(
        canvas,
        camera,
        Vec3(i * gridStep, 0, behind),
        Vec3(i * gridStep, 0, maxDepth),
        Paint()
          ..color = _gridColor.withAlpha(70)
          ..strokeWidth = 1,
      );
    }

    // Target line.
    _line3(
      canvas,
      camera,
      const Vec3(0, 0, behind),
      Vec3(0, 0, maxDepth),
      Paint()
        ..color = accent.withAlpha(90)
        ..strokeWidth = 1.4,
    );
  }

  void _paintDistanceLabels(
    Canvas canvas,
    _Camera camera,
    double gridStep,
    double maxDepth,
    double halfWidth,
  ) {
    final labelStep = gridStep * 2;
    for (var z = labelStep; z <= maxDepth; z += labelStep) {
      final at = camera.project(Vec3(-halfWidth * 0.9, 0, z));
      if (at == null) continue;
      _label(
        canvas,
        prefs.dist(z).round().toString(),
        at,
        AppTextStyles.mono(size: 9, color: AppColors.textDimmed),
      );
    }
  }

  void _paintCurtain(Canvas canvas, _Camera camera, int upTo) {
    final points = trajectory.points;
    final sheet = Path();
    for (var i = 0; i < upTo; i++) {
      final quad = _clipPolygon([
        camera.toCamera(Vec3(points[i].x, points[i].y, points[i].z)),
        camera.toCamera(
            Vec3(points[i + 1].x, points[i + 1].y, points[i + 1].z)),
        camera.toCamera(Vec3(points[i + 1].x, 0, points[i + 1].z)),
        camera.toCamera(Vec3(points[i].x, 0, points[i].z)),
      ]);
      if (quad.length < 3) continue;
      sheet.addPolygon([for (final c in quad) camera.toScreen(c)], true);
    }
    canvas.drawPath(sheet, Paint()..color = shotColor.withAlpha(16));
  }

  void _paintShadow(Canvas canvas, _Camera camera, int upTo) {
    final path = _pathFor(camera, trajectory.points, upTo, flatten: true);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintFlightPath(Canvas canvas, _Camera camera, int upTo) {
    final path = _pathFor(camera, trajectory.points, upTo);
    if (path == null) return;

    canvas.drawPath(
      path,
      Paint()
        ..color = shotColor.withAlpha(90)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Height reads as a vertical gradient: brighter the higher the ball is.
    final bounds = path.getBounds();
    final linePaint = Paint()
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (bounds.height > 1) {
      linePaint.shader = ui.Gradient.linear(
        Offset(bounds.center.dx, bounds.top),
        Offset(bounds.center.dx, bounds.bottom),
        [Color.lerp(shotColor, Colors.white, 0.55) ?? shotColor, shotColor],
      );
    } else {
      linePaint.color = shotColor;
    }
    canvas.drawPath(path, linePaint);
  }

  void _paintApexMarker(Canvas canvas, _Camera camera, Vec3 ball) {
    final apexPoint = _apexPoint();
    if (apexPoint == null) return;
    // Don't label the apex before the ball has reached it.
    if (ball.z < apexPoint.z) return;

    final top = camera.project(apexPoint);
    if (top == null) return;

    _line3(
      canvas,
      camera,
      apexPoint,
      Vec3(apexPoint.x, 0, apexPoint.z),
      Paint()
        ..color = Colors.white.withAlpha(40)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(top, 2.5, Paint()..color = Colors.white.withAlpha(170));
    _label(
      canvas,
      'APEX ${prefs.dist(trajectory.apex).toStringAsFixed(0)} ${prefs.distLabel}',
      top.translate(0, -12),
      AppTextStyles.mono(size: 9, color: Colors.white.withAlpha(190)),
    );
  }

  Vec3? _apexPoint() {
    final points = trajectory.points;
    if (points.isEmpty) return null;
    var best = points.first;
    for (final p in points) {
      if (p.y > best.y) best = p;
    }
    return Vec3(best.x, best.y, best.z);
  }

  void _paintLanding(Canvas canvas, _Camera camera) {
    final landing = Vec3(trajectory.offline, 0, trajectory.carry);
    final rest = trajectory.restPosition;

    for (final radius in const [2.0, 5.0]) {
      final ring = <Vec3>[
        for (var a = 0; a < 32; a++)
          Vec3(
            landing.x + radius * math.cos(a * math.pi / 16),
            0,
            landing.z + radius * math.sin(a * math.pi / 16),
          ),
      ];
      final paint = Paint()
        ..color = accent.withAlpha(radius > 3 ? 70 : 150)
        ..strokeWidth = 1.4;
      for (var i = 0; i < ring.length; i++) {
        _line3(canvas, camera, ring[i], ring[(i + 1) % ring.length], paint);
      }
    }

    if (trajectory.roll > 0.5) {
      _dashedLine3(canvas, camera, landing, rest, accent.withAlpha(120));
      final at = camera.project(rest);
      if (at != null) canvas.drawCircle(at, 3, Paint()..color = Colors.white);
    }

    final label = camera.project(landing);
    if (label != null) {
      _label(
        canvas,
        '${prefs.dist(trajectory.carry).toStringAsFixed(0)} ${prefs.distLabel}',
        label.translate(0, 14),
        AppTextStyles.mono(size: 10, color: accent),
      );
    }
  }

  void _dashedLine3(
    Canvas canvas,
    _Camera camera,
    Vec3 from,
    Vec3 to,
    Color color,
  ) {
    const segments = 12;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    for (var i = 0; i < segments; i += 2) {
      _line3(
        canvas,
        camera,
        from + (to - from) * (i / segments),
        from + (to - from) * ((i + 1) / segments),
        paint,
      );
    }
  }

  void _paintBall(Canvas canvas, _Camera camera, Vec3 ball) {
    final shadowAt = camera.project(Vec3(ball.x, 0, ball.z));
    if (shadowAt != null) {
      // The shadow tightens as the ball comes back down.
      final shrink = (1 - ball.y / math.max(trajectory.apex, 1)) * 0.6 + 0.4;
      canvas.drawOval(
        Rect.fromCenter(
          center: shadowAt,
          width: 9 * shrink,
          height: 4 * shrink,
        ),
        Paint()..color = Colors.black.withAlpha(140),
      );
    }

    final at = camera.project(ball);
    if (at == null) return;
    canvas.drawCircle(
      at,
      9,
      Paint()
        ..color = Colors.white.withAlpha(60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(at, 4, Paint()..color = Colors.white);
  }

  void _label(Canvas canvas, String text, Offset at, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(at.dx - painter.width / 2, at.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FlightPainter old) =>
      old.trajectory != trajectory ||
      old.ghosts.length != ghosts.length ||
      old.progress != progress ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.follow != follow ||
      old.shotColor != shotColor ||
      old.accent != accent ||
      old.prefs != prefs;
}
