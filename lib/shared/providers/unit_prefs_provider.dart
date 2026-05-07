import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum DistanceUnit { meters, yards }

enum SpeedUnit { mph, kmh }

/// Statistical convention used to draw dispersion ellipses. The multiplier is
/// applied to the σ in each axis; `1 - exp(-k²/2)` gives the % of shots
/// expected to fall inside the ellipse for a 2D Gaussian.
enum DispersionStandard {
  /// Trackman default — 2σ ellipse, ~86% of shots inside.
  trackman(2.0, 'Trackman', '86%'),

  /// PGA Tour shot-dispersion convention — ~2.15σ, ~90% of shots inside.
  pga(2.146, 'PGA', '90%');

  final double sigmaMultiplier;
  final String label;
  final String confidenceLabel;

  const DispersionStandard(
    this.sigmaMultiplier,
    this.label,
    this.confidenceLabel,
  );
}

// ── UnitPrefs ─────────────────────────────────────────────────────────────────

class UnitPrefs {
  final DistanceUnit distance;
  final SpeedUnit speed;
  final DispersionStandard dispersionStandard;

  const UnitPrefs({
    this.distance = DistanceUnit.meters,
    this.speed = SpeedUnit.mph,
    this.dispersionStandard = DispersionStandard.trackman,
  });

  UnitPrefs copyWith({
    DistanceUnit? distance,
    SpeedUnit? speed,
    DispersionStandard? dispersionStandard,
  }) =>
      UnitPrefs(
        distance: distance ?? this.distance,
        speed: speed ?? this.speed,
        dispersionStandard: dispersionStandard ?? this.dispersionStandard,
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
    'dispersionStandard': dispersionStandard.name,
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
    dispersionStandard: DispersionStandard.values.firstWhere(
      (e) => e.name == j['dispersionStandard'],
      orElse: () => DispersionStandard.trackman,
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

  void setDispersionStandard(DispersionStandard standard) {
    state = state.copyWith(dispersionStandard: standard);
    _save();
  }
}
