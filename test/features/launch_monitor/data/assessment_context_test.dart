import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/features/launch_monitor/data/database.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_context.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

void main() {
  test(
    'v5 rows migrate as unverified, new context survives insert and update',
    () async {
      final connection = NativeDatabase.memory(
        setup: (db) {
          db.execute(
            '''CREATE TABLE activities (id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, created_at INTEGER NOT NULL, hole_setup TEXT)''',
          );
          db.execute(
            '''CREATE TABLE shots (id INTEGER PRIMARY KEY AUTOINCREMENT,
        activity_id INTEGER NOT NULL, club_id TEXT, ball_speed REAL NOT NULL,
        spin_rate REAL NOT NULL, spin_axis REAL NOT NULL,
        launch_direction REAL NOT NULL, launch_angle REAL NOT NULL,
        club_speed REAL NOT NULL, apex REAL, run REAL, swing_path REAL,
        face_angle REAL, angle_of_attack REAL, dynamic_loft REAL,
        horizontal_impact REAL, vertical_impact REAL, hole_setup TEXT,
        tag_ids TEXT NOT NULL DEFAULT '')''',
          );
          db.execute(
            'CREATE TABLE tags (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color_value INTEGER NOT NULL)',
          );
          db.execute(
            'CREATE TABLE saved_clubs (id TEXT PRIMARY KEY NOT NULL, short_name TEXT NOT NULL, manufacturer TEXT, model TEXT, color_value INTEGER NOT NULL)',
          );
          db.execute(
            "INSERT INTO activities (name,created_at) VALUES ('Old session',0)",
          );
          db.execute(
            '''INSERT INTO shots (activity_id,ball_speed,spin_rate,spin_axis,
        launch_direction,launch_angle,club_speed) VALUES (1,145,2500,0,0,14,100)''',
          );
          db.execute('PRAGMA user_version = 5');
        },
      );
      final db = AppDatabase.forTesting(connection);
      addTearDown(db.close);
      final old = (await db.getAllSessions()).single.shots.single;
      expect(old.ballSpeed, 145);
      expect(old.context.ballSource, MeasurementSource.unknown);
      expect(old.hasUsableLaunch, isFalse);
      const context = ShotContext(
        ballSource: MeasurementSource.measured,
        clubSpeedSource: MeasurementSource.estimated,
        intent: ShotIntent.partial,
        goal: FittingGoal.approach,
        targetCarry: 95,
        trialId: 'persisted-trial',
        candidate: true,
        phase: FittingPhase.confirmation,
        equipment: EquipmentSetup(
          name: 'B',
          head: 'Head',
          shaft: 'Shaft',
          loft: '54',
          length: '35 in',
        ),
        conditions: 'Same premium ball; mat',
      );
      final inserted = await db.insertShot(
        1,
        const ShotData(
          clubId: 'sw',
          ballSpeed: 80,
          spinRate: 7000,
          spinAxis: 0,
          launchDirection: 0,
          launchAngle: 30,
          clubSpeed: 60,
          context: context,
        ),
      );
      await db.updateShot(
        inserted.copyWith(
          clubSpeed: 65,
          context: context.copyWith(
            clubSpeedSource: MeasurementSource.measured,
          ),
        ),
      );
      final restored = (await db.getAllSessions()).single.shots.firstWhere(
        (s) => s.dbId == inserted.dbId,
      );
      expect(restored.clubSpeed, 65);
      expect(
        restored.context.toJson(),
        context.copyWith(clubSpeedSource: MeasurementSource.measured).toJson(),
      );
      expect(
        await db
            .customSelect('PRAGMA user_version')
            .getSingle()
            .then((r) => r.read<int>('user_version')),
        6,
      );
    },
  );
}
