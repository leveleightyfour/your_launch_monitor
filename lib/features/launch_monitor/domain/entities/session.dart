import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

/// A completed or in-progress session of shots.
class Session {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<ShotData> shots;

  const Session({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.shots,
  });

  int get shotCount => shots.length;

  /// The club id that appeared most often in this session.
  String? get dominantClubId {
    if (shots.isEmpty) return null;
    final counts = <String, int>{};
    for (final s in shots) {
      if (s.clubId != null) counts[s.clubId!] = (counts[s.clubId!] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
