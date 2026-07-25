import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';

/// The hole currently configured to play into. Persisted alongside the unit
/// preferences.
///
/// Shots capture whichever hole was set when they were hit, so changing this
/// does not rewrite history — see [HoleSetup].
final holeSetupProvider = NotifierProvider<HoleSetupNotifier, HoleSetup>(
  HoleSetupNotifier.new,
);

class HoleSetupNotifier extends Notifier<HoleSetup> {
  static const _fileName = 'hole_setup.json';

  @override
  HoleSetup build() {
    _load();
    return HoleSetup.off;
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        state = HoleSetup.fromJson(json);
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

  void _update(HoleSetup next) {
    final clamped = next.clamped;
    if (clamped == state) return;
    state = clamped;
    _save();
  }

  void setEnabled(bool enabled) => _update(state.copyWith(enabled: enabled));

  void setGreenDistance(double yards) =>
      _update(state.copyWith(greenDistance: yards));

  void setGreenWidth(double yards) =>
      _update(state.copyWith(greenWidth: yards));

  void setGreenDepth(double yards) =>
      _update(state.copyWith(greenDepth: yards));

  void setGreenOffset(double yards) =>
      _update(state.copyWith(greenOffset: yards));

  void setFairwayWidth(double yards) =>
      _update(state.copyWith(fairwayWidth: yards));

  void replace(HoleSetup setup) => _update(setup);
}
