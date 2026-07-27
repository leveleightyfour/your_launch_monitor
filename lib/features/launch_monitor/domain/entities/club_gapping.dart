import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';

/// Robust per-club carry statistics for the bag's Distances tab.
///
/// Outliers are fenced with the standard Tukey rule: carries more than
/// 1.5 × IQR outside the quartiles are excluded from the stats, never from
/// the data — callers show how many were fenced, so a hidden shot is always
/// accounted for. With fewer than four shots there is no meaningful
/// distribution to fence, so everything is kept.
class ClubCarryStats {
  final Club club;

  /// Carries inside the fence, sorted ascending.
  final List<double> kept;

  /// Carries the fence excluded, sorted ascending.
  final List<double> excluded;

  const ClubCarryStats._(this.club, this.kept, this.excluded);

  factory ClubCarryStats.fromCarries(
    Club club,
    Iterable<double> carries, {
    bool includeOutliers = false,
  }) {
    final sorted = carries.toList()..sort();
    if (sorted.length < 4 || includeOutliers) {
      return ClubCarryStats._(club, sorted, const []);
    }
    final q1 = quantile(sorted, 0.25);
    final q3 = quantile(sorted, 0.75);
    final iqr = q3 - q1;
    final lo = q1 - 1.5 * iqr;
    final hi = q3 + 1.5 * iqr;
    final kept = <double>[];
    final excluded = <double>[];
    for (final c in sorted) {
      (c < lo || c > hi ? excluded : kept).add(c);
    }
    return ClubCarryStats._(club, kept, excluded);
  }

  int get totalCount => kept.length + excluded.length;
  bool get hasData => kept.isNotEmpty;

  double get median => quantile(kept, 0.5);
  double get average =>
      kept.isEmpty ? 0 : kept.reduce((a, b) => a + b) / kept.length;
  double get shortest => kept.isEmpty ? 0 : kept.first;
  double get longest => kept.isEmpty ? 0 : kept.last;
}

/// Linear-interpolated quantile of an ascending-sorted list.
double quantile(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0;
  final pos = (sorted.length - 1) * q;
  final lower = pos.floor();
  final upper = pos.ceil();
  if (lower == upper) return sorted[lower];
  final frac = pos - lower;
  return sorted[lower] * (1 - frac) + sorted[upper] * frac;
}
