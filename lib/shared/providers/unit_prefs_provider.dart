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

/// The 3D flight view's sky, picked from curated scenes rather than a free
/// colour: each choice pairs the sky with matching turf so the shot tracer
/// and markers stay readable under all of them.
enum SkyScene {
  day('Day'),
  morning('Morning'),
  overcast('Overcast'),
  dusk('Dusk'),
  night('Night');

  const SkyScene(this.label);

  final String label;
}

/// One camera slot's remembered configuration. Slot 0 is the primary angle,
/// slot 1 the second camera; an empty [deviceName] means the slot is vacant.
class CameraSlotPref {
  final String deviceName;

  /// Requested capture size. Zero means the camera's default mode.
  final int width;
  final int height;

  const CameraSlotPref({this.deviceName = '', this.width = 0, this.height = 0});

  bool get isEmpty => deviceName.isEmpty;

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'width': width,
    'height': height,
  };

  factory CameraSlotPref.fromJson(Map<String, dynamic> j) => CameraSlotPref(
    deviceName: j['deviceName'] as String? ?? '',
    width: j['width'] as int? ?? 0,
    height: j['height'] as int? ?? 0,
  );
}

class UnitPrefs {
  final DistanceUnit distance;
  final SpeedUnit speed;
  final DispersionStandard dispersionStandard;

  /// When `true`, the app silently reconnects to the last known launch
  /// monitor on startup.
  final bool autoReconnect;

  /// When `true`, the session screen shows the ⚡ test-shot button that
  /// injects a jittered seed shot — used for visualisation testing without
  /// the physical device. Off by default.
  final bool showTestShotButton;

  /// Which sky the 3D flight view renders under. Each choice is a full
  /// coordinated scene (sky plus turf), not just a backdrop colour.
  final SkyScene skyScene;

  /// The split view's pane choices, stored by pane-enum name so the
  /// screens' private enums stay private. Unknown names fall back to the
  /// screen's own default.
  ///
  /// The third pane only renders on layouts wide enough for it (desktop and
  /// ultra-wide — see `supportsThirdSplitPane`), but its choice is remembered
  /// everywhere so resizing back out restores it.
  final String splitLeftPane;
  final String splitRightPane;
  final String splitThirdPane;

  /// The Camera tab's two slots — device and capture mode per angle, so a
  /// down-the-line and a face-on camera each reopen on their own settings.
  final List<CameraSlotPref> cameraSlots;

  const UnitPrefs({
    this.distance = DistanceUnit.meters,
    this.speed = SpeedUnit.mph,
    this.dispersionStandard = DispersionStandard.trackman,
    this.autoReconnect = true,
    this.showTestShotButton = false,
    this.skyScene = SkyScene.day,
    this.splitLeftPane = 'table',
    this.splitRightPane = 'dispersion',
    this.splitThirdPane = 'optimizer',
    this.cameraSlots = const [CameraSlotPref(), CameraSlotPref()],
  });

  UnitPrefs copyWith({
    DistanceUnit? distance,
    SpeedUnit? speed,
    DispersionStandard? dispersionStandard,
    bool? autoReconnect,
    bool? showTestShotButton,
    SkyScene? skyScene,
    String? splitLeftPane,
    String? splitRightPane,
    String? splitThirdPane,
    List<CameraSlotPref>? cameraSlots,
  }) => UnitPrefs(
    distance: distance ?? this.distance,
    speed: speed ?? this.speed,
    dispersionStandard: dispersionStandard ?? this.dispersionStandard,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    showTestShotButton: showTestShotButton ?? this.showTestShotButton,
    skyScene: skyScene ?? this.skyScene,
    splitLeftPane: splitLeftPane ?? this.splitLeftPane,
    splitRightPane: splitRightPane ?? this.splitRightPane,
    splitThirdPane: splitThirdPane ?? this.splitThirdPane,
    cameraSlots: cameraSlots ?? this.cameraSlots,
  );

  /// Display label for distance values.
  String get distLabel => distance == DistanceUnit.meters ? 'm' : 'yds';

  /// Display label for speed values.
  String get speedLabel => speed == SpeedUnit.kmh ? 'km/h' : 'mph';

  /// Convert a value stored in yards to the display unit.
  double dist(double yards) =>
      distance == DistanceUnit.meters ? yards * 0.9144 : yards;

  /// Inverse of [dist] — a value the user typed or stepped, back to yards.
  double toYards(double displayValue) =>
      distance == DistanceUnit.meters ? displayValue / 0.9144 : displayValue;

  /// Convert a value stored in mph to the display unit.
  double spd(double mph) => speed == SpeedUnit.kmh ? mph * 1.60934 : mph;

  Map<String, dynamic> toJson() => {
    'distance': distance.name,
    'speed': speed.name,
    'dispersionStandard': dispersionStandard.name,
    'autoReconnect': autoReconnect,
    'showTestShotButton': showTestShotButton,
    'skyScene': skyScene.name,
    'splitLeftPane': splitLeftPane,
    'splitRightPane': splitRightPane,
    'splitThirdPane': splitThirdPane,
    'cameraSlots': cameraSlots.map((slot) => slot.toJson()).toList(),
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
    autoReconnect: j['autoReconnect'] as bool? ?? true,
    showTestShotButton: j['showTestShotButton'] as bool? ?? false,
    skyScene: SkyScene.values.firstWhere(
      (e) => e.name == j['skyScene'],
      orElse: () => SkyScene.day,
    ),
    splitLeftPane: j['splitLeftPane'] as String? ?? 'table',
    splitRightPane: j['splitRightPane'] as String? ?? 'dispersion',
    splitThirdPane: j['splitThirdPane'] as String? ?? 'optimizer',
    cameraSlots: _slotsFromJson(j),
  );

  /// Reads the slot list, padding to two entries; a prefs file written
  /// before slots existed migrates its single camera into slot 0.
  static List<CameraSlotPref> _slotsFromJson(Map<String, dynamic> j) {
    final raw = j['cameraSlots'];
    final slots = <CameraSlotPref>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          slots.add(CameraSlotPref.fromJson(entry));
        }
      }
    } else {
      final legacy = j['cameraDeviceName'] as String? ?? '';
      if (legacy.isNotEmpty) {
        slots.add(
          CameraSlotPref(
            deviceName: legacy,
            width: j['cameraWidth'] as int? ?? 0,
            height: j['cameraHeight'] as int? ?? 0,
          ),
        );
      }
    }
    while (slots.length < 2) {
      slots.add(const CameraSlotPref());
    }
    return List.unmodifiable(slots);
  }
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

  void setSkyScene(SkyScene scene) {
    state = state.copyWith(skyScene: scene);
    _save();
  }

  void setSplitPanes({String? left, String? right, String? third}) {
    state = state.copyWith(
      splitLeftPane: left,
      splitRightPane: right,
      splitThirdPane: third,
    );
    _save();
  }

  /// Updates one camera slot, keeping whatever isn't passed. A null
  /// [deviceName] clears the slot so the tab stops reopening a camera the
  /// golfer closed.
  void setCameraSlot(int slot, {String? deviceName, int? width, int? height}) {
    if (slot < 0) return;
    final slots = [...state.cameraSlots];
    while (slots.length <= slot) {
      slots.add(const CameraSlotPref());
    }
    final current = slots[slot];
    slots[slot] = CameraSlotPref(
      deviceName: deviceName ?? current.deviceName,
      width: width ?? current.width,
      height: height ?? current.height,
    );
    state = state.copyWith(cameraSlots: List.unmodifiable(slots));
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

  void setAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnect: enabled);
    _save();
  }

  void setShowTestShotButton(bool enabled) {
    state = state.copyWith(showTestShotButton: enabled);
    _save();
  }
}
