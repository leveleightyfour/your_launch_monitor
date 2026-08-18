import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/watch_sync_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/data/watch_connectivity_channel.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/watch_tile_payload.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

const _shot = ShotData(
  dbId: 1,
  clubId: '7i',
  ballSpeed: 131.8,
  spinRate: 5500,
  spinAxis: 2.1,
  launchDirection: 1.1,
  launchAngle: 17.3,
  clubSpeed: 92,
  horizontalImpact: 5.2,
  verticalImpact: -3.4,
);

const _slower = ShotData(
  ballSpeed: 121.8,
  spinRate: 6100,
  spinAxis: 1.4,
  launchDirection: -0.6,
  launchAngle: 18.1,
  clubSpeed: 88,
);

const _yards = UnitPrefs(distance: DistanceUnit.yards);
const _metric = UnitPrefs(distance: DistanceUnit.meters, speed: SpeedUnit.kmh);

/// Whether [value] is something WatchConnectivity will carry: strings,
/// numbers, booleans, and lists or maps of the same.
bool _isPropertyList(Object? value) => switch (value) {
  String() || int() || double() || bool() => true,
  List() => value.every(_isPropertyList),
  Map() => value.keys.every((k) => k is String) &&
      value.values.every(_isPropertyList),
  _ => false,
};

void main() {
  group('watchTileFor', () {
    test('carries the phone-formatted number, unit and average', () {
      final avg = ShotData.averageOf([_shot, _slower]);
      final tile = watchTileFor(TileMetric.ballSpeed, _shot, avg, _yards);

      expect(tile.id, 'ballSpeed');
      expect(tile.label, 'BALL SPD');
      expect(tile.value, '131.8');
      expect(tile.unit, 'mph');
      expect(tile.average, '126.8');
      expect(tile.delta, '±5.0');
    });

    test('respects the unit preference the golfer set on the phone', () {
      final tile = watchTileFor(TileMetric.ballSpeed, _shot, null, _metric);

      expect(tile.unit, 'km/h');
      expect(tile.value, '212.1');
      // Nothing to average against yet, so the watch has no footer to draw.
      expect(tile.average, '');
      expect(tile.delta, '');
    });

    test('splits the direction letter off the number', () {
      final tile = watchTileFor(TileMetric.offline, _shot, null, _yards);

      // The watch draws the number full size and the letter beside it at
      // half size, so they have to arrive apart.
      expect(double.tryParse(tile.value), isNotNull);
      expect(tile.unit, 'yds');
      expect(tile.suffix, isNot(matches(RegExp(r'[0-9]'))));
    });

    test('the degree sign stays with the digits', () {
      final tile = watchTileFor(TileMetric.launchAngle, _shot, null, _yards);

      expect(tile.value, '17.3°');
      expect(tile.suffix, '');
    });

    test('impact location travels as two readouts', () {
      final tile = watchTileFor(TileMetric.impactLocation, _shot, _shot, _yards);

      expect(tile.hasSecondary, isTrue);
      expect(tile.value, '5.2 T');
      expect(tile.secondaryLabel, 'VERT');
      expect(tile.secondaryValue, '3.4 L');
    });

    test('a missing metric reads as -- rather than a stale number', () {
      final tile = watchTileFor(TileMetric.swingPath, _shot, null, _yards);

      expect(tile.value, '--');
      expect(tile.delta, '');
    });
  });

  group('WatchTilePayload', () {
    WatchTilePayload payload({int sentAtMs = 0, int shotCount = 2}) =>
        WatchTilePayload(
          connection: WatchConnection.connected,
          tiles: [watchTileFor(TileMetric.carry, _shot, null, _yards)],
          shotCount: shotCount,
          shotIndex: 1,
          club: '7i',
          accent: '#2dd4b0',
          ballReady: true,
          battery: 84,
          sentAtMs: sentAtMs,
        );

    test('crosses to native as property-list types only', () {
      final map = payload(sentAtMs: 1234).toMap();

      expect(map['connection'], 'connected');
      expect(map['club'], '7i');
      expect(map['battery'], 84);
      expect(map['sentAtMs'], 1234);

      final tiles = map['tiles']! as List<Object>;
      final tile = tiles.single as Map<String, Object>;
      expect(tile['label'], 'CARRY');

      // WatchConnectivity refuses anything that isn't property-list
      // encodable, and refuses the whole payload rather than the offending
      // field.
      expect(_isPropertyList(map), isTrue);
    });

    test('an unknown battery is omitted rather than sent as null', () {
      const noBattery = WatchTilePayload(
        connection: WatchConnection.disconnected,
        tiles: [],
        shotCount: 0,
        shotIndex: 0,
        club: '',
        accent: '#2dd4b0',
        ballReady: false,
        sentAtMs: 0,
      );

      expect(noBattery.toMap().containsKey('battery'), isFalse);
    });

    test('the signature ignores the timestamp, so idle state is not resent', () {
      expect(payload(sentAtMs: 1).signature, payload(sentAtMs: 9999).signature);
      expect(
        payload(shotCount: 2).signature,
        isNot(payload(shotCount: 3).signature),
      );
    });

    test('a tag applied on the phone reaches the watch', () {
      const tagged = WatchTilePayload(
        connection: WatchConnection.connected,
        tiles: [],
        shotCount: 1,
        shotIndex: 1,
        club: '7i',
        accent: '#2dd4b0',
        ballReady: false,
        sentAtMs: 0,
        tags: [
          WatchTag(id: 4, name: 'Draw', color: '#22c55e'),
          WatchTag(id: 7, name: 'Thin', color: '#f97316'),
        ],
        shotTags: [4],
        shotId: 42,
      );

      final map = tagged.toMap();
      expect(map['shotId'], 42);
      expect(map['shotTags'], [4]);
      expect(
        (map['tags']! as List).first,
        {'id': 4, 'name': 'Draw', 'color': '#22c55e'},
      );
      expect(_isPropertyList(map), isTrue);

      // Tagging has to move the signature, or the watch would never be told.
      const untagged = WatchTilePayload(
        connection: WatchConnection.connected,
        tiles: [],
        shotCount: 1,
        shotIndex: 1,
        club: '7i',
        accent: '#2dd4b0',
        ballReady: false,
        sentAtMs: 0,
        tags: [
          WatchTag(id: 4, name: 'Draw', color: '#22c55e'),
          WatchTag(id: 7, name: 'Thin', color: '#f97316'),
        ],
        shotId: 42,
      );
      expect(tagged.signature, isNot(untagged.signature));
    });

    test('an unpersisted shot reports as untaggable', () {
      const fresh = WatchTilePayload(
        connection: WatchConnection.connected,
        tiles: [],
        shotCount: 1,
        shotIndex: 1,
        club: '7i',
        accent: '#2dd4b0',
        ballReady: false,
        sentAtMs: 0,
      );

      expect(fresh.toMap()['shotId'], 0);
    });
  });

  group('nextTagIds', () {
    test('adds and removes without disturbing the order', () {
      expect(nextTagIds(const [3, 1], 7, on: true), [3, 1, 7]);
      expect(nextTagIds(const [3, 1, 7], 1, on: false), [3, 7]);
    });

    test('is idempotent, so a repeated command cannot duplicate a tag', () {
      expect(nextTagIds(const [3], 3, on: true), [3]);
      expect(nextTagIds(const [3], 9, on: false), [3]);
    });
  });

  group('WatchCommand', () {
    test('reads a toggle off the wire', () {
      final command = WatchCommand.parse(const {
        'command': 'toggleTag',
        'shotId': 42,
        'tagId': 7,
        'on': true,
      });

      expect(command, isNotNull);
      expect(command!.action, 'toggleTag');
      expect(command.shotId, 42);
      expect(command.tagId, 7);
      expect(command.on, isTrue);
    });

    test('refuses anything that is not a command', () {
      // It arrives from another device; nothing about its shape is assumed.
      expect(WatchCommand.parse(null), isNull);
      expect(WatchCommand.parse('toggleTag'), isNull);
      expect(WatchCommand.parse(const {'shotId': 42}), isNull);
      expect(WatchCommand.parse(const {'command': ''}), isNull);
    });

    test('missing ids read as zero rather than throwing', () {
      final command = WatchCommand.parse(const {'command': 'toggleTag'});

      expect(command!.shotId, 0);
      expect(command.tagId, 0);
      expect(command.on, isFalse);
    });

    test('replies carry an outcome the watch can show', () {
      expect(WatchCommand.success()['ok'], isTrue);
      expect(WatchCommand.failure('Gone')['ok'], isFalse);
      expect(WatchCommand.failure('Gone')['reason'], 'Gone');
    });
  });

  group('WatchLinkState', () {
    test('only syncs once a watch is paired with our app installed', () {
      const ready = WatchLinkState(
        supported: true,
        activated: true,
        paired: true,
        appInstalled: true,
      );
      const noApp = WatchLinkState(
        supported: true,
        activated: true,
        paired: true,
      );

      expect(ready.shouldSync, isTrue);
      expect(noApp.shouldSync, isFalse);
      expect(WatchLinkState.unsupported.shouldSync, isFalse);
    });

    test('reads the map iOS sends back', () {
      final state = WatchLinkState.fromMap(const {
        'supported': true,
        'activated': true,
        'paired': true,
        'appInstalled': false,
        'reachable': false,
      });

      expect(state.paired, isTrue);
      expect(state.appInstalled, isFalse);
      expect(state.reachable, isFalse);
    });
  });
}
