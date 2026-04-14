import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';

/// The club currently being hit — used to tag incoming BLE shots.
/// Completely independent of [selectedShotIndexProvider].
final activeClubProvider = StateProvider<Club?>((ref) => Club.defaults.first);

/// The club currently selected for view filtering (TABLE, TILES, CLUB tabs).
/// Null means "show all clubs".
final selectedClubProvider = StateProvider<Club?>((ref) => null);

/// The index (into allShots) of the shot currently highlighted across the UI.
/// Completely independent of [activeClubProvider] and [selectedClubProvider].
final selectedShotIndexProvider = StateProvider<int>((ref) => 0);

/// The player's club bag. Starts with defaults, then loads persisted state.
final clubsProvider = NotifierProvider<ClubsNotifier, List<Club>>(
  ClubsNotifier.new,
);

class ClubsNotifier extends Notifier<List<Club>> {
  @override
  List<Club> build() {
    _loadFromDb();
    return List.from(Club.defaults);
  }

  Future<void> _loadFromDb() async {
    final saved = await ref.read(appDatabaseProvider).getSavedClubs();
    if (saved.isNotEmpty) state = saved;
  }

  Future<void> _persist() =>
      ref.read(appDatabaseProvider).saveAllClubs(state);

  void updateClubTags(String id, {String? manufacturer, String? model}) {
    state = [
      for (final c in state)
        if (c.id == id) c.copyWith(manufacturer: manufacturer, model: model) else c,
    ];
    _persist();
  }

  void addClub(Club club) {
    state = [...state, club];
    _persist();
  }

  void removeClub(String id) {
    state = state.where((c) => c.id != id).toList();
    _persist();
  }
}

// ── Tile metric selection ─────────────────────────────────────────────────────

/// All displayable metrics. Order here defines the order in the customise sheet.
enum TileMetric {
  // Ball data
  ballSpeed('BALL SPD', 'mph'),
  launchDirection('LAUNCH DIR', 'deg'),
  launchAngle('LAUNCH ANGLE', 'deg'),
  spinRate('SPIN RATE', 'rpm'),
  spinAxis('SPIN AXIS', 'deg'),
  apex('APEX', 'yds'),
  carry('CARRY', 'yds'),
  run('RUN', 'yds'),
  totalDistance('TOTAL DIST', 'yds'),
  // Club data
  clubSpeed('CLUB SPD', 'mph'),
  swingPath('SWING PATH', 'deg'),
  faceAngle('FACE ANGLE', 'deg'),
  angleOfAttack('ANG. ATT.', 'deg'),
  smashFactor('SMASH', ''),
  dynamicLoft('DYN. LOFT', 'deg'),
  impactLocation('IMPACT LOC.', ''),
  horizontalImpact('IMPACT HORIZ', 'mm'),
  verticalImpact('IMPACT VERT', 'mm');

  const TileMetric(this.label, this.unit);

  final String label;
  final String unit;

  static const _defaultMetrics = [
    TileMetric.carry,
    TileMetric.ballSpeed,
    TileMetric.spinRate,
    TileMetric.launchAngle,
    TileMetric.clubSpeed,
    TileMetric.smashFactor,
  ];
}

/// Which tile metrics are currently shown in the Tiles tab.
final selectedTilesProvider = StateProvider<List<TileMetric>>(
  (ref) => TileMetric._defaultMetrics,
);

// ── Table column selection ─────────────────────────────────────────────────────

/// All columns that can appear in the Table view.
enum TableColumn {
  // Ball data
  carry('CARRY', 'yds'),
  ballSpeed('BALL SPD', 'mph'),
  launchAngle('LAUNCH ANG.', 'deg'),
  launchDirection('LAUNCH DIR.', 'deg'),
  offline('OFFLINE', 'yds'),
  spinRate('SPIN RATE', 'rpm'),
  spinAxis('SPIN AXIS', 'deg'),
  apex('APEX', 'yds'),
  run('RUN', 'yds'),
  totalDistance('TOTAL DIST.', 'yds'),
  // Club data
  clubSpeed('CLUB SPD', 'mph'),
  smashFactor('SMASH', ''),
  swingPath('SWING PATH', 'deg'),
  faceAngle('FACE ANGLE', 'deg'),
  angleOfAttack('ANG. ATT.', 'deg'),
  dynamicLoft('DYN. LOFT', 'deg');

  const TableColumn(this.label, this.unit);

  final String label;
  final String unit;

  static const _defaultColumns = [
    TableColumn.carry,
    TableColumn.clubSpeed,
    TableColumn.ballSpeed,
    TableColumn.offline,
    TableColumn.launchAngle,
  ];
}

/// Which columns are currently shown in the Table view.
final selectedTableColumnsProvider = StateProvider<List<TableColumn>>(
  (ref) => TableColumn._defaultColumns,
);
