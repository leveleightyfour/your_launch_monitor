part of 'flight_3d_tab.dart';

/// A second art direction on the existing projection and shot model. All
/// scenery stays in the static repaint boundary; Follow uses fewer details.
/// No assets, texture uploads, blur passes or continuously animated scenery.
class _RealisticScenePainter extends _ScenePainter {
  _RealisticScenePainter({
    required super.trajectory,
    required super.replay,
    required super.flightFraction,
    required super.yaw,
    required super.pitch,
    required super.zoom,
    required super.follow,
    required super.firstPerson,
    required super.prefs,
    required super.density,
    required super.controlStripHeight,
    required super.hole,
    required super.frameWholeHole,
    required super.fitCache,
    required super.ghosts,
    required super.shotColor,
    super.repaint,
  });

  @override
  bool get _showGrid => false;

  bool get _reducedDetail => follow || density == _Density.compact;

  @override
  Color _terrainColor(Terrain terrain, bool band) {
    final color = switch (terrain) {
      Terrain.fairway => band ? scene.fairway : scene.fairwayStripe,
      Terrain.green =>
        band ? scene.green : Color.lerp(scene.green, scene.greenCollar, 0.12)!,
      Terrain.rough || Terrain.trees => scene.rough,
      Terrain.bunker => const Color(0xFFD7C598),
      Terrain.water => Color.lerp(
        const Color(0xFF315C69),
        scene.skyHorizon,
        0.28,
      )!,
      Terrain.outOfBounds => const Color(0xFF796C4B),
    };
    if (terrain == Terrain.bunker || terrain == Terrain.outOfBounds) {
      return Color.lerp(color, scene.skyTop, switch (prefs.skyScene) {
        SkyScene.night => 0.75,
        SkyScene.dusk => 0.4,
        SkyScene.overcast => 0.18,
        _ => 0.0,
      })!;
    }
    return color;
  }

  @override
  void _paintBackdrop(Canvas canvas, _Camera camera, Size size) {
    super._paintBackdrop(canvas, camera, size);
    // World-anchored sun/moon: orbiting never drags it along with the camera.
    final sun = camera.project(const Vec3(-4200, 2200, 7000));
    if (sun != null && prefs.skyScene != SkyScene.overcast) {
      final night = prefs.skyScene == SkyScene.night;
      final radius = size.shortestSide * (night ? 0.018 : 0.025);
      canvas.drawCircle(
        sun,
        radius * 6,
        Paint()
          ..shader = ui.Gradient.radial(sun, radius * 6, [
            const Color(0xFFFFEDD0).withAlpha(night ? 15 : 65),
            const Color(0x00FFEDD0),
          ]),
      );
      canvas.drawCircle(
        sun,
        radius,
        Paint()
          ..color = (night ? const Color(0xFFDDE6E9) : const Color(0xFFFFF4D5)),
      );
    }

    // Soft clouds use radial gradients, not offscreen blur/saveLayer passes.
    if (prefs.skyScene != SkyScene.night) {
      final cloudPaint = Paint();
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi / 6;
        final centre = camera.project(
          Vec3(math.sin(a) * 8500, 1100.0 + (i % 3) * 260, math.cos(a) * 8500),
        );
        if (centre == null) continue;
        final depth = camera.depthOf(
          Vec3(math.sin(a) * 8500, 1100.0 + (i % 3) * 260, math.cos(a) * 8500),
        );
        final width = (camera.focal * 1250 / depth).clamp(8.0, size.width);
        for (var puff = 0; puff < 3; puff++) {
          final at = centre.translate(
            (puff - 1) * width * 0.28,
            (puff % 2) * width * 0.04,
          );
          canvas.save();
          canvas.translate(at.dx, at.dy);
          canvas.scale(1, 0.24);
          cloudPaint.shader = ui.Gradient.radial(Offset.zero, width * 0.5, [
            scene.skyHorizon.withAlpha(150),
            scene.skyHorizon.withAlpha(0),
          ]);
          canvas.drawCircle(Offset.zero, width * 0.5, cloudPaint);
          canvas.restore();
        }
      }
    }

    // Distant rolling skyline, outside playable geometry. Every bearing has
    // scenery, including Side/Angled and a full 360-degree orbit.
    for (var layer = 0; layer < 2; layer++) {
      final paint = Paint()
        ..color = Color.lerp(
          scene.treeCanopy,
          scene.skyHorizon,
          layer == 0 ? 0.78 : 0.58,
        )!;
      final radius = layer == 0 ? 14000.0 : 11000.0;
      for (var i = 0; i < 64; i++) {
        final a = i * math.pi / 32;
        final b = (i + 1) * math.pi / 32;
        double height(double angle) =>
            120 +
            90 * math.sin(angle * 5 + layer).abs() +
            80 * math.sin(angle * 9 + 0.7).abs();
        _polygon3(canvas, camera, [
          Vec3(math.sin(a) * radius, -20, math.cos(a) * radius),
          Vec3(math.sin(a) * radius, height(a), math.cos(a) * radius),
          Vec3(math.sin(b) * radius, height(b), math.cos(b) * radius),
          Vec3(math.sin(b) * radius, -20, math.cos(b) * radius),
        ], paint);
      }
    }
  }

  @override
  void _paintGround(
    Canvas canvas,
    _Camera camera,
    double halfWidth,
    double maxDepth,
    double gridStep,
  ) {
    // Extend to the skyline even when the orbit faces back behind the tee.
    _polygon3(canvas, camera, const [
      Vec3(-20000, 0, -20000),
      Vec3(20000, 0, -20000),
      Vec3(20000, 0, 20000),
      Vec3(-20000, 0, 20000),
    ], Paint()..color = scene.rough);
    super._paintGround(canvas, camera, halfWidth, maxDepth, gridStep);
  }

  // Replace the old rough clump pass with a single bounded terrain-detail
  // pass after ALL surfaces have been painted, including custom hole grids.
  @override
  void _paintRoughTexture(
    Canvas canvas,
    _Camera camera,
    HoleSetup course,
    double halfWidth,
    double maxDepth,
  ) {}

  @override
  void _paintDistanceHaze(Canvas canvas, _Camera camera, Size size) {
    _paintSurfaceDetail(canvas, camera, size);
    super._paintDistanceHaze(canvas, camera, size);
    if (hole?.grid == null) _paintBoundaryTrees(canvas, camera);
  }

  void _paintBoundaryTrees(Canvas canvas, _Camera camera) {
    final course = hole;
    final side = math.max(
      (course?.fairwayWidth ?? 60) / 2 + 18,
      (course?.greenOffset.abs() ?? 0) + (course?.greenWidth ?? 30) / 2 + 18,
    );
    final trees = <({Vec3 at, double scale, double depth})>[];
    for (var i = 0; i < 36; i++) {
      final sign = i.isEven ? -1.0 : 1.0;
      final at = Vec3(sign * (side + (i % 5) * 7), 0, 35 + (i ~/ 2) * 22.0);
      if (course != null && course.terrainAt(at.x, at.z) != Terrain.rough) {
        continue;
      }
      final depth = camera.depthOf(at);
      if (depth < 2) continue;
      trees.add((at: at, scale: 0.8 + (i % 4) * 0.18, depth: depth));
    }
    trees.sort((a, b) => b.depth.compareTo(a.depth));
    final trunk = Paint(), lit = Paint(), shade = Paint();
    for (final tree in trees) {
      _paintTree(canvas, camera, tree.at, tree.scale, trunk, lit, shade);
    }
  }

  void _paintSurfaceDetail(Canvas canvas, _Camera camera, Size size) {
    // Fixed world lattice and hash keep details stationary through orbit and
    // replay. Caps are independent of hole dimensions and device pixel ratio.
    final stride = _reducedDetail ? 6.0 : 4.0;
    final originX = (camera.position.x / stride).floor();
    final originZ = (camera.position.z / stride).floor();
    final paint = Paint()..strokeCap = StrokeCap.round;
    final viewport = (Offset.zero & size).inflate(4);
    final span = _reducedDetail ? 9 : 13; // at most 324 / 676 candidates
    for (var row = -span; row < span; row++) {
      for (var col = -span; col < span; col++) {
        final ix = originX + col, iz = originZ + row;
        final hash = ((ix * 73856093) ^ (iz * 19349663)) & 0x7fffffff;
        final x = (ix + (hash & 255) / 255) * stride;
        final z = (iz + ((hash >> 8) & 255) / 255) * stride;
        final at = Vec3(x, 0.015, z);
        final depth = camera.depthOf(at);
        if (depth < 2 || depth > 120) continue;
        final screen = camera.project(at);
        if (screen == null || !viewport.contains(screen)) continue;
        final terrain = hole?.terrainAt(x, z) ?? Terrain.fairway;
        final fade =
            ((depth - 2) / 8).clamp(0.0, 1.0) *
            (1 - depth / 120).clamp(0.0, 1.0);
        if (terrain == Terrain.water) {
          paint
            ..color = scene.skyHorizon.withAlpha((95 * fade).round())
            ..strokeWidth = 0.7;
          _line3(canvas, camera, at, Vec3(x + 1.6, 0.015, z), paint);
        } else {
          final rough = terrain == Terrain.rough || terrain == Terrain.trees;
          paint
            ..color = (hash.isEven ? Colors.white : Colors.black).withAlpha(
              ((rough ? 42 : 22) * fade).round(),
            )
            ..strokeWidth = (camera.focal * 0.018 / depth).clamp(0.5, 1.3);
          // World-space strokes scale naturally with perspective. No grass
          // detail moves above the actual collision surface by more than 4 cm.
          _line3(
            canvas,
            camera,
            at,
            Vec3(x + (rough ? 0.08 : 0.28), rough ? 0.045 : 0.015, z + 0.12),
            paint,
          );
        }
      }
    }
  }

  @override
  void _paintTrees(Canvas canvas, _Camera camera, HoleGrid grid) {
    final visible = <({double depth, Vec3 at, double scale})>[];
    final viewport = Rect.fromLTRB(
      -80,
      -120,
      camera.centre.dx * 2 + 80,
      camera.centre.dy * 2 + 120,
    );
    for (final tree in _ScenePainter._treeStands(grid)) {
      final depth = camera.depthOf(tree.at);
      if (depth < 2) continue;
      final top = camera.project(tree.at + Vec3(0, 6 * tree.scale, 0));
      if (top == null || !viewport.contains(top)) continue;
      visible.add((depth: depth, at: tree.at, scale: tree.scale));
    }
    visible.sort((a, b) => a.depth.compareTo(b.depth));
    // Keep nearest trees, then paint back-to-front. The scan uses the shared
    // cached stand list; dense custom grids cannot multiply canopy draw calls.
    final count = math.min(visible.length, _reducedDetail ? 64 : 128);
    final trunk = Paint()..color = scene.treeTrunk;
    final lit = Paint()..color = scene.treeCanopyLit;
    final shade = Paint()..color = scene.treeCanopy;
    for (var i = count - 1; i >= 0; i--) {
      final t = visible[i];
      _paintTree(canvas, camera, t.at, t.scale, trunk, lit, shade);
    }
  }

  @override
  void _paintTree(
    Canvas canvas,
    _Camera camera,
    Vec3 base,
    double scale,
    Paint trunk,
    Paint canopyLit,
    Paint canopyShade,
  ) {
    final depth = camera.depthOf(base);
    if (depth < 2) return;
    final bottom = camera.project(base);
    final crown = camera.project(base + Vec3(0, 6.4 * scale, 0));
    if (bottom == null || crown == null) return;
    final radius = camera.focal * 3.4 * scale / depth;
    if (radius < 1.2) return;
    final fog = (depth / 900).clamp(0.0, 0.75);
    final dark = Color.lerp(scene.treeCanopy, scene.skyHorizon, fog)!;
    final light = Color.lerp(scene.treeCanopyLit, scene.skyHorizon, fog)!;

    // Ground-projected directional shadow; gradients cost one ordinary fill.
    final shadow = <Vec3>[
      for (var i = 0; i < 16; i++)
        Vec3(
          base.x + 3 * scale + math.cos(i * math.pi / 8) * 4 * scale,
          0.01,
          base.z + 2 * scale + math.sin(i * math.pi / 8) * 2.4 * scale,
        ),
    ];
    _polygon3(
      canvas,
      camera,
      shadow,
      Paint()
        ..color = Colors.black.withAlpha(
          prefs.skyScene == SkyScene.overcast ? 20 : 38,
        ),
    );
    canvas.drawLine(
      bottom,
      crown,
      trunk
        ..color = Color.lerp(scene.treeTrunk, scene.skyHorizon, fog)!
        ..strokeWidth = math.max(0.8, radius * 0.14),
    );
    final paint = Paint();
    final lobes = radius < 5 || _reducedDetail ? 3 : 7;
    for (var i = 0; i < lobes; i++) {
      final angle = i * 2.4 + base.z;
      final at = crown.translate(
        math.cos(angle) * radius * 0.42,
        math.sin(angle) * radius * 0.34,
      );
      final r = radius * (i == 0 ? 0.9 : 0.67);
      paint.shader = ui.Gradient.radial(
        at.translate(-r * 0.35, -r * 0.4),
        r * 1.7,
        [light, dark],
        [0, 1],
      );
      canvas.drawCircle(at, r, paint);
    }
  }

  @override
  void _paintDistanceLabels(
    Canvas canvas,
    _Camera camera,
    double gridStep,
    double maxDepth,
    double halfWidth,
  ) {
    // Small physical range boards, outside the line of play.
    for (var z = gridStep * 2; z <= maxDepth; z += gridStep * 2) {
      final x = hole?.grid?.left ?? -(hole?.fairwayWidth ?? 60) / 2 - 5;
      final at = camera.project(Vec3(x, 0.8, z));
      if (at == null) continue;
      final depth = camera.depthOf(Vec3(x, 0.8, z));
      if (depth < 3 || depth > 500) continue;
      final font = (camera.focal * 1.4 / depth).clamp(7.0, 11.0);
      final rect = Rect.fromCenter(
        center: at,
        width: font * 3.2,
        height: font * 1.65,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = const Color(0xDD263B2D),
      );
      _label(
        canvas,
        prefs.dist(z).round().toString(),
        at,
        AppTextStyles.mono(size: font, color: const Color(0xFFEDEEDC)),
      );
    }
  }
}

/// Same trajectory samples and timing, with a clean tracer and lit ball.
class _RealisticFlightPainter extends _FlightPainter {
  _RealisticFlightPainter({
    required super.trajectory,
    required super.replay,
    required super.flightFraction,
    required super.yaw,
    required super.pitch,
    required super.zoom,
    required super.follow,
    required super.firstPerson,
    required super.prefs,
    required super.density,
    required super.controlStripHeight,
    required super.hole,
    required super.frameWholeHole,
    required super.fitCache,
    required super.shotColor,
    required super.accent,
    super.repaint,
  });

  @override
  void _paintCurtain(Canvas canvas, _Camera camera, int upTo) {}

  @override
  void _paintShadow(
    Canvas canvas,
    _Camera camera,
    List<TrajectoryPoint> points,
    int upTo,
  ) {}

  @override
  void _paintFlightPath(Canvas canvas, _Camera camera, int upTo) {
    final path = _pathFor(camera, trajectory.points, upTo);
    if (path == null) return;
    // Two crisp strokes stay readable against sky and turf without a
    // full-flight blur on every animation frame.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      path,
      paint
        ..color = Colors.black.withAlpha(65)
        ..strokeWidth = 4.2 * _s,
    );
    canvas.drawPath(
      path,
      paint
        ..color = Color.lerp(shotColor, Colors.white, 0.35)!
        ..strokeWidth = 2.2 * _s,
    );
  }

  @override
  void _paintBall(Canvas canvas, _Camera camera, Vec3 ball) {
    final at = camera.project(ball);
    if (at == null) return;
    final depth = camera.depthOf(ball);
    // Regulation radius in yards with a small readability floor: the tracer
    // remains useful on a phone when a truly sized distant ball is subpixel.
    final radius = (camera.focal * 0.0233 / depth).clamp(1.8 * _s, 4.5 * _s);
    final shadowAt = camera.project(
      Vec3(ball.x + ball.y * 0.35, 0.012, ball.z + ball.y * 0.2),
    );
    if (shadowAt != null && ball.y < 20) {
      final opacity = ((1 - ball.y / 20) * 100).round();
      final shadowRadius = radius * (1.4 + ball.y * 0.08);
      canvas.save();
      canvas.translate(shadowAt.dx, shadowAt.dy);
      canvas.scale(1, 0.4);
      canvas.drawCircle(
        Offset.zero,
        shadowRadius,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, shadowRadius, [
            Colors.black.withAlpha(opacity),
            Colors.transparent,
          ]),
      );
      canvas.restore();
    }
    canvas.drawCircle(
      at,
      radius + 0.6,
      Paint()..color = Colors.black.withAlpha(95),
    );
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          at.translate(-radius * 0.35, -radius * 0.4),
          radius * 1.6,
          const [Color(0xFFFFFFFF), Color(0xFFE8E9DF), Color(0xFF818C87)],
          const [0, 0.55, 1],
        ),
    );
  }
}
