import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../../shared/theme.dart';
import '../../../application/club_head_model_provider.dart';
import '../../../domain/entities/shot_data.dart';

// The club head drawn in three dimensions with the shot's delivery hung on
// it. Pure Dart on top of Canvas.drawVertices: every vertex is transformed,
// lit and projected here, the same way the 3D flight tab draws its world,
// so nothing native is involved and the whole thing ships as a patch once
// the model asset is in a release.
//
// Frame of reference (see ClubHeadModel): +Z out of the face toward the
// target, +Y up, +X toward the toe, −X toward the heel and hosel. A
// right-handed golfer stands on the −X side looking down the target line,
// so "right of target" for them is +X: an open face turns its normal toward
// +X, and an in-to-out path travels toward +X as it goes to the target.

/// The three ways of looking at the head. Names double as the stored
/// preference so the tab reopens where the golfer left it.
enum ClubView {
  side('Side'),
  top('Top'),
  impact('Impact');

  const ClubView(this.label);
  final String label;

  static ClubView fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => ClubView.side);
}

/// Where each view parks the camera: yaw about +Y (0 = in front of the
/// face, on the target side; −90° = at the heel, looking along the face),
/// pitch above the ground, where the head's silhouette is centred on
/// screen, and how much of the viewport's width and height it may fill —
/// the rest is the room its figures need.
///
/// Impact looks at the face from the target side (yaw 0°). Side stands at
/// the toe (+90°) looking along the face toward the hosel, which puts the
/// hosel at the back and the target to the right. Top rises over the heel
/// (−90°) to look down, so the target line runs left across the screen with
/// the toe at the top — the head seen as the golfer stands over it.
class _Preset {
  final double yawDeg;
  final double pitchDeg;
  final Offset anchor;
  final double fillWidth;
  final double fillHeight;

  const _Preset(this.yawDeg, this.pitchDeg, this.anchor, this.fillWidth, this.fillHeight);

  static _Preset of(ClubView view) => switch (view) {
    // Loft and attack figures sit to the right of the face.
    ClubView.side => const _Preset(90, 7, Offset(0.42, 0.52), 0.52, 0.5),
    // The target line runs left; the figures sit above and below it.
    ClubView.top => const _Preset(-90, 76, Offset(0.6, 0.5), 0.5, 0.6),
    // Readouts live in the corners; the face can take the middle.
    ClubView.impact => const _Preset(0, 4, Offset(0.5, 0.5), 0.66, 0.6),
  };

  _Preset lerp(_Preset other, double t) => _Preset(
    yawDeg + (other.yawDeg - yawDeg) * t,
    pitchDeg + (other.pitchDeg - pitchDeg) * t,
    Offset.lerp(anchor, other.anchor, t)!,
    fillWidth + (other.fillWidth - fillWidth) * t,
    fillHeight + (other.fillHeight - fillHeight) * t,
  );

  @override
  bool operator ==(Object other) =>
      other is _Preset &&
      other.yawDeg == yawDeg &&
      other.pitchDeg == pitchDeg &&
      other.anchor == anchor &&
      other.fillWidth == fillWidth &&
      other.fillHeight == fillHeight;
  @override
  int get hashCode => Object.hash(yawDeg, pitchDeg, anchor, fillWidth, fillHeight);
}

/// How the shot turns the head: the face open or closed about +Y, and the
/// face tilted about the heel–toe axis until it reads the dynamic loft.
class _Pose {
  final double faceAngle;
  final double loftDelta;
  const _Pose({required this.faceAngle, required this.loftDelta});

  static _Pose of(ShotData shot, ClubHeadModel model) => _Pose(
    faceAngle: (shot.faceAngle ?? 0).clamp(-30.0, 30.0),
    loftDelta: ((shot.dynamicLoft ?? model.staticLoft) - model.staticLoft)
        .clamp(-25.0, 25.0),
  );

  /// Rotation as a row-major 3×3: Ry(face) · Rx(−loft).
  Float64List matrix() {
    final a = faceAngle * math.pi / 180, b = -loftDelta * math.pi / 180;
    final ca = math.cos(a), sa = math.sin(a), cb = math.cos(b), sb = math.sin(b);
    // Ry = [ca 0 sa; 0 1 0; -sa 0 ca], Rx = [1 0 0; 0 cb -sb; 0 sb cb]
    return Float64List.fromList([
      ca, sa * sb, sa * cb,
      0, cb, -sb,
      -sa, ca * sb, ca * cb,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is _Pose && other.faceAngle == faceAngle && other.loftDelta == loftDelta;
  @override
  int get hashCode => Object.hash(faceAngle, loftDelta);
}

/// Perspective camera orbiting the head's centre, backed off until the
/// head's silhouette from this angle fills what the preset allows.
class _Camera {
  final Float64List eye;
  final Float64List right;
  final Float64List up;
  final Float64List forward;
  final double focal;
  final Offset centre;

  const _Camera._(this.eye, this.right, this.up, this.forward, this.focal, this.centre);

  factory _Camera(_Preset p, ClubHeadModel model, _Pose pose, Size size) {
    const fov = 28.0;
    final focal = size.height / (2 * math.tan(fov * math.pi / 360));
    final yaw = p.yawDeg * math.pi / 180, pitch = p.pitchDeg * math.pi / 180;
    final focus = model.centre;
    // The basis depends on the angle alone, so the silhouette can be
    // measured before the distance is known.
    final direction = [
      math.sin(yaw) * math.cos(pitch),
      math.sin(pitch),
      math.cos(yaw) * math.cos(pitch),
    ];
    final forward = _norm([-direction[0], -direction[1], -direction[2]]);
    var right = _cross([0, 1, 0], forward);
    if (_len(right) < 1e-6) right = Float64List.fromList([1, 0, 0]);
    right = _norm(right);
    final up = _norm(_cross(forward, right));

    // Extent of the posed hull across and up the screen, about the centre.
    final r = pose.matrix();
    var minR = double.infinity, maxR = -double.infinity;
    var minU = double.infinity, maxU = -double.infinity;
    final hull = model.hull;
    for (var i = 0; i < hull.length; i += 3) {
      final px = hull[i] - focus[0], py = hull[i + 1] - focus[1], pz = hull[i + 2] - focus[2];
      final wx = r[0] * px + r[1] * py + r[2] * pz;
      final wy = r[3] * px + r[4] * py + r[5] * pz;
      final wz = r[6] * px + r[7] * py + r[8] * pz;
      final a = wx * right[0] + wy * right[1] + wz * right[2];
      final u = wx * up[0] + wy * up[1] + wz * up[2];
      if (a < minR) minR = a;
      if (a > maxR) maxR = a;
      if (u < minU) minU = u;
      if (u > maxU) maxU = u;
    }
    // Back off until the wider of the two fits its allowance. Perspective
    // spreads the near side a little, hence the margin.
    const margin = 1.06;
    final distance = margin *
        math.max(
          focal * (maxR - minR) / (p.fillWidth * size.width),
          focal * (maxU - minU) / (p.fillHeight * size.height),
        );
    final eye = Float64List.fromList([
      focus[0] + direction[0] * distance,
      focus[1] + direction[1] * distance,
      focus[2] + direction[2] * distance,
    ]);
    // Centre the silhouette, not the model's origin, on the anchor: the
    // hosel sticks out one side and would otherwise drag the head off it.
    final scale = focal / distance;
    final centre = Offset(
      size.width * p.anchor.dx - (minR + maxR) / 2 * scale,
      size.height * p.anchor.dy + (minU + maxU) / 2 * scale,
    );
    return _Camera._(eye, right, up, forward, focal, centre);
  }

  Offset project(double x, double y, double z) {
    final dx = x - eye[0], dy = y - eye[1], dz = z - eye[2];
    final cz = dx * forward[0] + dy * forward[1] + dz * forward[2];
    final cx = dx * right[0] + dy * right[1] + dz * right[2];
    final cy = dx * up[0] + dy * up[1] + dz * up[2];
    return Offset(centre.dx + focal * cx / cz, centre.dy - focal * cy / cz);
  }

  /// Screen pixels per metre at the head's centre — for sizing overlays.
  double scaleAt(Float32List point) {
    final dx = point[0] - eye[0], dy = point[1] - eye[1], dz = point[2] - eye[2];
    return focal / (dx * forward[0] + dy * forward[1] + dz * forward[2]);
  }
}

Float64List _cross(List<double> a, List<double> b) => Float64List.fromList([
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]);
double _len(List<double> a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
Float64List _norm(List<double> a) {
  final l = _len(a);
  return Float64List.fromList(l == 0 ? [0, 0, 1] : [a[0] / l, a[1] / l, a[2] / l]);
}

// ── Mesh painter ─────────────────────────────────────────────────────────────

class _Draw {
  final ui.Vertices vertices;
  final Paint paint;
  final double depth;
  const _Draw(this.vertices, this.paint, this.depth);
}

/// The last frame built, so an unchanged view repaints without touching a
/// single vertex: the painter is rebuilt by every widget rebuild, the frame
/// only when something that moves the head changes.
class _FrameCache {
  static Object? key;
  static List<_Draw>? draws;
}

class _ClubHeadPainter extends CustomPainter {
  final ClubHeadModel model;
  final _Preset preset;
  final _Pose pose;

  const _ClubHeadPainter({required this.model, required this.preset, required this.pose});

  @override
  void paint(Canvas canvas, Size size) {
    final key = Object.hash(model, preset, pose, size);
    if (_FrameCache.key != key) {
      _FrameCache.key = key;
      _FrameCache.draws = _build(_Camera(preset, model, pose, size));
    }
    for (final d in _FrameCache.draws!) {
      canvas.drawVertices(d.vertices, BlendMode.modulate, d.paint);
    }
  }

  List<_Draw> _build(_Camera cam) {
    final r = pose.matrix();
    final c = model.centre;
    // Lights in camera space (x right, y up, z into the screen): a key from
    // the upper left in front, a low fill from the right, a rim from behind.
    final key = _norm([-0.45, 0.7, -0.55]);
    final fill = _norm([0.7, -0.25, -0.4]);
    final rim = _norm([0.1, 0.35, 0.93]);
    final draws = <_Draw>[];

    for (final part in model.mesh.parts) {
      final n = part.vertexCount;
      final screen = Float32List(n * 2);
      final depth = Float32List(n);
      final colors = Int32List(n);
      final mat = part.material;
      final textured = mat.imageIndex != null && model.images[mat.imageIndex!] != null;
      // Instrument palette: near-black lacquer and raw metal both read as a
      // matte mid grey, so the shape carries and the accent stays the only
      // colour. Textures keep their own tone.
      final tone = textured
          ? const [1.0, 1.0, 1.0]
          : [
              mat.red * 0.4 + 0.42,
              mat.green * 0.4 + 0.44,
              mat.blue * 0.4 + 0.47,
            ];
      final shine = 0.15 + mat.metallic * 0.35 * (1 - mat.roughness);

      var sumDepth = 0.0;
      for (var i = 0; i < n; i++) {
        final px = part.positions[i * 3] - c[0];
        final py = part.positions[i * 3 + 1] - c[1];
        final pz = part.positions[i * 3 + 2] - c[2];
        final wx = r[0] * px + r[1] * py + r[2] * pz + c[0];
        final wy = r[3] * px + r[4] * py + r[5] * pz + c[1];
        final wz = r[6] * px + r[7] * py + r[8] * pz + c[2];
        final dx = wx - cam.eye[0], dy = wy - cam.eye[1], dz = wz - cam.eye[2];
        final cz = dx * cam.forward[0] + dy * cam.forward[1] + dz * cam.forward[2];
        final cx = dx * cam.right[0] + dy * cam.right[1] + dz * cam.right[2];
        final cy = dx * cam.up[0] + dy * cam.up[1] + dz * cam.up[2];
        screen[i * 2] = cam.centre.dx + cam.focal * cx / cz;
        screen[i * 2 + 1] = cam.centre.dy - cam.focal * cy / cz;
        depth[i] = cz;
        sumDepth += cz;

        final nx0 = part.normals[i * 3], ny0 = part.normals[i * 3 + 1], nz0 = part.normals[i * 3 + 2];
        final nx = r[0] * nx0 + r[1] * ny0 + r[2] * nz0;
        final ny = r[3] * nx0 + r[4] * ny0 + r[5] * nz0;
        final nz = r[6] * nx0 + r[7] * ny0 + r[8] * nz0;
        final vx = nx * cam.right[0] + ny * cam.right[1] + nz * cam.right[2];
        final vy = nx * cam.up[0] + ny * cam.up[1] + nz * cam.up[2];
        final vz = nx * cam.forward[0] + ny * cam.forward[1] + nz * cam.forward[2];

        final kd = math.max(0.0, vx * key[0] + vy * key[1] + vz * key[2]);
        final fd = math.max(0.0, vx * fill[0] + vy * fill[1] + vz * fill[2]);
        final rd = math.max(0.0, vx * rim[0] + vy * rim[1] + vz * rim[2]);
        // Blinn–Phong highlight toward the key, half vector with the view.
        final hx = key[0], hy = key[1], hz = key[2] - 1;
        final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
        final spec = math.pow(math.max(0.0, (vx * hx + vy * hy + vz * hz) / hl), 28).toDouble() * shine;
        final light = 0.30 + 0.62 * kd + 0.18 * fd + 0.12 * rd * rd;
        final rr = (tone[0] * light + spec) * 255;
        final gg = (tone[1] * light + spec) * 255;
        final bb = (tone[2] * light + spec) * 255;
        colors[i] = 0xFF000000 |
            (rr.clamp(0, 255).toInt() << 16) |
            (gg.clamp(0, 255).toInt() << 8) |
            bb.clamp(0, 255).toInt();
      }

      // Back-face culling by screen winding, then a far-to-near bucket sort
      // so the painter's order holds within the part. Front faces of a
      // counter-clockwise mesh turn clockwise once y points down.
      final tris = part.triangleCount;
      final order = Uint32List(tris);
      var kept = 0;
      var minZ = double.infinity, maxZ = -double.infinity;
      final triDepth = Float32List(tris);
      for (var t = 0; t < tris; t++) {
        final a = part.indices[t * 3], b = part.indices[t * 3 + 1], q = part.indices[t * 3 + 2];
        final ax = screen[a * 2], ay = screen[a * 2 + 1];
        final cross = (screen[b * 2] - ax) * (screen[q * 2 + 1] - ay) -
            (screen[b * 2 + 1] - ay) * (screen[q * 2] - ax);
        if (cross <= 0 && !mat.doubleSided) continue;
        if (cross <= 0) {
          // A double-sided part still hides its far side behind its near
          // side; keep only faces whose normals lean toward the camera.
          final nz = depth[a] + depth[b] + depth[q];
          if (nz > 0 && cross < -1e-3) continue;
        }
        final d = (depth[a] + depth[b] + depth[q]) / 3;
        triDepth[t] = d;
        if (d < minZ) minZ = d;
        if (d > maxZ) maxZ = d;
        order[kept++] = t;
      }
      if (kept == 0) continue;

      const buckets = 512;
      final span = maxZ - minZ;
      final counts = Int32List(buckets + 1);
      final bucketOf = Int32List(kept);
      for (var i = 0; i < kept; i++) {
        final bIndex = span <= 0
            ? 0
            : (buckets - 1 - ((triDepth[order[i]] - minZ) / span * (buckets - 1)).floor())
                .clamp(0, buckets - 1);
        bucketOf[i] = bIndex;
        counts[bIndex + 1]++;
      }
      for (var b = 0; b < buckets; b++) {
        counts[b + 1] += counts[b];
      }
      final sortedIndices = Uint16List(kept * 3);
      for (var i = 0; i < kept; i++) {
        final slot = counts[bucketOf[i]]++;
        final t = order[i];
        sortedIndices[slot * 3] = part.indices[t * 3];
        sortedIndices[slot * 3 + 1] = part.indices[t * 3 + 1];
        sortedIndices[slot * 3 + 2] = part.indices[t * 3 + 2];
      }

      final paint = Paint()..color = Colors.white;
      Float32List? texCoords;
      if (textured) {
        final image = model.images[mat.imageIndex!]!;
        paint.shader = ui.ImageShader(
          image,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.medium,
        );
        texCoords = Float32List(n * 2);
        for (var i = 0; i < n; i++) {
          texCoords[i * 2] = part.uvs![i * 2] * image.width;
          texCoords[i * 2 + 1] = part.uvs![i * 2 + 1] * image.height;
        }
      }
      draws.add(
        _Draw(
          ui.Vertices.raw(
            VertexMode.triangles,
            screen,
            colors: colors,
            textureCoordinates: texCoords,
            indices: sortedIndices,
          ),
          paint,
          mat.blend ? -double.infinity : sumDepth / n,
        ),
      );
    }
    // Far parts first; decals that blend go last so they always land on top.
    draws.sort((a, b) => b.depth.compareTo(a.depth));
    return draws;
  }

  @override
  bool shouldRepaint(_ClubHeadPainter old) =>
      old.model != model || old.preset != preset || old.pose != pose;
}

// ── Annotations ──────────────────────────────────────────────────────────────

/// The reference lines, angle arcs and figures for one view, drawn in the
/// same projection as the head so they sit on its geometry.
class _AnnotationPainter extends CustomPainter {
  final ClubHeadModel model;
  final _Preset preset;
  final _Pose pose;
  final ClubView view;
  final ShotData shot;
  final List<ShotData> allShots;
  final bool showHeatmap;
  final UnitPrefs prefs;
  final Color accent;
  final double opacity;

  const _AnnotationPainter({
    required this.model,
    required this.preset,
    required this.pose,
    required this.view,
    required this.shot,
    required this.allShots,
    required this.showHeatmap,
    required this.prefs,
    required this.accent,
    required this.opacity,
  });

  static const _referenceColor = AppColors.targetLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withAlpha((opacity * 255).round()));
    final cam = _Camera(preset, model, pose, size);
    switch (view) {
      case ClubView.side:
        _paintSide(canvas, size, cam);
      case ClubView.top:
        _paintTop(canvas, size, cam);
      case ClubView.impact:
        _paintImpact(canvas, size, cam);
    }
    canvas.restore();
  }

  // Model-space helpers. Points are rotated by the pose about the head's
  // centre before projection, exactly as the mesh is.
  Offset _p(_Camera cam, double x, double y, double z, {bool posed = true}) {
    if (!posed) return cam.project(x, y, z);
    final r = pose.matrix();
    final c = model.centre;
    final px = x - c[0], py = y - c[1], pz = z - c[2];
    return cam.project(
      r[0] * px + r[1] * py + r[2] * pz + c[0],
      r[3] * px + r[4] * py + r[5] * pz + c[1],
      r[6] * px + r[7] * py + r[8] * pz + c[2],
    );
  }

  Paint _line(Color color, {double width = 1.2}) => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 6, double gap = 5}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  /// Arc in 3D between two directions on a plane, as a projected polyline.
  void _arc(
    Canvas canvas,
    _Camera cam,
    List<double> origin,
    List<double> from,
    List<double> to,
    double radius,
    Paint paint, {
    bool posed = false,
  }) {
    final path = Path();
    const steps = 18;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      // Slerp between the two unit directions.
      final dot = (from[0] * to[0] + from[1] * to[1] + from[2] * to[2]).clamp(-1.0, 1.0);
      final omega = math.acos(dot);
      final wa = omega < 1e-4 ? 1 - t : math.sin((1 - t) * omega) / math.sin(omega);
      final wb = omega < 1e-4 ? t : math.sin(t * omega) / math.sin(omega);
      final x = origin[0] + (from[0] * wa + to[0] * wb) * radius;
      final y = origin[1] + (from[1] * wa + to[1] * wb) * radius;
      final z = origin[2] + (from[2] * wa + to[2] * wb) * radius;
      final s = _p(cam, x, y, z, posed: posed);
      if (i == 0) {
        path.moveTo(s.dx, s.dy);
      } else {
        path.lineTo(s.dx, s.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  /// The angle between two directions, filled from the vertex outward and
  /// fading to nothing at the arc — the delivered angle read as an area,
  /// not only a line.
  void _wedge(
    Canvas canvas,
    _Camera cam,
    List<double> origin,
    List<double> from,
    List<double> to,
    double radius,
    Color color, {
    bool posed = false,
  }) {
    final vertex = _p(cam, origin[0], origin[1], origin[2], posed: posed);
    final path = Path()..moveTo(vertex.dx, vertex.dy);
    const steps = 18;
    var reach = 0.0;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final dot = (from[0] * to[0] + from[1] * to[1] + from[2] * to[2]).clamp(-1.0, 1.0);
      final omega = math.acos(dot);
      final wa = omega < 1e-4 ? 1 - t : math.sin((1 - t) * omega) / math.sin(omega);
      final wb = omega < 1e-4 ? t : math.sin(t * omega) / math.sin(omega);
      final s = _p(
        cam,
        origin[0] + (from[0] * wa + to[0] * wb) * radius,
        origin[1] + (from[1] * wa + to[1] * wb) * radius,
        origin[2] + (from[2] * wa + to[2] * wb) * radius,
        posed: posed,
      );
      reach = math.max(reach, (s - vertex).distance);
      path.lineTo(s.dx, s.dy);
    }
    path.close();
    if (reach <= 0) return;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          vertex,
          reach,
          [color.withAlpha(110), color.withAlpha(0)],
        ),
    );
  }

  /// A readout — label above, value with unit — anchored by one of its
  /// corners so it can sit on either side of the thing it measures.
  void _readout(
    Canvas canvas,
    Size size,
    Offset at,
    String label,
    String value,
    String unit, {
    Alignment align = Alignment.topLeft,
    Color? color,
    String? note,
  }) {
    final labelPainter = TextPainter(
      text: TextSpan(text: label.toUpperCase(), style: AppTextStyles.statLabel()),
      textDirection: TextDirection.ltr,
    )..layout();
    final valuePainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: value, style: AppTextStyles.statValue(size: 24, color: color ?? Colors.white)),
          if (unit.isNotEmpty) TextSpan(text: ' $unit', style: AppTextStyles.statUnit()),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final notePainter = note == null
        ? null
        : (TextPainter(
            text: TextSpan(text: note, style: AppTextStyles.sans(size: 11, color: AppColors.textMuted)),
            textDirection: TextDirection.ltr,
          )..layout());
    final w = [labelPainter.width, valuePainter.width, notePainter?.width ?? 0].reduce(math.max);
    final h = labelPainter.height + 2 + valuePainter.height + (notePainter == null ? 0 : notePainter.height + 1);
    var origin = Offset(at.dx - (align.x + 1) / 2 * w, at.dy - (align.y + 1) / 2 * h);
    // Keep it on screen.
    origin = Offset(
      origin.dx.clamp(8.0, math.max(8.0, size.width - w - 8)),
      origin.dy.clamp(8.0, math.max(8.0, size.height - h - 8)),
    );
    labelPainter.paint(canvas, origin);
    valuePainter.paint(canvas, origin + Offset(0, labelPainter.height + 2));
    notePainter?.paint(canvas, origin + Offset(0, labelPainter.height + 2 + valuePainter.height + 1));
  }

  String _deg(double v) => v.abs().toStringAsFixed(1);

  // ── Side: dynamic loft and angle of attack, seen from the toe ─────────────

  void _paintSide(Canvas canvas, Size size, _Camera cam) {
    final fc = model.faceCentre;
    final n = model.faceNormal;
    final headRadius = model.radius;
    // Ground level under the sole, along the target line through the face.
    final ground = model.mesh.boundsMin[1];
    final gA = _p(cam, fc[0], ground, fc[2] - headRadius * 1.6, posed: false);
    final gB = _p(cam, fc[0], ground, fc[2] + headRadius * 1.9, posed: false);
    canvas.drawLine(gA, gB, _line(AppColors.border2, width: 1));

    // The face plane: its up-vector in the face's own plane, rotated by the
    // delivered loft as the mesh is. Drawn through the face centre.
    final faceUp = _norm([0 - n[1] * n[0], 1 - n[1] * n[1], 0 - n[1] * n[2]]);
    final loftLen = model.faceHalfHeight * 2.6;
    final top = _p(cam, fc[0] + faceUp[0] * loftLen, fc[1] + faceUp[1] * loftLen, fc[2] + faceUp[2] * loftLen);
    final bottom = _p(cam, fc[0] - faceUp[0] * loftLen * 0.55, fc[1] - faceUp[1] * loftLen * 0.55, fc[2] - faceUp[2] * loftLen * 0.55);
    canvas.drawLine(bottom, top, _line(accent, width: 1.6));
    // Vertical reference through the same point.
    final vTop = _p(cam, fc[0], fc[1] + loftLen, fc[2], posed: false);
    final vBottom = _p(cam, fc[0], fc[1] - loftLen * 0.55, fc[2], posed: false);
    _dashed(canvas, vBottom, vTop, _line(_referenceColor.withAlpha(150), width: 1));

    final dynLoft = shot.dynamicLoft;
    if (dynLoft != null) {
      // Arc from vertical to the delivered face plane, above the face.
      final delivered = _rotX(faceUp, -pose.loftDelta);
      _wedge(canvas, cam, [fc[0], fc[1], fc[2]], [0, 1, 0], delivered, loftLen * 0.9, accent);
      _arc(canvas, cam, [fc[0], fc[1], fc[2]], [0, 1, 0], delivered, loftLen * 0.9, _line(accent.withAlpha(180), width: 1));
      // Beside the arc, clear of whichever of the two lines leans further
      // out at that height.
      final beside = _p(cam, fc[0], fc[1] + loftLen * 0.62, fc[2], posed: false);
      final onFace = _p(cam, fc[0] + faceUp[0] * loftLen * 0.62, fc[1] + faceUp[1] * loftLen * 0.62, fc[2] + faceUp[2] * loftLen * 0.62);
      _readout(
        canvas,
        size,
        Offset(math.max(beside.dx, onFace.dx) + 20, beside.dy),
        'Dyn. loft',
        _deg(dynLoft),
        '°',
        align: Alignment.centerLeft,
        color: accent,
        note: 'face at impact',
      );
    }

    // Angle of attack: the head's path through the ball, rising or falling
    // toward the target, against the horizontal.
    final aoa = shot.angleOfAttack;
    if (aoa != null) {
      final rad = aoa * math.pi / 180;
      final dir = [0.0, math.sin(rad), math.cos(rad)];
      final len = headRadius * 1.7;
      final origin = [fc[0], ground, fc[2] + model.faceHalfWidth * 0.2];
      final back = _p(cam, origin[0] - dir[0] * len, origin[1] - dir[1] * len, origin[2] - dir[2] * len, posed: false);
      final fore = _p(cam, origin[0] + dir[0] * len, origin[1] + dir[1] * len, origin[2] + dir[2] * len, posed: false);
      _wedge(canvas, cam, origin, [0, 0, 1], dir, len * 0.75, accent);
      canvas.drawLine(back, fore, _line(accent, width: 1.6));
      _arc(canvas, cam, origin, [0, 0, 1], dir, len * 0.75, _line(accent.withAlpha(180), width: 1));
      // Under the ground line, where nothing else lives, clear of the
      // loft figure above the face.
      final under = _p(cam, origin[0], ground, origin[2] + len * 0.9, posed: false);
      _readout(
        canvas,
        size,
        Offset(under.dx, under.dy + 14),
        'Angle of attack',
        _deg(aoa),
        '°',
        align: Alignment.topRight,
        color: accent,
        note: aoa >= 0 ? 'up' : 'down',
      );
    }
  }

  static List<double> _rotX(List<double> v, double deg) {
    final a = deg * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    return [v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c];
  }

  static List<double> _rotY(List<double> v, double deg) {
    final a = deg * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    return [v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c];
  }

  // ── Top: face to target and club path, seen from above ────────────────────

  void _paintTop(Canvas canvas, Size size, _Camera cam) {
    final fc = model.faceCentre;
    final r = model.radius;
    final ground = model.mesh.boundsMin[1] + 0.001;
    // The target line runs through the ball just off the face — leftward
    // on screen from this camera — with the ball's cross line through it.
    // Its reach is set by the screen, not the head: out to near the edge
    // however wide the pane, so the figures beside it always have room.
    final ball = [fc[0], ground, fc[2] + 0.02];
    final ballScreen = _p(cam, ball[0], ball[1], ball[2], posed: false);
    final perMetre = cam.scaleAt(Float32List.fromList([ball[0], ball[1], ball[2]]));
    final reach = math.max(r * 1.2, (ballScreen.dx - size.width * 0.07) / perMetre);
    final tA = _p(cam, ball[0], ball[1], ball[2] - r * 1.4, posed: false);
    final tB = _p(cam, ball[0], ball[1], ball[2] + reach, posed: false);
    canvas.drawLine(tA, tB, _line(_referenceColor, width: 1.2));
    _dashed(
      canvas,
      _p(cam, ball[0] - r * 0.9, ball[1], ball[2], posed: false),
      _p(cam, ball[0] + r * 0.9, ball[1], ball[2], posed: false),
      _line(AppColors.border2, width: 1),
    );

    final face = shot.faceAngle;
    if (face != null) {
      // The face line, heel to toe, turned as the head is; its normal
      // arced against the target line in front of the face.
      final along = _rotY([1, 0, 0], pose.faceAngle);
      final half = model.faceHalfWidth * 1.35;
      final normal = _rotY([0, 0, 1], pose.faceAngle);
      final len = reach * 0.5;
      _wedge(canvas, cam, [fc[0], ground, fc[2]], [0, 0, 1], normal, len * 0.7, accent);
      final a = _p(cam, fc[0] + along[0] * half, ground, fc[2] + along[2] * half, posed: false);
      final b = _p(cam, fc[0] - along[0] * half, ground, fc[2] - along[2] * half, posed: false);
      canvas.drawLine(a, b, _line(accent, width: 1.6));
      final tip = _p(cam, fc[0] + normal[0] * len, ground, fc[2] + normal[2] * len, posed: false);
      _dashed(canvas, _p(cam, fc[0], ground, fc[2], posed: false), tip, _line(accent.withAlpha(180), width: 1));
      _arc(canvas, cam, [fc[0], ground, fc[2]], [0, 0, 1], normal, len * 0.7, _line(accent.withAlpha(180), width: 1));
      // Above the line for an open face (which turns toward the toe, the
      // top of the screen), below for a closed one.
      final above = face >= 0;
      _readout(
        canvas,
        size,
        Offset(tip.dx, tip.dy + (above ? -12 : 12)),
        'Face to target',
        _deg(face),
        '°',
        align: above ? Alignment.bottomCenter : Alignment.topCenter,
        color: accent,
        note: above ? 'open' : 'closed',
      );
    }

    final path = shot.swingPath;
    if (path != null) {
      final dir = _rotY([0, 0, 1], path);
      final len = reach * 0.8;
      _wedge(canvas, cam, ball, [0, 0, 1], dir, len * 0.6, accent);
      final back = _p(cam, ball[0] - dir[0] * len * 0.5, ball[1], ball[2] - dir[2] * len * 0.5, posed: false);
      final fore = _p(cam, ball[0] + dir[0] * len, ball[1], ball[2] + dir[2] * len, posed: false);
      canvas.drawLine(back, fore, _line(accent, width: 1.6));
      _arrowHead(canvas, back, fore, accent);
      _arc(canvas, cam, ball, [0, 0, 1], dir, len * 0.6, _line(accent.withAlpha(180), width: 1));
      // Opposite side of the target line from the face figure, so the two
      // never meet: in-to-out heads for the toe, so its figure goes below.
      final below = path >= 0;
      _readout(
        canvas,
        size,
        Offset(fore.dx + 8, fore.dy + (below ? 14 : -14)),
        'Club path',
        _deg(path),
        '°',
        align: below ? Alignment.topLeft : Alignment.bottomLeft,
        color: accent,
        note: path > 0 ? 'in to out' : path < 0 ? 'out to in' : 'square',
      );
    }

    if (face != null && path != null) {
      final ftp = face - path;
      _readout(
        canvas,
        size,
        Offset(size.width - 16, size.height - 16),
        'Face to path',
        _deg(ftp),
        '°',
        align: Alignment.bottomRight,
        note: ftp > 0 ? 'open to path' : ftp < 0 ? 'closed to path' : 'square to path',
      );
    }
  }

  void _arrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    final d = to - from;
    if (d.distance == 0) return;
    final u = d / d.distance;
    final n = Offset(-u.dy, u.dx);
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - u.dx * 9 + n.dx * 4.5, to.dy - u.dy * 9 + n.dy * 4.5)
      ..lineTo(to.dx - u.dx * 9 - n.dx * 4.5, to.dy - u.dy * 9 - n.dy * 4.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ── Impact: strike positions on the face, club speed ──────────────────────

  /// Model-space point on the face plane for an impact position in mm
  /// (+horizontal = toe, +vertical = high), lifted just off the surface.
  List<double> _facePoint(double hMm, double vMm) {
    final fc = model.faceCentre;
    final n = model.faceNormal;
    final up = _norm([0 - n[1] * n[0], 1 - n[1] * n[1], 0 - n[1] * n[2]]);
    final across = _norm(_cross(up, n)); // toward the toe (+X) on the face plane
    final h = hMm / 1000, v = vMm / 1000;
    const lift = 0.0015;
    return [
      fc[0] + across[0] * h + up[0] * v + n[0] * lift,
      fc[1] + across[1] * h + up[1] * v + n[1] * lift,
      fc[2] + across[2] * h + up[2] * v + n[2] * lift,
    ];
  }

  Offset _faceScreen(_Camera cam, double hMm, double vMm) {
    final q = _facePoint(hMm, vMm);
    return _p(cam, q[0], q[1], q[2]);
  }

  void _paintImpact(Canvas canvas, Size size, _Camera cam) {
    final halfW = model.faceHalfWidth * 1000;
    final halfH = model.faceHalfHeight * 1000;
    // The face centre's own axes, drawn on the face plane and run well
    // past the head so a strike reads against them at a glance: a solid
    // horizontal for high and low, a dashed vertical for toe and heel.
    canvas.drawLine(
      _faceScreen(cam, halfW * 3.2, 0),
      _faceScreen(cam, -halfW * 3.2, 0),
      _line(_referenceColor.withAlpha(150), width: 1),
    );
    _dashed(
      canvas,
      _faceScreen(cam, 0, halfH * 3.4),
      _faceScreen(cam, 0, -halfH * 3.4),
      _line(_referenceColor.withAlpha(150), width: 1),
    );
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void zone(String t, Offset at) {
      tp
        ..text = TextSpan(text: t, style: AppTextStyles.statLabel(color: AppColors.textDimmed))
        ..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    zone('TOE', _faceScreen(cam, halfW * 0.8, halfH * 1.25));
    zone('HEEL', _faceScreen(cam, -halfW * 0.8, halfH * 1.25));

    if (showHeatmap) {
      _heatmap(canvas, cam, halfW, halfH);
    } else {
      final p = Paint()..color = Colors.white.withAlpha(150);
      for (final s in allShots) {
        if (identical(s, shot) || s.horizontalImpact == null || s.verticalImpact == null) continue;
        canvas.drawCircle(_faceScreen(cam, s.horizontalImpact!, s.verticalImpact!), 3, p);
      }
    }
    if (shot.horizontalImpact != null && shot.verticalImpact != null) {
      final at = _faceScreen(cam, shot.horizontalImpact!, shot.verticalImpact!);
      canvas.drawCircle(at, 14, Paint()..color = accent.withAlpha(30)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(at, 9, Paint()..color = accent.withAlpha(200)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      canvas.drawCircle(at, 4, Paint()..color = accent);
    }

    _readout(
      canvas,
      size,
      Offset(size.width - 16, 16),
      'Club speed',
      prefs.spd(shot.clubSpeed).toStringAsFixed(1),
      prefs.speedLabel,
      align: Alignment.topRight,
    );
    final h = shot.horizontalImpact, v = shot.verticalImpact;
    _readout(
      canvas,
      size,
      Offset(16, size.height - 16),
      'Horiz. impact',
      h == null ? '—' : h.abs().toStringAsFixed(1),
      h == null ? '' : 'mm ${h >= 0 ? 'toe' : 'heel'}',
      align: Alignment.bottomLeft,
    );
    _readout(
      canvas,
      size,
      Offset(size.width - 16, size.height - 16),
      'Vert. impact',
      v == null ? '—' : v.abs().toStringAsFixed(1),
      v == null ? '' : 'mm ${v >= 0 ? 'high' : 'low'}',
      align: Alignment.bottomRight,
    );
  }

  void _heatmap(Canvas canvas, _Camera cam, double halfW, double halfH) {
    const cols = 9, rows = 7;
    final grid = List.generate(rows, (_) => List.filled(cols, 0));
    var maxCount = 0;
    for (final s in allShots) {
      if (s.horizontalImpact == null || s.verticalImpact == null) continue;
      final c = (((s.horizontalImpact! + halfW) / (2 * halfW)) * cols).floor().clamp(0, cols - 1);
      final r = (((halfH - s.verticalImpact!) / (2 * halfH)) * rows).floor().clamp(0, rows - 1);
      grid[r][c]++;
      if (grid[r][c] > maxCount) maxCount = grid[r][c];
    }
    if (maxCount == 0) return;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final count = grid[r][c];
        if (count == 0) continue;
        final t = count / maxCount;
        final color = Color.lerp(const Color(0xFF1A3A6A), const Color(0xFFE05A2B), t)!
            .withAlpha((t * 190 + 40).round().clamp(0, 255));
        // Cell corners in mm: columns run heel → toe.
        final h0 = -halfW + (c / cols) * 2 * halfW, h1 = -halfW + ((c + 1) / cols) * 2 * halfW;
        final v0 = halfH - (r / rows) * 2 * halfH, v1 = halfH - ((r + 1) / rows) * 2 * halfH;
        final quad = Path()
          ..moveTo(_faceScreen(cam, h0, v0).dx, _faceScreen(cam, h0, v0).dy)
          ..lineTo(_faceScreen(cam, h1, v0).dx, _faceScreen(cam, h1, v0).dy)
          ..lineTo(_faceScreen(cam, h1, v1).dx, _faceScreen(cam, h1, v1).dy)
          ..lineTo(_faceScreen(cam, h0, v1).dx, _faceScreen(cam, h0, v1).dy)
          ..close();
        canvas.drawPath(quad, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) =>
      old.model != model ||
      old.preset != preset ||
      old.pose != pose ||
      old.view != view ||
      old.shot != shot ||
      old.allShots != allShots ||
      old.showHeatmap != showHeatmap ||
      old.prefs != prefs ||
      old.accent != accent ||
      old.opacity != opacity;
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// The head with one view's annotations, and the authored moment between
/// views: figures fade out, the head swings to the new angle, the new
/// figures fade in.
class ClubHeadView extends StatefulWidget {
  final ClubHeadModel model;
  final ShotData shot;
  final List<ShotData> allShots;
  final ClubView view;
  final bool showHeatmap;
  final UnitPrefs prefs;

  const ClubHeadView({
    super.key,
    required this.model,
    required this.shot,
    required this.allShots,
    required this.view,
    required this.showHeatmap,
    required this.prefs,
  });

  /// The whole move, fade-out to fade-in.
  static const transition = Duration(milliseconds: 950);

  @override
  State<ClubHeadView> createState() => _ClubHeadViewState();
}

class _ClubHeadViewState extends State<ClubHeadView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ClubHeadView.transition,
    value: 1,
  );
  late ClubView _from = widget.view;
  late ClubView _to = widget.view;

  @override
  void didUpdateWidget(ClubHeadView old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      _from = _controller.isAnimating ? _to : old.view;
      _to = widget.view;
      if (MediaQuery.of(context).disableAnimations) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Camera progress: the swing occupies the middle of the move, easing out
  /// so the head settles before the figures return.
  static double _swing(double t) =>
      Curves.easeOutCubic.transform(((t - 0.12) / 0.7).clamp(0.0, 1.0));

  /// Figures are gone while the head moves.
  static double _fade(double t) {
    if (t < 0.12) return 1 - t / 0.12;
    if (t > 0.84) return (t - 0.84) / 0.16;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final pose = _Pose.of(widget.shot, widget.model);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final preset = _Preset.of(_from).lerp(_Preset.of(_to), _swing(t));
        final fade = _fade(t);
        final annotated = t < 0.5 ? _from : _to;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ClubHeadPainter(model: widget.model, preset: preset, pose: pose),
            ),
            CustomPaint(
              painter: _AnnotationPainter(
                model: widget.model,
                preset: preset,
                pose: pose,
                view: annotated,
                shot: widget.shot,
                allShots: widget.allShots,
                showHeatmap: widget.showHeatmap,
                prefs: widget.prefs,
                accent: accent,
                opacity: fade,
              ),
            ),
          ],
        );
      },
    );
  }
}
