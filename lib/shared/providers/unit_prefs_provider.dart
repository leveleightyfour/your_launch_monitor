import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DistanceUnit { meters, yards }

enum SpeedUnit { mph, kmh }

// ── UnitPrefs ─────────────────────────────────────────────────────────────────

class UnitPrefs {
  final DistanceUnit distance;
  final SpeedUnit speed;

  const UnitPrefs({
    this.distance = DistanceUnit.meters,
    this.speed = SpeedUnit.mph,
  });

  UnitPrefs copyWith({DistanceUnit? distance, SpeedUnit? speed}) => UnitPrefs(
    distance: distance ?? this.distance,
    speed: speed ?? this.speed,
  );

  /// Display label for distance values.
  String get distLabel => distance == DistanceUnit.meters ? 'm' : 'yds';

  /// Display label for speed values.
  String get speedLabel => speed == SpeedUnit.kmh ? 'km/h' : 'mph';

  /// Convert a value stored in yards to the display unit.
  double dist(double yards) =>
      distance == DistanceUnit.meters ? yards * 0.9144 : yards;

  /// Convert a value stored in mph to the display unit.
  double spd(double mph) => speed == SpeedUnit.kmh ? mph * 1.60934 : mph;

  Map<String, String> toJson() => {
    'distance': distance.name,
    'speed': speed.name,
  };

  factory UnitPrefs.fromJson(Map<String, dynamic> j) => UnitPrefs(
    distance: DistanceUnit.values.firstWhere(
      (e) => e.name == j['distance'],
      orElse: () => DistanceUnit.meters,
    ),
    speed: SpeedUnit.values.firstWhere(
      (e) => e.name == j['speed'],
      orElse: () => SpeedUnit.mph,
    ),
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final unitPrefsProvider = NotifierProvider<UnitPrefsNotifier, UnitPrefs>(
  UnitPrefsNotifier.new,
);

class UnitPrefsNotifier extends Notifier<UnitPrefs> {
  static const _fileName = 'unit_prefs.json';

  @override
  UnitPrefs build() {
    _load();
    return const UnitPrefs();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        state = UnitPrefs.fromJson(json);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode(state.toJson()));
    } catch (_) {}
  }

  void setDistance(DistanceUnit unit) {
    state = state.copyWith(distance: unit);
    _save();
  }

  void setSpeed(SpeedUnit unit) {
    state = state.copyWith(speed: unit);
    _save();
  }
}
