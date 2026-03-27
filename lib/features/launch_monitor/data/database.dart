// ── Drift database ────────────────────────────────────────────────────────────
//
// After editing this file, regenerate with:
//   flutter pub get
//   dart run build_runner build --delete-conflicting-outputs
//
// The generated file (database.g.dart) is produced by drift_dev and must
// exist before the app will compile. The IDE errors shown before generation
// are expected and will disappear once build_runner has run.

// ignore_for_file: type=lint
import 'dart:ui' show Color;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart'
    as domain;
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/tag.dart';

part 'database.g.dart';

// ── Table definitions ─────────────────────────────────────────────────────────

/// @DataClassName avoids clashing with the domain [domain.Session] entity.
@DataClassName('ActivityRow')
class Activities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// @DataClassName avoids clashing with any future Shot domain class.
@DataClassName('ShotRow')
class Shots extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// CASCADE delete — removing an activity removes all its shots.
  IntColumn get activityId =>
      integer().references(Activities, #id, onDelete: KeyAction.cascade)();

  TextColumn get clubId => text().nullable()();

  // ── Ball data ─────────────────────────────────────────────────────────────
  RealColumn get ballSpeed => real()();
  RealColumn get spinRate => real()();
  RealColumn get spinAxis => real()();
  RealColumn get launchDirection => real()();
  RealColumn get launchAngle => real()();

  // ── Club data ─────────────────────────────────────────────────────────────
  RealColumn get clubSpeed => real()();

  // ── Optional — decoded from BLE once protocol is known ───────────────────
  RealColumn get apex => real().nullable()();
  RealColumn get run => real().nullable()();
  RealColumn get swingPath => real().nullable()();
  RealColumn get faceAngle => real().nullable()();
  RealColumn get angleOfAttack => real().nullable()();
  RealColumn get dynamicLoft => real().nullable()();
  RealColumn get horizontalImpact => real().nullable()();
  RealColumn get verticalImpact => real().nullable()();

  // ── Tags ──────────────────────────────────────────────────────────────────
  /// Comma-separated tag IDs, e.g. "1,3,7". Empty string = no tags.
  TextColumn get tagIds =>
      text().withDefault(const Constant(''))();
}

/// @DataClassName avoids clashing with the domain [Tag] entity.
@DataClassName('TagRow')
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  /// Stored as ARGB integer — reconstruct with Color(colorValue).
  IntColumn get colorValue => integer()();
}

/// Persists the player's current club bag.
@DataClassName('SavedClubRow')
class SavedClubs extends Table {
  /// Matches [Club.id] — natural primary key (e.g. 'dr', '7i').
  TextColumn get id => text()();
  TextColumn get shortName => text()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get model => text().nullable()();
  /// Color stored as ARGB integer — reconstruct with Color(colorValue).
  IntColumn get colorValue => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── Database ──────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [Activities, Shots, Tags, SavedClubs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(shots, shots.tagIds);
            await m.createTable(tags);
          }
          if (from < 3) {
            await m.createTable(savedClubs);
          }
        },
      );

  // ── Club bag persistence ──────────────────────────────────────────────────

  /// Loads the persisted club bag. Returns an empty list on first launch.
  Future<List<Club>> getSavedClubs() async {
    final rows = await select(savedClubs).get();
    return rows
        .map((r) => Club(
              id: r.id,
              shortName: r.shortName,
              manufacturer: r.manufacturer,
              model: r.model,
              color: Color(r.colorValue),
            ))
        .toList();
  }

  /// Replaces the persisted bag with the current in-memory state.
  Future<void> saveAllClubs(List<Club> clubs) async {
    await transaction(() async {
      await delete(savedClubs).go();
      for (final c in clubs) {
        await into(savedClubs).insert(SavedClubsCompanion.insert(
          id: c.id,
          shortName: c.shortName,
          manufacturer: Value(c.manufacturer),
          model: Value(c.model),
          colorValue: c.color.toARGB32(),
        ));
      }
    });
  }

  // ── Tag queries ───────────────────────────────────────────────────────────

  Future<List<Tag>> getAllTags() async {
    final rows = await select(tags).get();
    return rows.map(_toDomainTag).toList();
  }

  Future<Tag> insertTag(String name, Color color) async {
    final id = await into(tags).insert(
      TagsCompanion.insert(name: name, colorValue: color.toARGB32()),
    );
    return Tag(id: id, name: name, color: color);
  }

  Future<void> deleteTag(int id) =>
      (delete(tags)..where((t) => t.id.equals(id))).go();

  // ── Shot tag updates ──────────────────────────────────────────────────────

  /// Overwrites the tagIds for a single shot row.
  Future<void> updateShotTagIds(int shotId, List<int> tagIds) {
    return (update(shots)..where((s) => s.id.equals(shotId))).write(
      ShotsCompanion(tagIds: Value(tagIds.join(','))),
    );
  }

  // ── Live-session helpers ──────────────────────────────────────────────────

  /// Creates a placeholder activity row for the in-progress session and returns
  /// its DB ID. The name can be updated later with [finalizeSession].
  Future<int> saveDraftSession(DateTime createdAt) =>
      into(activities).insert(
        ActivitiesCompanion.insert(name: '', createdAt: createdAt),
      );

  /// Inserts a single shot, returning the shot with its [ShotData.dbId] set.
  Future<ShotData> insertShot(int activityId, ShotData shot) async {
    final id = await into(shots).insert(_toShotCompanion(activityId, shot));
    return shot.copyWith(dbId: id);
  }

  /// Sets the final name for a session created via [saveDraftSession].
  Future<void> finalizeSession(int id, String name) =>
      (update(activities)..where((a) => a.id.equals(id)))
          .write(ActivitiesCompanion(name: Value(name)));

  // ── Session queries ───────────────────────────────────────────────────────

  /// Returns all sessions (with their shots), most recent first.
  Future<List<domain.Session>> getAllSessions() async {
    final rows = await select(activities).get();
    final result = <domain.Session>[];
    for (final row in rows) {
      final shotRows = await (select(shots)
            ..where((s) => s.activityId.equals(row.id)))
          .get();
      result.add(_toDomainSession(row, shotRows));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Persists a completed [domain.Session] and all its shots.
  Future<int> saveSession(domain.Session session) {
    return transaction(() async {
      final actId = await into(activities).insert(
        ActivitiesCompanion.insert(
          name: session.name,
          createdAt: session.createdAt,
        ),
      );
      for (final shot in session.shots) {
        await into(shots).insert(_toShotCompanion(actId, shot));
      }
      return actId;
    });
  }

  Future<void> deleteSession(int id) =>
      (delete(activities)..where((a) => a.id.equals(id))).go();

  // ── Row → domain mappers ──────────────────────────────────────────────────

  domain.Session _toDomainSession(ActivityRow row, List<ShotRow> shotRows) {
    return domain.Session(
      id: row.id.toString(),
      name: row.name,
      createdAt: row.createdAt,
      shots: shotRows.map(_toDomainShot).toList(),
    );
  }

  ShotData _toDomainShot(ShotRow row) {
    final tagIdList = row.tagIds.isEmpty
        ? <int>[]
        : row.tagIds.split(',').map(int.parse).toList();
    return ShotData(
      dbId: row.id,
      clubId: row.clubId,
      ballSpeed: row.ballSpeed,
      spinRate: row.spinRate,
      spinAxis: row.spinAxis,
      launchDirection: row.launchDirection,
      launchAngle: row.launchAngle,
      clubSpeed: row.clubSpeed,
      apex: row.apex,
      run: row.run,
      swingPath: row.swingPath,
      faceAngle: row.faceAngle,
      angleOfAttack: row.angleOfAttack,
      dynamicLoft: row.dynamicLoft,
      horizontalImpact: row.horizontalImpact,
      verticalImpact: row.verticalImpact,
      tagIds: tagIdList,
    );
  }

  ShotsCompanion _toShotCompanion(int activityId, ShotData shot) {
    return ShotsCompanion.insert(
      activityId: activityId,
      clubId: Value(shot.clubId),
      ballSpeed: shot.ballSpeed,
      spinRate: shot.spinRate,
      spinAxis: shot.spinAxis,
      launchDirection: shot.launchDirection,
      launchAngle: shot.launchAngle,
      clubSpeed: shot.clubSpeed,
      apex: Value(shot.apex),
      run: Value(shot.run),
      swingPath: Value(shot.swingPath),
      faceAngle: Value(shot.faceAngle),
      angleOfAttack: Value(shot.angleOfAttack),
      dynamicLoft: Value(shot.dynamicLoft),
      horizontalImpact: Value(shot.horizontalImpact),
      verticalImpact: Value(shot.verticalImpact),
      tagIds: Value(shot.tagIds.join(',')),
    );
  }

  Tag _toDomainTag(TagRow row) =>
      Tag(id: row.id, name: row.name, color: Color(row.colorValue));
}

// ── SQLite connection ─────────────────────────────────────────────────────────

QueryExecutor _openConnection() {
  // drift_flutter picks the right SQLite backend per platform automatically.
  return driftDatabase(name: 'omni_sniffer');
}
