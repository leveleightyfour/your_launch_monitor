import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/hole_builder.dart';
import 'package:omni_sniffer/shared/providers/hole_setup_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Camera positions offered by the view chips.
enum FlightCamera {
  behind('Behind', Icons.arrow_upward),
  side('Side', Icons.arrow_forward),
  angled('Angled', Icons.filter_hdr),
  top('Top', Icons.vertical_align_top),
  follow('Follow', Icons.videocam),
  hole('Hole', Icons.golf_course);

  final String label;
  final IconData icon;

  const FlightCamera(this.label, this.icon);
}

/// How much of the view fits: a full tab, one half of a split, or a pane on a
/// phone. Everything that scales — how many stats, chip labels, stroke widths,
/// which annotations survive — keys off this.
enum _Density {
  compact,
  medium,
  full;

  static _Density forSize(Size size) {
    if (size.width >= 560 && size.height >= 400) return _Density.full;
    if (size.width >= 380 && size.height >= 290) return _Density.medium;
    return _Density.compact;
  }

  bool get atLeastMedium => this != _Density.compact;

  /// Scales stroke widths, marker radii and label sizes.
  double get scale => switch (this) {
    _Density.full => 1.0,
    _Density.medium => 0.85,
    _Density.compact => 0.7,
  };
}

/// Width of one mown band, in yards, for a surface that is banded.
///
/// A putting surface is cut far tighter than a fairway, so its bands are
/// narrower as well as fainter.
double mowLaneWidthYards(Terrain terrain) =>
    terrain == Terrain.green ? 2.5 : 5.0;

/// Which of the two alternating bands a point falls in.
///
/// Anchored on the target line, in yards — not on a grid column, and not on
/// the fairway edge.
///
/// Both of those were wrong in ways that only showed once fairways could vary
/// in width. Anchoring at the fairway's own edge moved the whole pattern every
/// time the width changed, so bands jumped at every pinch. Anchoring at grid
/// column zero held still but put the phase wherever the grid's left edge
/// happened to land, so the pattern was not symmetric about the middle of the
/// hole and the two sides of a narrowed fairway disagreed.
///
/// Measuring from x = 0 fixes both: a lane covers the same ground whatever the
/// fairway is doing there, the pattern mirrors about the target line, and it
/// no longer shifts when the cell size changes with the unit preference.
bool isMowBand(double xYards, Terrain terrain) {
  final lane = (xYards / mowLaneWidthYards(terrain)).floor();
  return lane.isEven;
}

/// How long the airborne part of a replay lasts, in seconds.
///
/// Real time — a 6.4 s tour drive takes 6.4 s on screen. The replay used to
/// run 15% slow on the theory that it read better on a phone, which made every
/// club hang noticeably longer than life, and a 7 s ceiling on top of that
/// collapsed driver, 3-wood and 5-iron to the same duration so you could not
/// tell them apart.
///
/// The clamp that remains is a guard against unusable data — a zero flight
/// time from a bad read, or something absurd — and is deliberately wider than
/// any real golf shot, so nothing playable is altered by it.
double airborneReplaySeconds(double? flightTime) =>
    (flightTime ?? 3.0).clamp(0.3, 12.0);

/// Two shot rows describe the same shot.
///
/// Rows are rebuilt when tags change, so identity alone is not enough.
bool isSameShot(ShotData? a, ShotData? b) {
  if (a == null || b == null) return a == b;
  if (identical(a, b)) return true;
  return a.dbId != null && a.dbId == b.dbId;
}

/// Other shots worth drawing alongside [subject]: same club, same target.
///
/// The target has to match exactly. Fairway width and green size change how
/// the ball behaves once it lands, so shots played to different setups did not
/// cover the same ground and overlaying them would compare flights that were
/// never comparable. Shots dropped for that reason are counted so the view can
/// say so rather than quietly showing fewer trails.
({List<ShotData> shown, int hiddenByTarget}) sameTargetTrails(
  List<ShotData> shots,
  ShotData subject, {
  int limit = 12,
}) {
  final sameClub = [
    for (final s in shots)
      if (!isSameShot(s, subject) && s.clubId == subject.clubId) s,
  ];
  final sameTarget = [
    for (final s in sameClub)
      if (s.hole == subject.hole) s,
  ];
  return (
    shown: sameTarget.take(limit).toList(),
    hiddenByTarget: sameClub.length - sameTarget.length,
  );
}

/// A 3D ball-flight view: the shot's simulated trajectory drawn over a range,
/// with an orbiting camera and a replay that runs through to the ball's rest.
///
/// The Omni only measures launch conditions, so the flight, the bounce and the
/// roll all come from [ShotData.trajectory] — the same simulation that feeds
/// the carry and dispersion numbers elsewhere in the app.
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
  double _pitch = 0;
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

  /// The roll-out plays in real time up to this much. Past it the release is
  /// compressed — a ball trickling for eight seconds is not worth the wait.
  static const _maxGroundReplaySeconds = 4.0;

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
    if (shot != null && !isSameShot(shot, _lastAnimatedShot)) _play();
  }

  @override
  void dispose() {
    _replay.dispose();
    super.dispose();
  }

  ShotData? get _shot =>
      widget.selectedShot ?? (widget.shots.isEmpty ? null : widget.shots.first);

  double get _airborneSeconds =>
      airborneReplaySeconds(_shot?.trajectory.flightTime);

  double get _groundSeconds =>
      math.min(_shot?.trajectory.groundTime ?? 0.0, _maxGroundReplaySeconds);

  /// Share of the replay spent in the air, so the painter can split progress
  /// between the flight and the bounce-and-roll.
  double get _flightFraction {
    final total = _airborneSeconds + _groundSeconds;
    return total <= 0 ? 1.0 : _airborneSeconds / total;
  }

  Duration _replayDuration() => Duration(
    milliseconds: ((_airborneSeconds + _groundSeconds) * 1000).round(),
  );

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
          // First person: yaw and pitch are offsets from where a golfer
          // standing at the ball would naturally be looking.
          _yaw = 0;
          _pitch = 0;
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
        case FlightCamera.hole:
          _yaw = 0;
          _pitch = 0.40;
      }
    });
  }

  /// The hole this shot was played to, if any. It comes from the shot rather
  /// than from settings so a saved session renders the hole it was played on.
  HoleSetup? get _hole {
    final hole = _shot?.hole;
    return hole != null && hole.enabled ? hole : null;
  }

  bool get _holeIsSet => _hole != null;

  /// Opens the builder on whatever hole is configured, and keeps what comes
  /// back.
  ///
  /// The configured hole is edited, not the selected shot's. Shots are stamped
  /// with the hole they were played to and stay that way — building a new one
  /// applies to the shots that come next, which is the same rule as moving the
  /// green.
  Future<void> _openHoleBuilder() async {
    final built = await showHoleBuilder(
      context,
      hole: ref.read(holeSetupProvider),
      prefs: ref.read(unitPrefsProvider),
    );
    if (built == null || !mounted) return;
    ref.read(holeSetupProvider.notifier).replace(built);
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
      return _Message(text: 'Hit a shot to see it in 3D');
    }

    final trajectory = shot.trajectory;
    if (trajectory.isEmpty) {
      return _Message(text: 'Not enough launch data to model this flight');
    }

    final shotColor = _clubFor(shot)?.color ?? context.accent;

    final trails = sameTargetTrails(widget.shots, shot);
    final ghosts = _showTrails
        ? [
            for (final s in trails.shown)
              if (!s.trajectory.isEmpty) s.trajectory,
          ]
        : const <ShotTrajectory>[];
    final hiddenTrails = _showTrails ? trails.hiddenByTarget : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final density = _Density.forSize(constraints.biggest);
        return Column(
          children: [
            _FlightStatBar(
              shot: shot,
              trajectory: trajectory,
              prefs: prefs,
              density: density,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildScene(
                      trajectory: trajectory,
                      ghosts: ghosts,
                      shotColor: shotColor,
                      prefs: prefs,
                      density: density,
                      hole: _hole,
                    ),
                  ),
                  if (hiddenTrails > 0)
                    Positioned(
                      left: 12,
                      right: 12,
                      // Clears the control strip, which itself sits 8 up.
                      bottom: _controlStripHeight(density) + 12,
                      child: Text(
                        '$hiddenTrails shot${hiddenTrails == 1 ? '' : 's'} '
                        'hidden — played to a different target',
                        style: AppTextStyles.sans(
                          size: 10,
                          color: AppColors.textDimmed,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _buildControls(density),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScene({
    required ShotTrajectory trajectory,
    required List<ShotTrajectory> ghosts,
    required Color shotColor,
    required UnitPrefs prefs,
    required _Density density,
    required HoleSetup? hole,
  }) {
    return GestureDetector(
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
            _zoom = (_gestureZoom / details.scale).clamp(_minZoom, _maxZoom);
          }
          final delta = details.localFocalPoint - _gestureFocal;
          _yaw = _gestureYaw + delta.dx * 0.006;
          _pitch = (_gesturePitch + delta.dy * 0.005).clamp(
            _minPitch,
            _maxPitch,
          );
        });
      },
      child: AnimatedBuilder(
        animation: _replay,
        builder: (context, _) => CustomPaint(
          painter: _FlightPainter(
            trajectory: trajectory,
            ghosts: ghosts,
            progress: _replay.value,
            flightFraction: _flightFraction,
            yaw: _yaw,
            pitch: _pitch,
            zoom: _zoom,
            follow: _camera == FlightCamera.follow,
            firstPerson: _camera == FlightCamera.behind,
            shotColor: shotColor,
            accent: context.accent,
            prefs: prefs,
            density: density,
            controlStripHeight: _controlStripHeight(density),
            hole: hole,
            frameWholeHole: _camera == FlightCamera.hole,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Picks the scene the flight renders under. Curated pairings rather than
  /// a free colour: every sky ships with turf that keeps the tracer and
  /// markers readable.
  void _pickSky() {
    final current = ref.read(unitPrefsProvider).skyScene;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Sky',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (final choice in SkyScene.values)
            ListTile(
              leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _Scene.of(choice).skyTop,
                      _Scene.of(choice).skyHorizon,
                    ],
                  ),
                ),
              ),
              title: Text(
                choice.label,
                style: AppTextStyles.sans(
                  size: 14,
                  weight: choice == current ? FontWeight.w600 : FontWeight.w400,
                  color: choice == current ? ctx.accent : Colors.white,
                ),
              ),
              trailing: choice == current
                  ? Icon(Icons.check, color: ctx.accent, size: 18)
                  : null,
              onTap: () {
                ref.read(unitPrefsProvider.notifier).setSkyScene(choice);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Chip row height plus its padding — the painter keeps the shot above it.
  static double _controlStripHeight(_Density density) =>
      density == _Density.compact ? 42 : 46;

  Widget _buildControls(_Density density) {
    final buttonSize = density == _Density.compact ? 26.0 : 30.0;
    return Row(
      children: [
        Expanded(child: _cameraChips(density)),
        const SizedBox(width: 6),
        _RoundAction(
          icon: _showTrails ? Icons.layers : Icons.layers_outlined,
          active: _showTrails,
          size: buttonSize,
          tooltip: 'Previous shots with this club',
          onTap: () => setState(() => _showTrails = !_showTrails),
        ),
        const SizedBox(width: 6),
        _RoundAction(
          icon: Icons.filter_hdr,
          active: false,
          size: buttonSize,
          tooltip: 'Sky',
          onTap: _pickSky,
        ),
        const SizedBox(width: 6),
        _RoundAction(
          icon: Icons.golf_course,
          active: _holeIsSet,
          size: buttonSize,
          tooltip: 'Hole builder',
          onTap: _openHoleBuilder,
        ),
        const SizedBox(width: 6),
        _RoundAction(
          icon: Icons.replay,
          active: false,
          size: buttonSize,
          tooltip: 'Replay',
          onTap: _play,
        ),
      ],
    );
  }

  Widget _cameraChips(_Density density) {
    final showLabels = density.atLeastMedium;
    // The Hole view is only meaningful when a hole is configured.
    final presets = [
      for (final p in FlightCamera.values)
        if (p != FlightCamera.hole || _holeIsSet) p,
    ];
    return SizedBox(
      height: density == _Density.compact ? 26 : 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, i) {
          final preset = presets[i];
          final active = preset == _camera;
          final color = active ? context.accent : AppColors.textMuted;
          return Tooltip(
            message: preset.label,
            child: GestureDetector(
              onTap: () => _applyPreset(preset),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: showLabels ? 10 : 7),
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
                    Icon(preset.icon, size: 12, color: color),
                    if (showLabels) ...[
                      const SizedBox(width: 5),
                      Text(
                        preset.label,
                        style: AppTextStyles.sans(
                          size: 11,
                          weight: active ? FontWeight.w600 : FontWeight.w400,
                          color: color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Empty / error state ──────────────────────────────────────────────────────

class _Message extends StatelessWidget {
  final String text;

  const _Message({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.sans(color: AppColors.textMuted),
      ),
    ),
  );
}

// ── Stat bar ─────────────────────────────────────────────────────────────────

class _FlightStatBar extends StatelessWidget {
  final ShotData shot;
  final ShotTrajectory trajectory;
  final UnitPrefs prefs;
  final _Density density;

  const _FlightStatBar({
    required this.shot,
    required this.trajectory,
    required this.prefs,
    required this.density,
  });

  @override
  Widget build(BuildContext context) {
    String side(double yards) {
      final v = prefs.dist(yards);
      if (v.abs() < 0.05) return '0.0';
      return '${v.abs().toStringAsFixed(1)}${v < 0 ? 'L' : 'R'}';
    }

    String dist(double yards) => prefs.dist(yards).toStringAsFixed(1);

    // Ordered by how much a golfer wants them; the tail is dropped as the pane
    // gets smaller.
    final all = <(String, String, String)>[
      ('Carry', dist(trajectory.carry), prefs.distLabel),
      ('Total', dist(shot.totalDistance), prefs.distLabel),
      ('Side', side(shot.lateralOffset), prefs.distLabel),
      ('Apex', dist(shot.apexHeight), prefs.distLabel),
      ('Descent', trajectory.descentAngle.toStringAsFixed(1), '°'),
      ('Roll', dist(shot.rollDistance), prefs.distLabel),
      ('Curve', side(trajectory.curve), prefs.distLabel),
    ];
    final count = switch (density) {
      _Density.full => 7,
      _Density.medium => 4,
      _Density.compact => 3,
    };
    final valueSize = switch (density) {
      _Density.full => 18.0,
      _Density.medium => 16.0,
      _Density.compact => 14.0,
    };
    final pad = density == _Density.compact ? 8.0 : 12.0;

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(pad, 6, pad, 6),
      child: Row(
        children: [
          for (final (label, value, unit) in all.take(count))
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
                      size: density == _Density.compact ? 9 : 10,
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
                        Text(value, style: AppTextStyles.mono(size: valueSize)),
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
  final double size;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.active,
    required this.size,
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
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? context.accentSubtle : AppColors.card,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? context.accent : AppColors.border2,
            ),
          ),
          child: Icon(
            icon,
            size: size * 0.5,
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
    var right = Vec3.up.cross(forward);
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

  /// A camera planted at a point, aimed by yaw and pitch — no orbit target.
  factory _Camera.lookFrom({
    required Vec3 position,
    required double yaw,
    required double pitch,
    required Size size,
    required double fovDegrees,
  }) {
    final forward = Vec3(
      math.sin(yaw) * math.cos(pitch),
      math.sin(pitch),
      math.cos(yaw) * math.cos(pitch),
    ).normalized;
    var right = Vec3.up.cross(forward);
    if (right.length < 1e-5) right = const Vec3(1, 0, 0);
    right = right.normalized;

    return _Camera._(
      position: position,
      right: right,
      up: forward.cross(right).normalized,
      forward: forward,
      focal: size.height / (2 * math.tan(fovDegrees * math.pi / 360.0)),
      centre: Offset(size.width / 2, size.height / 2),
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

/// Scene palette — the sky and every ground tone the painter draws that is
/// not one of a built hole's own terrain cell colours. Night is the incumbent
/// dark-range look; day is a soft daylight tuned so the white markers and the
/// accent tracer stay readable, with the analytic fairway and green matched
/// to the built-hole cell colours so both hole styles read as one world.
class _Scene {
  final Color skyTop;
  final Color skyHorizon;
  final Color ground;
  final Color rough;
  final Color roughClump;
  final Color roughClumpDark;
  final Color fairway;
  final Color fairwayStripe;
  final Color grid;
  final Color green;
  final Color greenCollar;
  final Color greenEdge;
  final Color haze;

  /// How much of [haze] settles over the far ground, 0–1. Clear days sit
  /// low, an overcast sky sits heavy, and night keeps the full-strength
  /// dark fade that has always carried its depth cue.
  final double hazeStrength;

  final Color treeTrunk;
  final Color treeCanopy;
  final Color treeCanopyLit;

  const _Scene({
    required this.skyTop,
    required this.skyHorizon,
    required this.ground,
    required this.rough,
    required this.roughClump,
    required this.roughClumpDark,
    required this.fairway,
    required this.fairwayStripe,
    required this.grid,
    required this.green,
    required this.greenCollar,
    required this.greenEdge,
    required this.haze,
    required this.hazeStrength,
    required this.treeTrunk,
    required this.treeCanopy,
    required this.treeCanopyLit,
  });

  static const night = _Scene(
    skyTop: AppColors.background,
    skyHorizon: AppColors.skyLow,
    ground: AppColors.turfGround,
    rough: AppColors.turfRough,
    roughClump: AppColors.turfRoughClump,
    roughClumpDark: AppColors.turfRoughClumpDark,
    fairway: AppColors.turfFairway,
    fairwayStripe: AppColors.turfFairwayStripe,
    grid: AppColors.turfGrid,
    green: AppColors.turfGreen,
    greenCollar: AppColors.turfGreenCollar,
    greenEdge: AppColors.turfGreenEdge,
    haze: AppColors.turfHaze,
    hazeStrength: 1.0,
    treeTrunk: AppColors.treeTrunk,
    treeCanopy: AppColors.treeCanopy,
    treeCanopyLit: AppColors.treeCanopyLit,
  );

  static const day = _Scene(
    skyTop: Color(0xFF4A90C9),
    skyHorizon: Color(0xFFB8D8EA),
    ground: Color(0xFF3E5633),
    rough: Color(0xFF41582D),
    roughClump: Color(0xFF4C6636),
    roughClumpDark: Color(0xFF364A24),
    fairway: Color(0xFF4C7A47),
    fairwayStripe: Color(0xFF548351),
    grid: Color(0xFF3A5C36),
    green: Color(0xFF74B863),
    greenCollar: Color(0xFF5F9B54),
    greenEdge: Color(0xFF2E5B2B),
    haze: Color(0xFFB8D8EA),
    hazeStrength: 0.35,
    treeTrunk: Color(0xFF5A4632),
    treeCanopy: Color(0xFF2E5B33),
    treeCanopyLit: Color(0xFF477B44),
  );

  static const morning = _Scene(
    skyTop: Color(0xFF6FA3C9),
    skyHorizon: Color(0xFFF2DCA8),
    ground: Color(0xFF43552F),
    rough: Color(0xFF475A2C),
    roughClump: Color(0xFF526538),
    roughClumpDark: Color(0xFF3C4B22),
    fairway: Color(0xFF527B43),
    fairwayStripe: Color(0xFF5A8450),
    grid: Color(0xFF3F5A33),
    green: Color(0xFF79B45F),
    greenCollar: Color(0xFF64984F),
    greenEdge: Color(0xFF2E5B2B),
    haze: Color(0xFFF2DCA8),
    hazeStrength: 0.55,
    treeTrunk: Color(0xFF5A4632),
    treeCanopy: Color(0xFF33602F),
    treeCanopyLit: Color(0xFF4E7F42),
  );

  static const overcast = _Scene(
    skyTop: Color(0xFF7E8B96),
    skyHorizon: Color(0xFFC2CBD2),
    ground: Color(0xFF3D4A38),
    rough: Color(0xFF44523A),
    roughClump: Color(0xFF4D5C42),
    roughClumpDark: Color(0xFF37452E),
    fairway: Color(0xFF4C6E4A),
    fairwayStripe: Color(0xFF527451),
    grid: Color(0xFF3A5040),
    green: Color(0xFF6BA363),
    greenCollar: Color(0xFF578C51),
    greenEdge: Color(0xFF2C4F2C),
    haze: Color(0xFFC2CBD2),
    hazeStrength: 0.8,
    treeTrunk: Color(0xFF4E4234),
    treeCanopy: Color(0xFF2F4F33),
    treeCanopyLit: Color(0xFF416844),
  );

  static const dusk = _Scene(
    skyTop: Color(0xFF35406E),
    skyHorizon: Color(0xFFD98A5B),
    ground: Color(0xFF2E3B26),
    rough: Color(0xFF333F22),
    roughClump: Color(0xFF3C4A2A),
    roughClumpDark: Color(0xFF28331A),
    fairway: Color(0xFF3A5C36),
    fairwayStripe: Color(0xFF416440),
    grid: Color(0xFF2F4A33),
    green: Color(0xFF4F8347),
    greenCollar: Color(0xFF45753E),
    greenEdge: Color(0xFF6B9A55),
    haze: Color(0xFFD98A5B),
    hazeStrength: 0.5,
    treeTrunk: Color(0xFF4A3A2C),
    treeCanopy: Color(0xFF26492B),
    treeCanopyLit: Color(0xFF3A6238),
  );

  static _Scene of(SkyScene choice) => switch (choice) {
    SkyScene.day => day,
    SkyScene.morning => morning,
    SkyScene.overcast => overcast,
    SkyScene.dusk => dusk,
    SkyScene.night => night,
  };
}

class _FlightPainter extends CustomPainter {
  final ShotTrajectory trajectory;
  final List<ShotTrajectory> ghosts;

  /// 0 at impact, 1 once the ball has come to rest.
  final double progress;

  /// Share of [progress] spent airborne; the rest is the bounce and roll.
  final double flightFraction;

  final double yaw;
  final double pitch;
  final double zoom;
  final bool follow;

  /// Stand at the tee and watch, instead of orbiting the shot from outside.
  final bool firstPerson;

  final Color shotColor;
  final Color accent;
  final UnitPrefs prefs;
  final _Density density;

  /// Height of the control overlay along the bottom edge, kept clear of the
  /// shot when framing.
  final double controlStripHeight;

  /// The hole to draw, if one was configured for this shot.
  final HoleSetup? hole;

  /// Frame the whole hole rather than just the shot.
  final bool frameWholeHole;

  /// Sky and turf palette, chosen by the user's sky preference.
  /// Derived from [prefs], so `shouldRepaint`'s prefs check covers it.
  _Scene get scene => _Scene.of(prefs.skyScene);

  _FlightPainter({
    required this.trajectory,
    required this.ghosts,
    required this.progress,
    required this.flightFraction,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.follow,
    required this.firstPerson,
    required this.shotColor,
    required this.accent,
    required this.prefs,
    required this.density,
    required this.controlStripHeight,
    required this.hole,
    required this.frameWholeHole,
  });

  /// Width of one mown band, in yards. Roughly a triplex mower's pass.
  static const _stripeWidth = 5.0;

  double get _s => density.scale;

  /// Fraction of the airborne path that has been drawn.
  double get _flightProgress =>
      flightFraction <= 0 ? 1.0 : (progress / flightFraction).clamp(0.0, 1.0);

  /// Fraction of the bounce-and-roll path that has been drawn.
  double get _groundProgress => flightFraction >= 1.0
      ? (progress >= 1.0 ? 1.0 : 0.0)
      : ((progress - flightFraction) / (1 - flightFraction)).clamp(0.0, 1.0);

  bool get _hasLanded => _flightProgress >= 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || trajectory.isEmpty) return;

    // CustomPaint does not clip to its own bounds. The ground plane is drawn
    // far larger than the shot so its far edge reads as a horizon, and at some
    // camera angles it projects well outside this widget and over whatever
    // sits beside it — the split-view neighbour, the shot list, the nav bar.
    canvas.clipRect(Offset.zero & size);

    final rest = trajectory.restPosition;
    final range = math.max(trajectory.totalDistance, 40.0);
    final ball = _ballPosition();

    // Grid spacing follows the display unit so the labels stay round numbers.
    final gridStep = prefs.distance == DistanceUnit.meters ? 25 / 0.9144 : 25.0;
    final course = hole;
    final halfWidth = math.max(
      math.max(rest.x.abs() + 2 * gridStep, 3 * gridStep),
      math.max(range * 0.3, course == null ? 0.0 : course.fairwayWidth * 0.9),
    );
    // The hole has to be drawn even when the shot falls well short of it.
    final maxDepth =
        math.max(range, course == null ? 0.0 : course.greenBack + 20) +
        2 * gridStep;

    final _Camera camera;
    if (firstPerson) {
      camera = _standingCamera(size);
    } else if (follow) {
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

    _paintBackdrop(canvas, camera, size);
    _paintGround(canvas, camera, halfWidth, maxDepth, gridStep);
    // A built hole replaces the analytic fairway-and-green entirely: its cells
    // already say what every patch of ground is, including the green.
    final built = course?.grid;
    if (built != null) {
      _paintGridHole(canvas, camera, built);
      _paintPinAt(canvas, camera, built);
    } else {
      if (course != null && density.atLeastMedium) {
        _paintRoughTexture(canvas, camera, course, halfWidth, maxDepth);
      }
      if (course != null) _paintGreen(canvas, camera, course);
    }
    _paintDistanceHaze(canvas, camera, size);
    // Trees stand on the ground, so they go over the haze — otherwise the far
    // ones would be washed out at the base and solid at the top.
    if (built != null) _paintTrees(canvas, camera, built);
    if (density.atLeastMedium) {
      _paintDistanceLabels(canvas, camera, gridStep, maxDepth, halfWidth);
    }

    for (final ghost in ghosts) {
      final path = _pathFor(camera, ghost.points, ghost.points.length - 1);
      if (path != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = shotColor.withAlpha(50)
            ..strokeWidth = 1.2 * _s
            ..style = PaintingStyle.stroke,
        );
      }
    }

    if (_hasLanded) _paintLandingMarks(canvas, camera);

    final flightSegments = _visibleSegments(trajectory.points, _flightProgress);
    _paintCurtain(canvas, camera, flightSegments);
    _paintShadow(canvas, camera, trajectory.points, flightSegments);
    _paintFlightPath(canvas, camera, flightSegments);
    _paintGroundPath(canvas, camera);
    _paintApexMarker(canvas, camera, ball);
    _paintBall(canvas, camera, ball);
  }

  // ── Framing ────────────────────────────────────────────────────────────────

  /// Points the camera has to keep on screen: the flight, the bounce path and
  /// where the ball comes to rest.
  List<Vec3> _framingPoints(Vec3 rest) {
    final points = trajectory.points;
    final stride = math.max(1, points.length ~/ 24);
    final ground = trajectory.groundPoints;
    final groundStride = math.max(1, ground.length ~/ 8);
    return [
      Vec3.zero,
      for (var i = 0; i < points.length; i += stride)
        Vec3(points[i].x, points[i].y, points[i].z),
      Vec3(points.last.x, points.last.y, points.last.z),
      for (var i = 0; i < ground.length; i += groundStride)
        Vec3(ground[i].x, ground[i].y, ground[i].z),
      rest,
      // The Hole view frames tee to green whatever the shot did; every other
      // view follows the shot and lets the hole run off the edge.
      if (frameWholeHole && hole != null) ...[
        Vec3(hole!.greenOffset - hole!.greenWidth / 2, 0, hole!.greenFront),
        Vec3(hole!.greenOffset + hole!.greenWidth / 2, 0, hole!.greenBack),
        Vec3(hole!.greenOffset, 2.4, hole!.greenDistance),
      ],
    ];
  }

  /// Eye of a golfer at the tee: about 5'8" up, a pace behind the ball.
  static const _eye = Vec3(0, 1.9, -4.0);

  /// What the player sees, standing where they hit it.
  ///
  /// The eye does not move — that is the whole point — so the shot is framed
  /// by aiming and by the lens instead: the view tilts to sit between the ball
  /// and the apex, and widens if it has to. Drag still looks around from the
  /// same spot, and pinch works as a zoom lens rather than a step backwards.
  _Camera _standingCamera(Size size) {
    double elevationOf(Vec3 p) {
      final d = p - _eye;
      final horizontal = math.max(math.sqrt(d.x * d.x + d.z * d.z), 0.001);
      return math.atan2(d.y, horizontal);
    }

    final marks = <Vec3>[
      Vec3.zero,
      _apexPoint() ?? Vec3.zero,
      trajectory.restPosition,
      if (hole != null) Vec3(hole!.greenOffset, 0, hole!.greenDistance),
    ];
    var lowest = double.infinity;
    var highest = -double.infinity;
    for (final m in marks) {
      final e = elevationOf(m);
      lowest = math.min(lowest, e);
      highest = math.max(highest, e);
    }

    final spread = (highest - lowest) * 1.3 * 180 / math.pi;
    return _Camera.lookFrom(
      position: _eye,
      yaw: yaw,
      pitch: (lowest + highest) / 2 + pitch,
      size: size,
      fovDegrees: (spread.clamp(44.0, 104.0) * zoom).clamp(28.0, 118.0),
    );
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

    // Frame into the area the controls don't cover, rather than the raw
    // viewport: the chip row sits along the bottom, so the usable box is
    // off-centre and the shot has to be centred in *that*.
    const safeTop = 6.0;
    final safeBottom = size.height - controlStripHeight;
    final safeCentre = Offset(size.width / 2, (safeTop + safeBottom) / 2);
    final marginX = size.width * 0.5 * 0.90;
    final marginY = math.max((safeBottom - safeTop) / 2 * 0.96, 24.0);

    var principal = safeCentre;

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
        worst = math.max(worst, (screen.dx - safeCentre.dx).abs() / marginX);
        worst = math.max(worst, (screen.dy - safeCentre.dy).abs() / marginY);
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
        (safeCentre.dx - (minSx + maxSx) / 2).clamp(
          -size.width * 0.3,
          size.width * 0.3,
        ),
        (safeCentre.dy - (minSy + maxSy) / 2).clamp(
          -size.height * 0.3,
          size.height * 0.3,
        ),
      );
      principal = safeCentre + shift;
    }

    return cameraAt(math.max(fitDistance() * zoom, 12.0));
  }

  // ── Geometry helpers ───────────────────────────────────────────────────────

  static int _visibleSegments(List<TrajectoryPoint> points, double progress) =>
      (progress * (points.length - 1)).ceil().clamp(1, points.length - 1);

  static Vec3 _interpolate(List<TrajectoryPoint> points, double progress) {
    final scaled = progress.clamp(0.0, 1.0) * (points.length - 1);
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

  Vec3 _ballPosition() {
    if (trajectory.points.isEmpty) return Vec3.zero;
    if (!_hasLanded) return _interpolate(trajectory.points, _flightProgress);
    final ground = trajectory.groundPoints;
    if (ground.isEmpty) return trajectory.restPosition;
    return _interpolate(ground, _groundProgress);
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
      final b = Vec3(
        points[i + 1].x,
        flatten ? 0 : points[i + 1].y,
        points[i + 1].z,
      );
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
    return lastEnd == null ? null : path;
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

  /// Screen height of the ground plane's true horizon for this camera, or
  /// null when the view has none (looking straight up or down).
  ///
  /// Projected along the camera's own forward direction flattened onto the
  /// plane, so it tracks the real vanishing line under any yaw — and it is
  /// deliberately NOT clamped into the viewport: a horizon far above the top
  /// edge is information the sky and haze need, not an error to correct.
  double? _horizonScreenY(_Camera camera) {
    final flat = Vec3(camera.forward.x, 0, camera.forward.z);
    if (flat.length < 1e-3) return null;
    final far = camera.project(camera.position + flat.normalized * 10000);
    if (far == null || !far.dy.isFinite) return null;
    return far.dy;
  }

  void _paintBackdrop(Canvas canvas, _Camera camera, Size size) {
    final horizon = _horizonScreenY(camera);
    // Anchor the gradient to the horizon so the palest sky always meets the
    // ground line, wherever the camera puts it. The shader clamps beyond its
    // ends, so below the horizon (ground territory) stays horizon-toned and
    // high above stays deep sky. No horizon in view: the camera is pointing
    // at the ground, which will cover the backdrop anyway.
    final anchor = horizon ?? size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, anchor - size.height * 0.9),
          Offset(0, anchor),
          [scene.skyTop, scene.skyHorizon],
        ),
    );
  }

  /// The pin on a built hole: the middle of wherever the green cells are.
  ///
  /// A painted green has no centre to read off a setting, so it is measured.
  /// No green cells means no pin, which is correct — a hole can be built
  /// without one.
  void _paintPinAt(Canvas canvas, _Camera camera, HoleGrid grid) {
    var sx = 0.0, sz = 0.0, n = 0;
    for (var row = 0; row < grid.rows; row++) {
      for (var col = 0; col < grid.cols; col++) {
        if (grid.at(col, row) != Terrain.green) continue;
        sx += grid.left + (col + 0.5) * grid.cellSize;
        sz += (row + 0.5) * grid.cellSize;
        n++;
      }
    }
    if (n == 0) return;
    _paintFlagstick(canvas, camera, Vec3(sx / n, 0, sz / n));
  }

  /// A hand-built hole, drawn cell by cell.
  ///
  /// Cells are merged into horizontal runs before anything is projected: a
  /// 400x120 yard hole at 5-yard cells is nearly two thousand of them, and
  /// almost every one shares a terrain with the cell beside it. Merging turns
  /// that into a few dozen quads a row without changing a pixel.
  ///
  /// Mown surfaces keep their banding, computed from the column index so the
  /// stripes line up across runs rather than restarting at every boundary.
  void _paintGridHole(Canvas canvas, _Camera camera, HoleGrid grid) {
    final cell = grid.cellSize;

    /// Middle of a column, in yards from the target line. The band is read
    /// from the middle rather than an edge so a cell sitting astride a lane
    /// boundary picks the lane it mostly occupies.
    double centreOf(int col) => grid.left + (col + 0.5) * cell;

    for (var row = 0; row < grid.rows; row++) {
      final z0 = row * cell;
      // Overlap downrange by a hair; abutting fills leave an antialiased seam.
      final z1 = z0 + cell + 0.04;
      var col = 0;
      while (col < grid.cols) {
        final terrain = grid.at(col, row);
        // Runs break on a change of terrain, and on a change of mown band so
        // the stripes survive the merge.
        final banded = terrain == Terrain.fairway || terrain == Terrain.green;
        final band = isMowBand(centreOf(col), terrain);
        var end = col + 1;
        while (end < grid.cols &&
            grid.at(end, row) == terrain &&
            (!banded || isMowBand(centreOf(end), terrain) == band)) {
          end++;
        }

        final x0 = grid.left + col * cell;
        final x1 = grid.left + end * cell + 0.04;
        _polygon3(
          canvas,
          camera,
          [Vec3(x0, 0, z0), Vec3(x1, 0, z0), Vec3(x1, 0, z1), Vec3(x0, 0, z1)],
          Paint()
            ..color = banded && !band
                ? terrain.stripeColor
                : terrain.surfaceColor,
        );
        col = end;
      }
    }
  }

  /// Trees, as flat-shaded shapes standing on their cells.
  ///
  /// Sorted far-to-near and drawn in that order, which is the whole of the
  /// depth handling — they are painted before the shot, so a tree never hides
  /// the ball. That is deliberate: the trace is the subject of the view, and
  /// interleaving it properly would mean splitting the path by depth.
  void _paintTrees(Canvas canvas, _Camera camera, HoleGrid grid) {
    final cell = grid.cellSize;
    final stands = <({double depth, Vec3 at, double scale})>[];

    for (var row = 0; row < grid.rows; row++) {
      for (var col = 0; col < grid.cols; col++) {
        if (grid.at(col, row) != Terrain.trees) continue;
        // Hashed from the cell so a tree stays put as the camera moves.
        final h = (col * 73856093) ^ (row * 19349663);
        final jx = ((h & 0xff) / 255.0 - 0.5) * cell * 0.6;
        final jz = (((h >> 8) & 0xff) / 255.0 - 0.5) * cell * 0.6;
        final at = Vec3(
          grid.left + (col + 0.5) * cell + jx,
          0,
          (row + 0.5) * cell + jz,
        );
        final depth = camera.depthOf(at);
        if (depth <= 0) continue;
        stands.add((
          depth: depth,
          at: at,
          scale: 0.8 + ((h >> 16) & 0xff) / 255.0 * 0.5,
        ));
      }
    }

    stands.sort((a, b) => b.depth.compareTo(a.depth));
    for (final t in stands) {
      _paintTree(canvas, camera, t.at, t.scale);
    }
  }

  /// One tree: a trunk and two canopy layers, built from ground-anchored
  /// verticals so it scales with the projection like everything else.
  void _paintTree(Canvas canvas, _Camera camera, Vec3 base, double scale) {
    final height = 9.0 * scale;
    final spread = 3.2 * scale;

    final trunkTop = camera.project(Vec3(base.x, height * 0.42, base.z));
    final trunkBase = camera.project(base);
    if (trunkTop == null || trunkBase == null) return;
    if (!trunkTop.dy.isFinite || !trunkBase.dy.isFinite) return;

    // Trunk width follows the projected height, so it thins with distance
    // without needing a second projection.
    final rise = (trunkBase.dy - trunkTop.dy).abs();
    if (rise < 1.2) return; // too far away to be worth drawing
    canvas.drawLine(
      trunkBase,
      trunkTop,
      Paint()
        ..color = scene.treeTrunk
        ..strokeWidth = math.max(1.0, rise * 0.16),
    );

    // Canopy as two stacked triangles — enough to read as a conifer at any
    // size this view puts them at.
    for (final layer in const [(0.34, 1.0), (0.62, 0.72)]) {
      final (base0, width) = layer;
      final tip = camera.project(Vec3(base.x, height * (base0 + 0.42), base.z));
      final left = camera.project(
        Vec3(base.x - spread * width, height * base0, base.z),
      );
      final right = camera.project(
        Vec3(base.x + spread * width, height * base0, base.z),
      );
      if (tip == null || left == null || right == null) continue;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(right.dx, right.dy)
          ..lineTo(left.dx, left.dy)
          ..close(),
        Paint()..color = base0 > 0.5 ? scene.treeCanopyLit : scene.treeCanopy,
      );
    }
  }

  /// Scattered clumps over the rough, so it reads as longer grass rather than
  /// as a flat fill the fairway happens to sit on.
  ///
  /// The scatter is hashed from each lattice point's own coordinates rather
  /// than drawn from a random source, so a clump keeps its place from frame to
  /// frame. A per-frame RNG would make the whole surface crawl as the camera
  /// orbits.
  void _paintRoughTexture(
    Canvas canvas,
    _Camera camera,
    HoleSetup course,
    double halfWidth,
    double maxDepth,
  ) {
    const step = 7.0;
    final near = -20.0;
    for (var z = near; z < maxDepth; z += step) {
      // Thin the scatter out with distance: at the horizon the clumps would
      // otherwise converge into a solid band.
      final depthFade = (1 - (z - near) / (maxDepth - near)).clamp(0.0, 1.0);
      if (depthFade < 0.06) continue;
      for (var x = -halfWidth; x < halfWidth; x += step) {
        // Cheap positional hash — stable, and cheaper than a real noise field.
        final h =
            ((x * 73856093).toInt() ^ (z * 19349663).toInt()) & 0x7fffffff;
        if (h % 100 > 62) continue;
        final jx = x + (h % 37) / 37.0 * step;
        final jz = z + ((h >> 7) % 41) / 41.0 * step;
        // Only the rough gets clumps; mown surfaces stay smooth.
        if (course.surfaceAt(jx, jz) != Surface.rough) continue;
        final size = 0.9 + (h >> 13) % 11 / 11.0 * 1.5;
        _polygon3(
          canvas,
          camera,
          [
            Vec3(jx - size, 0, jz - size * 0.6),
            Vec3(jx + size, 0, jz - size * 0.6),
            Vec3(jx + size * 0.7, 0, jz + size * 0.6),
            Vec3(jx - size * 0.7, 0, jz + size * 0.6),
          ],
          Paint()
            ..color = (h & 1 == 0 ? scene.roughClump : scene.roughClumpDark)
                .withAlpha((150 * depthFade).round()),
        );
      }
    }
  }

  /// Atmospheric perspective: turf fades toward the horizon tone with
  /// distance.
  ///
  /// This is what pays for the brighter surface. Depth used to come from the
  /// turf simply being nearly black, so lifting it would have flattened the
  /// scene into one bright slab running to the skyline. Fading the far field
  /// instead puts the depth cue where the eye expects it and leaves the near
  /// ground — the part with the shot in it — at full strength.
  ///
  /// Drawn over the ground but under the shot, so it never touches the trace.
  void _paintDistanceHaze(Canvas canvas, _Camera camera, Size size) {
    // Anchored to the same true horizon as the sky, and never clamped into
    // the viewport: with the horizon far above the top edge (camera looking
    // down at near ground) only the weak tail of the fade reaches the frame,
    // instead of a fresh opaque band pinned to the top. No horizon, no haze.
    final horizon = _horizonScreenY(camera);
    if (horizon == null || horizon >= size.height - 1) return;

    // Reaches full clarity about half a viewport below the horizon; past
    // that the haze would start eating the landing area.
    final bottom = horizon + size.height * 0.5;
    if (bottom <= 0) return;

    canvas.drawRect(
      Rect.fromLTRB(
        0,
        math.max(0.0, horizon),
        size.width,
        math.min(size.height, bottom),
      ),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, bottom), [
          scene.haze.withAlpha((255 * scene.hazeStrength).round()),
          scene.haze.withAlpha(0),
        ]),
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
    final course = hole;

    // With a hole set, everything off the fairway and green really is rough —
    // the model says so — so the ground it sits on is coloured as rough rather
    // than as neutral scenery.
    _polygon3(canvas, camera, [
      Vec3(-outerWidth, 0, -outerDepth),
      Vec3(outerWidth, 0, -outerDepth),
      Vec3(outerWidth, 0, outerDepth),
      Vec3(-outerWidth, 0, outerDepth),
    ], Paint()..color = course != null ? scene.rough : scene.ground);

    // Fairway down the target line. With a hole configured it is the width the
    // player set and it stops at the front of the green.
    //
    // It is drawn as mown bands rather than one strip: the way the bands
    // converge is most of what makes the surface read as receding, and it
    // costs a dozen extra polygons.
    final fairwayHalf = course != null
        ? course.fairwayWidth / 2
        : math.min(halfWidth * 0.5, 30.0);
    final fairwayEnd = course != null ? course.greenFront : maxDepth;
    // Lanes are laid out from the target line outwards, not from the fairway
    // edge inwards. Anchoring at the edge moved every band whenever the width
    // changed, and left the two sides of the fairway out of step with each
    // other.
    final firstLane = (-fairwayHalf / _stripeWidth).floor();
    final lastLane = (fairwayHalf / _stripeWidth).ceil();
    for (var lane = firstLane; lane < lastLane; lane++) {
      final left = math.max(lane * _stripeWidth, -fairwayHalf);
      // Overlap the neighbour a hair; abutting fills leave an antialiased seam.
      final right = math.min((lane + 1) * _stripeWidth + 0.05, fairwayHalf);
      if (right - left < 0.01) continue;
      _polygon3(
        canvas,
        camera,
        [
          Vec3(left, 0, behind),
          Vec3(right, 0, behind),
          Vec3(right, 0, fairwayEnd),
          Vec3(left, 0, fairwayEnd),
        ],
        Paint()..color = lane.isEven ? scene.fairway : scene.fairwayStripe,
      );
    }

    // Cross lines — faded with distance so the horizon doesn't turn solid.
    for (var z = 0.0; z <= maxDepth; z += gridStep) {
      final fade = (1 - camera.depthOf(Vec3(0, 0, z)) / (maxDepth * 1.6)).clamp(
        0.12,
        1.0,
      );
      _line3(
        canvas,
        camera,
        Vec3(-halfWidth, 0, z),
        Vec3(halfWidth, 0, z),
        Paint()
          ..color = scene.grid.withAlpha((150 * fade).round())
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
          ..color = scene.grid.withAlpha(70)
          ..strokeWidth = 1,
      );
    }

    // Target line — scenery, so it stays neutral instead of competing with
    // the shot's own accent-coloured marks.
    _line3(
      canvas,
      camera,
      const Vec3(0, 0, behind),
      Vec3(0, 0, maxDepth),
      Paint()
        ..color = AppColors.targetLine.withAlpha(70)
        ..strokeWidth = 1.4,
    );
  }

  /// The green: an ellipse of turf with an edge and a pin in the middle.
  void _paintGreen(Canvas canvas, _Camera camera, HoleSetup course) {
    const segments = 40;
    final halfWidth = course.greenWidth / 2;
    final halfDepth = course.greenDepth / 2;
    final ring = <Vec3>[
      for (var i = 0; i < segments; i++)
        Vec3(
          course.greenOffset + halfWidth * math.cos(i * 2 * math.pi / segments),
          0,
          course.greenDistance +
              halfDepth * math.sin(i * 2 * math.pi / segments),
        ),
    ];

    // Collar first, as a slightly larger ellipse behind the putting surface.
    // A real green is ringed by a band cut between fairway and putting height,
    // and it is the cue that reads first — the shape stops looking like a
    // painted patch and starts looking like a green.
    const collar = 2.2;
    _polygon3(canvas, camera, [
      for (var i = 0; i < segments; i++)
        Vec3(
          course.greenOffset +
              (halfWidth + collar) * math.cos(i * 2 * math.pi / segments),
          0,
          course.greenDistance +
              (halfDepth + collar) * math.sin(i * 2 * math.pi / segments),
        ),
    ], Paint()..color = scene.greenCollar);

    _polygon3(canvas, camera, ring, Paint()..color = scene.green);

    final edge = Paint()
      ..color = scene.greenEdge
      ..strokeWidth = 1.4 * _s;
    for (var i = 0; i < ring.length; i++) {
      _line3(canvas, camera, ring[i], ring[(i + 1) % ring.length], edge);
    }

    _paintFlagstick(canvas, camera, course.pin);

    if (density == _Density.compact) return;
    final label = camera.project(Vec3(course.pin.x, 0, course.greenBack));
    if (label != null) {
      _label(
        canvas,
        '${prefs.dist(course.greenDistance).round()} ${prefs.distLabel}',
        label.translate(0, -10),
        AppTextStyles.mono(size: 9 * _s, color: scene.greenEdge),
      );
    }
  }

  /// Pin, with a small flag. Two and a half yards is roughly a real flagstick
  /// at this scale — tall enough to read, short enough not to dominate.
  void _paintFlagstick(Canvas canvas, _Camera camera, Vec3 base) {
    const height = 2.4;
    final top = Vec3(base.x, height, base.z);
    _line3(
      canvas,
      camera,
      base,
      top,
      Paint()
        ..color = Colors.white.withAlpha(200)
        ..strokeWidth = 1.4 * _s,
    );
    final flagTop = camera.project(top);
    final flagBottom = camera.project(Vec3(base.x, height * 0.72, base.z));
    if (flagTop != null && flagBottom != null) {
      final span = (flagBottom.dy - flagTop.dy).abs().clamp(3.0, 14.0);
      canvas.drawPath(
        Path()
          ..moveTo(flagTop.dx, flagTop.dy)
          ..lineTo(flagTop.dx + span * 1.3, flagTop.dy + span * 0.45)
          ..lineTo(flagTop.dx, flagTop.dy + span * 0.9)
          ..close(),
        Paint()..color = AppColors.pinFlag,
      );
    }
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
        AppTextStyles.mono(size: 9 * _s, color: AppColors.textDimmed),
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
          Vec3(points[i + 1].x, points[i + 1].y, points[i + 1].z),
        ),
        camera.toCamera(Vec3(points[i + 1].x, 0, points[i + 1].z)),
        camera.toCamera(Vec3(points[i].x, 0, points[i].z)),
      ]);
      if (quad.length < 3) continue;
      sheet.addPolygon([for (final c in quad) camera.toScreen(c)], true);
    }
    canvas.drawPath(sheet, Paint()..color = shotColor.withAlpha(16));
  }

  void _paintShadow(
    Canvas canvas,
    _Camera camera,
    List<TrajectoryPoint> points,
    int upTo,
  ) {
    final path = _pathFor(camera, points, upTo, flatten: true);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..strokeWidth = 2.2 * _s
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
        ..strokeWidth = 7 * _s
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * _s),
    );

    // Height reads as a vertical gradient: brighter the higher the ball is.
    final bounds = path.getBounds();
    final linePaint = Paint()
      ..strokeWidth = 2.6 * _s
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

  /// The bounce-and-roll: the ball's real path across the turf, hops and all.
  void _paintGroundPath(Canvas canvas, _Camera camera) {
    final ground = trajectory.groundPoints;
    if (ground.length < 2 || _groundProgress <= 0) return;

    final upTo = _visibleSegments(ground, _groundProgress);
    final path = _pathFor(camera, ground, upTo);
    if (path == null) return;

    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withAlpha(190)
        ..strokeWidth = 1.8 * _s
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Mark each touchdown: a sample sits exactly on the ground right after
    // every bounce.
    for (var i = 1; i <= upTo; i++) {
      if (ground[i].y > 0.01 || ground[i - 1].y <= 0.01) continue;
      final at = camera.project(Vec3(ground[i].x, 0, ground[i].z));
      if (at == null) continue;
      canvas.drawCircle(at, 2.0 * _s, Paint()..color = accent.withAlpha(200));
    }
  }

  void _paintApexMarker(Canvas canvas, _Camera camera, Vec3 ball) {
    if (density == _Density.compact) return;
    final apexPoint = _apexPoint();
    if (apexPoint == null) return;
    // Don't label the apex before the ball has reached it.
    if (!_hasLanded && ball.z < apexPoint.z) return;

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
    canvas.drawCircle(
      top,
      2.5 * _s,
      Paint()..color = Colors.white.withAlpha(170),
    );
    _label(
      canvas,
      'APEX ${prefs.dist(trajectory.apex).toStringAsFixed(0)} ${prefs.distLabel}',
      top.translate(0, -12),
      AppTextStyles.mono(size: 9 * _s, color: Colors.white.withAlpha(190)),
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

  /// Rings at the pitch mark, plus the carry read-out.
  void _paintLandingMarks(Canvas canvas, _Camera camera) {
    final landing = Vec3(trajectory.offline, 0, trajectory.carry);

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
        ..strokeWidth = 1.4 * _s;
      for (var i = 0; i < ring.length; i++) {
        _line3(canvas, camera, ring[i], ring[(i + 1) % ring.length], paint);
      }
    }

    if (density == _Density.compact) return;
    final label = camera.project(landing);
    if (label != null) {
      _label(
        canvas,
        '${prefs.dist(trajectory.carry).toStringAsFixed(0)} ${prefs.distLabel}',
        label.translate(0, 14),
        AppTextStyles.mono(size: 10 * _s, color: accent),
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
          width: 9 * shrink * _s,
          height: 4 * shrink * _s,
        ),
        Paint()..color = Colors.black.withAlpha(140),
      );
    }

    final at = camera.project(ball);
    if (at == null) return;
    canvas.drawCircle(
      at,
      9 * _s,
      Paint()
        ..color = Colors.white.withAlpha(60)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * _s),
    );
    canvas.drawCircle(at, 4 * _s, Paint()..color = Colors.white);
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
      old.flightFraction != flightFraction ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.follow != follow ||
      old.firstPerson != firstPerson ||
      old.shotColor != shotColor ||
      old.accent != accent ||
      old.prefs != prefs ||
      old.density != density ||
      old.controlStripHeight != controlStripHeight ||
      old.hole != hole ||
      old.frameWholeHole != frameWholeHole;
}
