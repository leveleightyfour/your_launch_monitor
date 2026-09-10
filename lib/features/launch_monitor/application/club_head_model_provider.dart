import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/three/glb_model.dart';

/// A club head ready to draw: the parsed mesh, its textures decoded, and the
/// face measured so a shot's numbers can be hung on the geometry.
///
/// Model frame: +Z out of the face toward the target, +Y up, +X toward the
/// toe, −X toward the heel and hosel. A right-handed golfer stands on the
/// −X side with the target to their left.
///
/// The GT2 export is built as the mirror image of that — hosel at +X with
/// the face still at +Z, which is a left-handed head, and its decals read
/// backwards to prove it — so the mesh is reflected on X as it loads.
class ClubHeadModel {
  final GlbModel mesh;
  final List<ui.Image?> images;

  /// Centre of the face in model space, metres.
  final Float32List faceCentre;

  /// Unit normal of the face at address.
  final Float32List faceNormal;

  /// Loft built into the geometry, degrees: what the face reads before any
  /// delivery is applied. A shot's dynamic loft is rendered relative to it.
  final double staticLoft;

  /// Face extents on its own plane, metres: half-width heel to toe and
  /// half-height sole to crown, for placing impact positions.
  final double faceHalfWidth;
  final double faceHalfHeight;

  /// Model-space centre and radius of the whole head, for framing.
  final Float32List centre;
  final double radius;

  /// Support points of the head's convex hull — the farthest vertex in each
  /// of a spread of directions, xyz triples. Projecting these onto a camera
  /// gives the silhouette's extent from any angle without touching the
  /// whole mesh, which is what lets a view fit the head to the viewport.
  final Float32List hull;

  const ClubHeadModel({
    required this.mesh,
    required this.images,
    required this.faceCentre,
    required this.faceNormal,
    required this.staticLoft,
    required this.faceHalfWidth,
    required this.faceHalfHeight,
    required this.centre,
    required this.radius,
    required this.hull,
  });

  static const asset = 'assets/models/titleist_gt2_head.glb';

  static Future<ClubHeadModel> load([String asset = ClubHeadModel.asset]) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final mesh = (await compute(parseGlb, bytes, debugLabel: 'parseGlb')).mirroredX();
    final images = <ui.Image?>[];
    for (final image in mesh.images) {
      try {
        images.add(await decodeImageFromList(image.bytes));
      } catch (_) {
        images.add(null);
      }
    }
    return ClubHeadModel.measure(mesh, images);
  }

  /// Derive the face and framing from the mesh alone. The face is the part
  /// whose material name says so; failing that, the largest part whose
  /// average normal points furthest along +Z.
  factory ClubHeadModel.measure(GlbModel mesh, List<ui.Image?> images) {
    GlbPart? face;
    for (final part in mesh.parts) {
      if (part.material.name.toLowerCase().contains('face')) {
        face = part;
        break;
      }
    }
    if (face == null) {
      var best = -2.0;
      for (final part in mesh.parts) {
        final n = _averageNormal(part);
        if (n[2] > best && part.triangleCount > 100) {
          best = n[2];
          face = part;
        }
      }
    }
    face ??= mesh.parts.first;
    final normal = _averageNormal(face);
    // Loft is the face normal's elevation above the horizontal.
    final staticLoft = math.atan2(normal[1], math.sqrt(normal[0] * normal[0] + normal[2] * normal[2])) * 180 / math.pi;
    // The face's own axes: up is +Y flattened onto the face plane, across
    // runs toward the toe within it. Extents along them bound the outline,
    // and their midpoint is the geometric centre of the face — what an impact
    // position is measured from. The vertex centroid would drift toward
    // wherever the mesh is densest (the scoring), so it is not used.
    final up = _unit([-normal[1] * normal[0], 1 - normal[1] * normal[1], -normal[1] * normal[2]]);
    final across = _unit([
      up[1] * normal[2] - up[2] * normal[1],
      up[2] * normal[0] - up[0] * normal[2],
      up[0] * normal[1] - up[1] * normal[0],
    ]);
    var minA = double.infinity, maxA = -double.infinity;
    var minU = double.infinity, maxU = -double.infinity;
    var minN = double.infinity, maxN = -double.infinity;
    for (var i = 0; i < face.positions.length; i += 3) {
      final x = face.positions[i], y = face.positions[i + 1], z = face.positions[i + 2];
      final a = x * across[0] + y * across[1] + z * across[2];
      final u = x * up[0] + y * up[1] + z * up[2];
      final d = x * normal[0] + y * normal[1] + z * normal[2];
      if (a < minA) minA = a;
      if (a > maxA) maxA = a;
      if (u < minU) minU = u;
      if (u > maxU) maxU = u;
      if (d < minN) minN = d;
      if (d > maxN) maxN = d;
    }
    final midA = (minA + maxA) / 2, midU = (minU + maxU) / 2;
    // On the face surface: the bulge puts the middle of the face proud of
    // its edges, so take the outermost depth rather than the mean.
    final centre = Float32List.fromList([
      for (var k = 0; k < 3; k++) across[k] * midA + up[k] * midU + normal[k] * maxN,
    ]);
    final headCentre = Float32List.fromList([
      for (var k = 0; k < 3; k++) (mesh.boundsMin[k] + mesh.boundsMax[k]) / 2,
    ]);
    var radius = 0.0;
    for (var k = 0; k < 3; k++) {
      final half = (mesh.boundsMax[k] - mesh.boundsMin[k]) / 2;
      radius += half * half;
    }
    return ClubHeadModel(
      mesh: mesh,
      images: images,
      faceCentre: centre,
      faceNormal: normal,
      staticLoft: staticLoft,
      faceHalfWidth: (maxA - minA) / 2,
      faceHalfHeight: (maxU - minU) / 2,
      centre: headCentre,
      radius: math.sqrt(radius),
      hull: _supportPoints(mesh),
    );
  }

  /// The farthest vertex along each of [count] directions spread evenly
  /// over the sphere (a Fibonacci lattice).
  static Float32List _supportPoints(GlbModel mesh, {int count = 96}) {
    final out = Float32List(count * 3);
    final golden = math.pi * (3 - math.sqrt(5));
    for (var i = 0; i < count; i++) {
      final y = 1 - 2 * (i + 0.5) / count;
      final r = math.sqrt(1 - y * y);
      final theta = golden * i;
      final dx = math.cos(theta) * r, dy = y, dz = math.sin(theta) * r;
      var best = -double.infinity;
      var bx = 0.0, by = 0.0, bz = 0.0;
      for (final part in mesh.parts) {
        final p = part.positions;
        for (var k = 0; k < p.length; k += 3) {
          final d = p[k] * dx + p[k + 1] * dy + p[k + 2] * dz;
          if (d > best) {
            best = d;
            bx = p[k];
            by = p[k + 1];
            bz = p[k + 2];
          }
        }
      }
      out[i * 3] = bx;
      out[i * 3 + 1] = by;
      out[i * 3 + 2] = bz;
    }
    return out;
  }

  static Float32List _averageNormal(GlbPart part) {
    var x = 0.0, y = 0.0, z = 0.0;
    for (var i = 0; i < part.normals.length; i += 3) {
      x += part.normals[i];
      y += part.normals[i + 1];
      z += part.normals[i + 2];
    }
    final l = math.sqrt(x * x + y * y + z * z);
    return Float32List.fromList(l == 0 ? [0, 0, 1] : [x / l, y / l, z / l]);
  }

  static List<double> _unit(List<double> v) {
    final l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return l == 0 ? const [0, 1, 0] : [v[0] / l, v[1] / l, v[2] / l];
  }
}

/// The driver head, loaded once per app run. Every club shows it until its
/// own model lands.
final clubHeadModelProvider = FutureProvider<ClubHeadModel>(
  (_) => ClubHeadModel.load(),
);
