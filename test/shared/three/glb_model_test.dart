import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/shared/three/glb_model.dart';

void main() {
  final bytes = File('assets/models/titleist_gt2_head.glb').readAsBytesSync();

  test('reads every part of the GT2 head with its textures', () {
    final model = parseGlb(bytes);
    expect(model.parts, hasLength(15));
    expect(model.images, hasLength(3));
    expect(model.triangleCount, 64156);
    for (final part in model.parts) {
      expect(part.normals.length, part.positions.length, reason: part.name);
      expect(part.indices.reduce(math.max), lessThan(part.vertexCount), reason: part.name);
      if (part.material.imageIndex != null) {
        expect(part.uvs, isNotNull, reason: part.name);
        expect(part.uvs!.length ~/ 2, part.vertexCount, reason: part.name);
      }
    }
    final textured = model.parts.where((p) => p.material.imageIndex != null);
    expect(textured.map((p) => p.material.name), contains(startsWith('Titanium face')));
  });

  test('applies node transforms, so the head is head-sized in metres', () {
    final model = parseGlb(bytes);
    final size = [for (var k = 0; k < 3; k++) model.boundsMax[k] - model.boundsMin[k]];
    // ~13 cm heel to toe, ~7 cm tall, ~12 cm face to back.
    expect(size[0], closeTo(0.13, 0.01));
    expect(size[1], closeTo(0.071, 0.005));
    expect(size[2], closeTo(0.116, 0.01));
    // The loft sticker is a rotated, translated node; untransformed it would
    // sit near the origin.
    final sticker = model.parts.firstWhere((p) => p.name.startsWith('Sole • loft'));
    expect(sticker.positions[0].abs() + sticker.positions[1].abs(), greaterThan(0.02));
  });

  test('mirroring on X keeps faces facing out', () {
    final model = parseGlb(bytes);
    final mirrored = model.mirroredX();
    expect(mirrored.triangleCount, model.triangleCount);
    expect(mirrored.boundsMin[0], closeTo(-model.boundsMax[0], 1e-6));
    expect(mirrored.boundsMax[0], closeTo(-model.boundsMin[0], 1e-6));
    // Geometric winding must agree with the stored normal, before and after.
    for (final m in [model, mirrored]) {
      final part = m.parts.firstWhere((p) => p.material.name.startsWith('Titanium face'));
      var agree = 0, total = 0;
      for (var t = 0; t + 2 < part.indices.length; t += 3) {
        final a = part.indices[t] * 3, b = part.indices[t + 1] * 3, c = part.indices[t + 2] * 3;
        final p = part.positions;
        final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
        final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
        final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        final n = part.normals;
        if (nx * n[a] + ny * n[a + 1] + nz * n[a + 2] > 0) agree++;
        total++;
      }
      expect(agree / total, greaterThan(0.95));
    }
  });

  test('rejects data that is not a glb', () {
    expect(() => parseGlb(bytes.sublist(4)), throwsA(isA<GlbFormatException>()));
  });
}
