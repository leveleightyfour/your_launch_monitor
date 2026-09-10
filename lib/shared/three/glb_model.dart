import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// A minimal glTF 2.0 binary (.glb) reader: enough to lift triangle meshes,
// their normals, texture coordinates and materials out of a Blender export
// and hand them to a painter. Pure Dart, no engine types, so it parses in an
// isolate and tests can read a model straight from disk.
//
// What it deliberately does not do: skins, morph targets, animations, KHR
// extensions, sparse accessors, or anything but triangle lists. A model that
// needs those is not a club head.

class GlbImage {
  final String mimeType;
  final Uint8List bytes;
  const GlbImage({required this.mimeType, required this.bytes});
}

class GlbMaterial {
  final String name;

  /// Linear RGBA base colour factor, 0–1.
  final double red, green, blue, alpha;
  final double metallic;
  final double roughness;

  /// Index into [GlbModel.images] when the base colour comes from a texture.
  final int? imageIndex;
  final bool blend;
  final bool doubleSided;

  const GlbMaterial({
    required this.name,
    this.red = 1,
    this.green = 1,
    this.blue = 1,
    this.alpha = 1,
    this.metallic = 1,
    this.roughness = 1,
    this.imageIndex,
    this.blend = false,
    this.doubleSided = false,
  });

  static const fallback = GlbMaterial(name: 'default', metallic: 0, roughness: 1);
}

/// One triangle list in model space, node transforms already applied.
class GlbPart {
  final String name;

  /// xyz triples.
  final Float32List positions;

  /// Unit xyz triples, one per vertex.
  final Float32List normals;

  /// uv pairs, or null when the material is untextured.
  final Float32List? uvs;

  /// Triangle list, three indices per face.
  final Uint32List indices;
  final GlbMaterial material;

  const GlbPart({
    required this.name,
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    required this.material,
  });

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

class GlbModel {
  final List<GlbPart> parts;
  final List<GlbImage> images;
  final Float32List boundsMin;
  final Float32List boundsMax;

  const GlbModel({
    required this.parts,
    required this.images,
    required this.boundsMin,
    required this.boundsMax,
  });

  int get triangleCount => parts.fold(0, (n, p) => n + p.triangleCount);

  /// The same model reflected through the YZ plane, with every triangle's
  /// winding reversed so its front faces stay front faces. For an export
  /// that was built as the wrong hand.
  GlbModel mirroredX() {
    final parts = <GlbPart>[];
    for (final part in this.parts) {
      final positions = Float32List.fromList(part.positions);
      final normals = Float32List.fromList(part.normals);
      for (var i = 0; i < positions.length; i += 3) {
        positions[i] = -positions[i];
        normals[i] = -normals[i];
      }
      final indices = Uint32List.fromList(part.indices);
      for (var t = 0; t + 2 < indices.length; t += 3) {
        final b = indices[t + 1];
        indices[t + 1] = indices[t + 2];
        indices[t + 2] = b;
      }
      parts.add(GlbPart(
        name: part.name,
        positions: positions,
        normals: normals,
        uvs: part.uvs,
        indices: indices,
        material: part.material,
      ));
    }
    return GlbModel(
      parts: parts,
      images: images,
      boundsMin: Float32List.fromList([-boundsMax[0], boundsMin[1], boundsMin[2]]),
      boundsMax: Float32List.fromList([-boundsMin[0], boundsMax[1], boundsMax[2]]),
    );
  }
}

class GlbFormatException implements Exception {
  final String message;
  const GlbFormatException(this.message);
  @override
  String toString() => 'GlbFormatException: $message';
}

/// Parse a .glb file. Throws [GlbFormatException] on anything it cannot read.
GlbModel parseGlb(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 20 || data.getUint32(0, Endian.little) != 0x46546C67) {
    throw const GlbFormatException('not a glb file');
  }
  if (data.getUint32(4, Endian.little) != 2) {
    throw const GlbFormatException('only glTF 2.0 is supported');
  }
  final jsonLength = data.getUint32(12, Endian.little);
  if (data.getUint32(16, Endian.little) != 0x4E4F534A) {
    throw const GlbFormatException('first chunk is not JSON');
  }
  final json =
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)))
          as Map<String, dynamic>;
  Uint8List bin = Uint8List(0);
  final binStart = 20 + jsonLength;
  if (bytes.length >= binStart + 8) {
    final binLength = data.getUint32(binStart, Endian.little);
    if (data.getUint32(binStart + 4, Endian.little) != 0x004E4942) {
      throw const GlbFormatException('second chunk is not BIN');
    }
    bin = Uint8List.sublistView(bytes, binStart + 8, binStart + 8 + binLength);
  }
  return _Reader(json, bin).read();
}

class _Reader {
  final Map<String, dynamic> json;
  final Uint8List bin;
  _Reader(this.json, this.bin);

  List<dynamic> _list(String key) => (json[key] as List<dynamic>?) ?? const [];

  Uint8List _view(int index) {
    final bv = _list('bufferViews')[index] as Map<String, dynamic>;
    if ((bv['buffer'] as int) != 0) {
      throw const GlbFormatException('external buffers are not supported');
    }
    final offset = (bv['byteOffset'] as int?) ?? 0;
    return Uint8List.sublistView(bin, offset, offset + (bv['byteLength'] as int));
  }

  int _stride(int viewIndex) {
    final bv = _list('bufferViews')[viewIndex] as Map<String, dynamic>;
    return (bv['byteStride'] as int?) ?? 0;
  }

  /// Read a float accessor as a flat list, [components] per element.
  Float32List _floats(int accessorIndex, int components) {
    final a = _list('accessors')[accessorIndex] as Map<String, dynamic>;
    if ((a['componentType'] as int) != 5126) {
      throw GlbFormatException('accessor $accessorIndex is not float32');
    }
    final count = a['count'] as int;
    final viewIndex = a['bufferView'] as int;
    final view = _view(viewIndex);
    final data = ByteData.sublistView(view);
    final base = (a['byteOffset'] as int?) ?? 0;
    final stride = _stride(viewIndex);
    final out = Float32List(count * components);
    if (stride == 0 || stride == components * 4) {
      for (var i = 0; i < out.length; i++) {
        out[i] = data.getFloat32(base + i * 4, Endian.little);
      }
    } else {
      for (var e = 0; e < count; e++) {
        for (var c = 0; c < components; c++) {
          out[e * components + c] =
              data.getFloat32(base + e * stride + c * 4, Endian.little);
        }
      }
    }
    return out;
  }

  Uint32List _indices(int accessorIndex) {
    final a = _list('accessors')[accessorIndex] as Map<String, dynamic>;
    final count = a['count'] as int;
    final view = _view(a['bufferView'] as int);
    final data = ByteData.sublistView(view);
    final base = (a['byteOffset'] as int?) ?? 0;
    final out = Uint32List(count);
    switch (a['componentType'] as int) {
      case 5121:
        for (var i = 0; i < count; i++) {
          out[i] = data.getUint8(base + i);
        }
      case 5123:
        for (var i = 0; i < count; i++) {
          out[i] = data.getUint16(base + i * 2, Endian.little);
        }
      case 5125:
        for (var i = 0; i < count; i++) {
          out[i] = data.getUint32(base + i * 4, Endian.little);
        }
      default:
        throw GlbFormatException('unsupported index type in $accessorIndex');
    }
    return out;
  }

  List<GlbMaterial> _materials() {
    final images = _list('images');
    final textures = _list('textures');
    return [
      for (final m in _list('materials').cast<Map<String, dynamic>>())
        _material(m, textures, images),
    ];
  }

  GlbMaterial _material(
    Map<String, dynamic> m,
    List<dynamic> textures,
    List<dynamic> images,
  ) {
    final pbr = (m['pbrMetallicRoughness'] as Map<String, dynamic>?) ?? const {};
    final factor =
        (pbr['baseColorFactor'] as List<dynamic>?)?.cast<num>() ??
        const [1, 1, 1, 1];
    int? imageIndex;
    final tex = pbr['baseColorTexture'] as Map<String, dynamic>?;
    if (tex != null) {
      final t = textures[tex['index'] as int] as Map<String, dynamic>;
      final source = t['source'] as int?;
      if (source != null && source < images.length) imageIndex = source;
    }
    return GlbMaterial(
      name: (m['name'] as String?) ?? 'material',
      red: factor[0].toDouble(),
      green: factor[1].toDouble(),
      blue: factor[2].toDouble(),
      alpha: factor[3].toDouble(),
      metallic: ((pbr['metallicFactor'] as num?) ?? 1).toDouble(),
      roughness: ((pbr['roughnessFactor'] as num?) ?? 1).toDouble(),
      imageIndex: imageIndex,
      blend: m['alphaMode'] == 'BLEND',
      doubleSided: (m['doubleSided'] as bool?) ?? false,
    );
  }

  List<GlbImage> _images() => [
    for (final im in _list('images').cast<Map<String, dynamic>>())
      if (im['bufferView'] is int)
        GlbImage(
          mimeType: (im['mimeType'] as String?) ?? 'image/png',
          bytes: Uint8List.fromList(_view(im['bufferView'] as int)),
        )
      else
        throw const GlbFormatException('external images are not supported'),
  ];

  GlbModel read() {
    final materials = _materials();
    final nodes = _list('nodes').cast<Map<String, dynamic>>();
    final scenes = _list('scenes');
    final rootIds = scenes.isEmpty
        ? List<int>.generate(nodes.length, (i) => i)
        : ((scenes[(json['scene'] as int?) ?? 0] as Map<String, dynamic>)['nodes']
                  as List<dynamic>)
              .cast<int>();
    final parts = <GlbPart>[];
    final min = Float32List.fromList([double.infinity, double.infinity, double.infinity]);
    final max = Float32List.fromList([-double.infinity, -double.infinity, -double.infinity]);

    void visit(int id, _Mat4 parent) {
      final node = nodes[id];
      final world = parent.multiply(_Mat4.ofNode(node));
      final meshIndex = node['mesh'] as int?;
      if (meshIndex != null) {
        final mesh = _list('meshes')[meshIndex] as Map<String, dynamic>;
        final name = (node['name'] as String?) ?? (mesh['name'] as String?) ?? 'mesh $meshIndex';
        final primitives = (mesh['primitives'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (var p = 0; p < primitives.length; p++) {
          final part = _primitive(primitives[p], world, materials, primitives.length > 1 ? '$name #$p' : name);
          if (part == null) continue;
          parts.add(part);
          for (var i = 0; i < part.positions.length; i += 3) {
            for (var k = 0; k < 3; k++) {
              final v = part.positions[i + k];
              if (v < min[k]) min[k] = v;
              if (v > max[k]) max[k] = v;
            }
          }
        }
      }
      for (final child in ((node['children'] as List<dynamic>?) ?? const []).cast<int>()) {
        visit(child, world);
      }
    }

    for (final id in rootIds) {
      visit(id, _Mat4.identity());
    }
    if (parts.isEmpty) throw const GlbFormatException('no triangle meshes');
    return GlbModel(parts: parts, images: _images(), boundsMin: min, boundsMax: max);
  }

  GlbPart? _primitive(
    Map<String, dynamic> prim,
    _Mat4 world,
    List<GlbMaterial> materials,
    String name,
  ) {
    final mode = (prim['mode'] as int?) ?? 4;
    if (mode != 4) return null; // triangles only
    final attrs = prim['attributes'] as Map<String, dynamic>;
    final positionAccessor = attrs['POSITION'] as int?;
    if (positionAccessor == null) return null;
    final positions = world.transformPoints(_floats(positionAccessor, 3));
    final normalAccessor = attrs['NORMAL'] as int?;
    final normals = normalAccessor != null
        ? world.transformNormals(_floats(normalAccessor, 3))
        : _flatNormals(positions, _indices(prim['indices'] as int));
    final materialIndex = prim['material'] as int?;
    final material = materialIndex != null && materialIndex < materials.length
        ? materials[materialIndex]
        : GlbMaterial.fallback;
    final uvAccessor = attrs['TEXCOORD_0'] as int?;
    final uvs = material.imageIndex != null && uvAccessor != null
        ? _floats(uvAccessor, 2)
        : null;
    final indexAccessor = prim['indices'] as int?;
    final indices = indexAccessor != null
        ? _indices(indexAccessor)
        : Uint32List.fromList(List.generate(positions.length ~/ 3, (i) => i));
    return GlbPart(
      name: name,
      positions: positions,
      normals: normals,
      uvs: uvs,
      indices: indices,
      material: material,
    );
  }

  static Float32List _flatNormals(Float32List p, Uint32List idx) {
    final n = Float32List(p.length);
    for (var t = 0; t + 2 < idx.length; t += 3) {
      final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
      final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
      final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
      final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      for (final i in [a, b, c]) {
        n[i] += nx;
        n[i + 1] += ny;
        n[i + 2] += nz;
      }
    }
    for (var i = 0; i < n.length; i += 3) {
      final l = math.sqrt(n[i] * n[i] + n[i + 1] * n[i + 1] + n[i + 2] * n[i + 2]);
      if (l > 0) {
        n[i] /= l;
        n[i + 1] /= l;
        n[i + 2] /= l;
      }
    }
    return n;
  }
}

/// Column-major 4×4, as glTF stores it.
class _Mat4 {
  final Float64List m;
  const _Mat4(this.m);

  factory _Mat4.identity() => _Mat4(
    Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
  );

  factory _Mat4.ofNode(Map<String, dynamic> node) {
    final matrix = (node['matrix'] as List<dynamic>?)?.cast<num>();
    if (matrix != null) {
      return _Mat4(Float64List.fromList(matrix.map((v) => v.toDouble()).toList()));
    }
    final t = (node['translation'] as List<dynamic>?)?.cast<num>() ?? const [0, 0, 0];
    final r = (node['rotation'] as List<dynamic>?)?.cast<num>() ?? const [0, 0, 0, 1];
    final s = (node['scale'] as List<dynamic>?)?.cast<num>() ?? const [1, 1, 1];
    final x = r[0].toDouble(), y = r[1].toDouble(), z = r[2].toDouble(), w = r[3].toDouble();
    final sx = s[0].toDouble(), sy = s[1].toDouble(), sz = s[2].toDouble();
    // Rotation matrix from the unit quaternion, columns scaled — T·R·S.
    return _Mat4(
      Float64List.fromList([
        (1 - 2 * (y * y + z * z)) * sx, (2 * (x * y + z * w)) * sx, (2 * (x * z - y * w)) * sx, 0,
        (2 * (x * y - z * w)) * sy, (1 - 2 * (x * x + z * z)) * sy, (2 * (y * z + x * w)) * sy, 0,
        (2 * (x * z + y * w)) * sz, (2 * (y * z - x * w)) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
        t[0].toDouble(), t[1].toDouble(), t[2].toDouble(), 1,
      ]),
    );
  }

  _Mat4 multiply(_Mat4 o) {
    final out = Float64List(16);
    for (var c = 0; c < 4; c++) {
      for (var r = 0; r < 4; r++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += m[k * 4 + r] * o.m[c * 4 + k];
        }
        out[c * 4 + r] = sum;
      }
    }
    return _Mat4(out);
  }

  Float32List transformPoints(Float32List p) {
    final out = Float32List(p.length);
    for (var i = 0; i < p.length; i += 3) {
      final x = p[i], y = p[i + 1], z = p[i + 2];
      out[i] = m[0] * x + m[4] * y + m[8] * z + m[12];
      out[i + 1] = m[1] * x + m[5] * y + m[9] * z + m[13];
      out[i + 2] = m[2] * x + m[6] * y + m[10] * z + m[14];
    }
    return out;
  }

  /// Rotates normals by the upper 3×3 and renormalises; correct for the
  /// uniform-or-none scaling a Blender export of a rigid object carries.
  Float32List transformNormals(Float32List n) {
    final out = Float32List(n.length);
    for (var i = 0; i < n.length; i += 3) {
      final x = n[i], y = n[i + 1], z = n[i + 2];
      var ox = m[0] * x + m[4] * y + m[8] * z;
      var oy = m[1] * x + m[5] * y + m[9] * z;
      var oz = m[2] * x + m[6] * y + m[10] * z;
      final l = math.sqrt(ox * ox + oy * oy + oz * oz);
      if (l > 0) {
        ox /= l;
        oy /= l;
        oz /= l;
      }
      out[i] = ox;
      out[i + 1] = oy;
      out[i + 2] = oz;
    }
    return out;
  }
}
