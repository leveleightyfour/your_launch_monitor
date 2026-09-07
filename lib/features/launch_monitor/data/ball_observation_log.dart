/// A record of every place this monitor has seen a ball, and whether it called
/// it ready there.
///
/// Exists because the ready zone cannot be worked out from documentation. The
/// manual quotes it as 25 cm square, 5 cm to the side of the launch monitor and
/// 35 cm in front — but those offsets are measured from the device's body,
/// while the coordinates on the wire are measured from the middle of its field
/// of view, out on the mat. Applying one to the other put the zone in the wrong
/// place every time it was tried.
///
/// The device does know, though: its light goes solid green exactly when the
/// ball is in the zone. So rather than infer, this watches. Every frame is a
/// sample — a position, and whether the monitor called it ready there — and
/// after a few sessions of ordinary use the boundary draws itself.
///
/// Positions are bucketed to [bucketMm] so the log stays small and so a ball
/// sitting still doesn't drown the interesting samples. Each bucket keeps how
/// often it was seen ready and how often merely detected, which is what
/// separates the zone from the mat around it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Grid resolution, in millimetres. Fine enough to place a 25 cm zone edge to
/// within a ball's width, coarse enough that a session is a few hundred
/// buckets rather than tens of thousands.
const int bucketMm = 10;

/// One square of mat, and what the monitor has said about balls sitting in it.
class BallObservation {
  final int depthMm;
  final int lateralMm;

  /// Frames where the monitor reported the ball ready — inside the zone.
  final int readyCount;

  /// Frames where it saw the ball but did not call it ready.
  final int detectedCount;

  const BallObservation({
    required this.depthMm,
    required this.lateralMm,
    this.readyCount = 0,
    this.detectedCount = 0,
  });

  /// Whether the monitor has ever called a ball ready here. One sighting is
  /// enough to say the zone reaches this square; the counts are for judging how
  /// firmly, since a single frame could be a boundary flicker.
  bool get everReady => readyCount > 0;

  BallObservation plus({required bool ready}) => BallObservation(
    depthMm: depthMm,
    lateralMm: lateralMm,
    readyCount: readyCount + (ready ? 1 : 0),
    detectedCount: detectedCount + (ready ? 0 : 1),
  );

  Map<String, dynamic> toJson() => {
    'd': depthMm,
    'l': lateralMm,
    'r': readyCount,
    'n': detectedCount,
  };

  factory BallObservation.fromJson(Map<String, dynamic> j) => BallObservation(
    depthMm: (j['d'] as num).toInt(),
    lateralMm: (j['l'] as num).toInt(),
    readyCount: (j['r'] as num?)?.toInt() ?? 0,
    detectedCount: (j['n'] as num?)?.toInt() ?? 0,
  );
}

/// The log itself: buckets keyed by their grid square.
class BallObservationLog {
  final Map<String, BallObservation> _buckets;

  BallObservationLog([Map<String, BallObservation>? buckets])
    : _buckets = buckets ?? {};

  static String _key(int depth, int lateral) => '$depth:$lateral';

  static int _bucket(double mm) => (mm / bucketMm).round() * bucketMm;

  Iterable<BallObservation> get observations => _buckets.values;

  int get bucketCount => _buckets.length;

  int get frameCount =>
      _buckets.values.fold(0, (n, o) => n + o.readyCount + o.detectedCount);

  /// Squares the monitor has called a ball ready in — the zone, as measured
  /// rather than as documented.
  Iterable<BallObservation> get readySquares =>
      _buckets.values.where((o) => o.everReady);

  /// Record one frame. Only frames where a ball was actually seen belong here:
  /// an empty mat says nothing about where the zone is.
  ///
  /// Mutates rather than returning a new log. This runs on every sensor frame,
  /// and copying a few hundred buckets ten times a second to satisfy
  /// immutability would be work done for nobody — nothing watches this
  /// continuously, it is read when the panel opens or the log is exported.
  void record({
    required double depthMm,
    required double lateralMm,
    required bool ready,
  }) {
    final d = _bucket(depthMm);
    final l = _bucket(lateralMm);
    final key = _key(d, l);
    _buckets[key] =
        (_buckets[key] ?? BallObservation(depthMm: d, lateralMm: l)).plus(
          ready: ready,
        );
  }

  /// The bounding box of everywhere a ball has been seen, and of everywhere it
  /// has been called ready. Null when nothing has been recorded yet.
  ({double minDepth, double maxDepth, double minLateral, double maxLateral})?
  extentOf(Iterable<BallObservation> of) {
    if (of.isEmpty) return null;
    var minD = double.infinity, maxD = double.negativeInfinity;
    var minL = double.infinity, maxL = double.negativeInfinity;
    for (final o in of) {
      if (o.depthMm < minD) minD = o.depthMm.toDouble();
      if (o.depthMm > maxD) maxD = o.depthMm.toDouble();
      if (o.lateralMm < minL) minL = o.lateralMm.toDouble();
      if (o.lateralMm > maxL) maxL = o.lateralMm.toDouble();
    }
    return (
      minDepth: minD,
      maxDepth: maxD,
      minLateral: minL,
      maxLateral: maxL,
    );
  }

  String toJsonString() => jsonEncode({
    'bucketMm': bucketMm,
    'observations': [for (final o in _buckets.values) o.toJson()],
  });

  factory BallObservationLog.fromJsonString(String s) {
    final json = jsonDecode(s) as Map<String, dynamic>;
    final list = (json['observations'] as List?) ?? const [];
    final buckets = <String, BallObservation>{};
    for (final entry in list) {
      final o = BallObservation.fromJson(entry as Map<String, dynamic>);
      buckets[_key(o.depthMm, o.lateralMm)] = o;
    }
    return BallObservationLog(buckets);
  }

  /// A human-readable dump: the two extents, then every square. Written as text
  /// rather than JSON because the point is to be read and reasoned about.
  String report() {
    final buf = StringBuffer()
      ..writeln('Ball position log')
      ..writeln('Bucket size: ${bucketMm}mm')
      ..writeln('Squares: $bucketCount   Frames: $frameCount')
      ..writeln();

    final seen = extentOf(observations);
    final ready = extentOf(readySquares);
    if (seen != null) {
      buf.writeln(
        'Seen at all:  depth ${seen.minDepth.toInt()}..${seen.maxDepth.toInt()}'
        '   side ${seen.minLateral.toInt()}..${seen.maxLateral.toInt()}',
      );
    }
    buf.writeln(
      ready == null
          ? 'Called ready: never — no ball has been in the zone yet'
          : 'Called ready: depth ${ready.minDepth.toInt()}..${ready.maxDepth.toInt()}'
                '   side ${ready.minLateral.toInt()}..${ready.maxLateral.toInt()}',
    );
    buf
      ..writeln()
      ..writeln('depth,side,ready,detected');

    final sorted = _buckets.values.toList()
      ..sort((a, b) {
        final d = b.depthMm.compareTo(a.depthMm);
        return d != 0 ? d : a.lateralMm.compareTo(b.lateralMm);
      });
    for (final o in sorted) {
      buf.writeln(
        '${o.depthMm},${o.lateralMm},${o.readyCount},${o.detectedCount}',
      );
    }
    return buf.toString();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  static const _fileName = 'ball_observations.json';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<BallObservationLog> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return BallObservationLog();
      return BallObservationLog.fromJsonString(await file.readAsString());
    } catch (_) {
      return BallObservationLog();
    }
  }

  Future<void> save() async {
    try {
      await (await _file()).writeAsString(toJsonString());
    } catch (_) {}
  }

  static Future<void> erase() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
