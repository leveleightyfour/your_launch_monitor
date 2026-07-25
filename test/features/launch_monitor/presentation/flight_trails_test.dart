import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';

const _par3 = HoleSetup(enabled: true, greenDistance: 165);
const _longer = HoleSetup(enabled: true, greenDistance: 190);
const _narrower = HoleSetup(enabled: true, greenDistance: 165, fairwayWidth: 20);

ShotData _shot({
  int? dbId,
  String clubId = '7i',
  HoleSetup? hole,
  double ballSpeed = 120,
}) =>
    ShotData(
      dbId: dbId,
      clubId: clubId,
      ballSpeed: ballSpeed,
      spinRate: 6500,
      spinAxis: 0,
      launchDirection: 0,
      launchAngle: 18,
      clubSpeed: 85,
      hole: hole,
    );

void main() {
  group('sameTargetTrails', () {
    test('shows other shots with the same club and the same target', () {
      final subject = _shot(dbId: 1, hole: _par3);
      final shots = [subject, _shot(dbId: 2, hole: _par3), _shot(dbId: 3, hole: _par3)];

      final trails = sameTargetTrails(shots, subject);

      expect(trails.shown.length, 2);
      expect(trails.hiddenByTarget, 0);
    });

    test('never includes the subject itself', () {
      final subject = _shot(dbId: 1, hole: _par3);
      final trails = sameTargetTrails([subject], subject);

      expect(trails.shown, isEmpty);
      expect(trails.hiddenByTarget, 0);
    });

    test('an equal row for the same shot is still the subject', () {
      // Tag edits rebuild the row, so identity alone is not enough.
      final subject = _shot(dbId: 1, hole: _par3);
      final rebuilt = _shot(dbId: 1, hole: _par3);

      expect(sameTargetTrails([rebuilt], subject).shown, isEmpty);
    });

    test('hides shots played to a different green, and counts them', () {
      final subject = _shot(dbId: 1, hole: _par3);
      final shots = [
        subject,
        _shot(dbId: 2, hole: _par3),
        _shot(dbId: 3, hole: _longer),
        _shot(dbId: 4, hole: _longer),
      ];

      final trails = sameTargetTrails(shots, subject);

      expect(trails.shown.length, 1);
      expect(trails.hiddenByTarget, 2);
    });

    test('matching is exact — a narrower fairway is a different target', () {
      // The fairway width changes how the ball rolls, so those shots did not
      // cover the same ground even though the green is in the same place.
      final subject = _shot(dbId: 1, hole: _par3);
      final shots = [subject, _shot(dbId: 2, hole: _narrower)];

      final trails = sameTargetTrails(shots, subject);

      expect(trails.shown, isEmpty);
      expect(trails.hiddenByTarget, 1);
    });

    test('other clubs are not trails and are not counted as hidden', () {
      final subject = _shot(dbId: 1, hole: _par3);
      final shots = [
        subject,
        _shot(dbId: 2, clubId: 'dr', hole: _par3),
        _shot(dbId: 3, clubId: 'dr', hole: _longer),
      ];

      final trails = sameTargetTrails(shots, subject);

      expect(trails.shown, isEmpty);
      expect(trails.hiddenByTarget, 0,
          reason: 'a different club is not a hidden trail, it is another club');
    });

    test('shots with no target match each other', () {
      final subject = _shot(dbId: 1);
      final shots = [subject, _shot(dbId: 2), _shot(dbId: 3, hole: _par3)];

      final trails = sameTargetTrails(shots, subject);

      expect(trails.shown.length, 1);
      expect(trails.hiddenByTarget, 1);
    });

    test('the limit caps what is drawn but not what is counted hidden', () {
      final subject = _shot(dbId: 0, hole: _par3);
      final shots = [
        subject,
        for (var i = 1; i <= 20; i++) _shot(dbId: i, hole: _par3),
        for (var i = 21; i <= 23; i++) _shot(dbId: i, hole: _longer),
      ];

      final trails = sameTargetTrails(shots, subject, limit: 12);

      expect(trails.shown.length, 12);
      expect(trails.hiddenByTarget, 3);
    });
  });

  group('isSameShot', () {
    test('matches on database id once persisted', () {
      expect(isSameShot(_shot(dbId: 5), _shot(dbId: 5)), isTrue);
      expect(isSameShot(_shot(dbId: 5), _shot(dbId: 6)), isFalse);
    });

    test('falls back to identity before a shot is persisted', () {
      final unsaved = _shot();

      expect(isSameShot(unsaved, unsaved), isTrue);
      expect(isSameShot(unsaved, _shot()), isFalse);
    });

    test('null is only the same as null', () {
      expect(isSameShot(null, null), isTrue);
      expect(isSameShot(_shot(dbId: 1), null), isFalse);
    });
  });
}
