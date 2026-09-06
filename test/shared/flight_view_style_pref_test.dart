import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

void main() {
  test('older and unknown preferences keep the existing renderer', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {'flightViewStyle': 'future-renderer'},
      {'flightViewStyle': null},
    ]) {
      expect(UnitPrefs.fromJson(json).flightViewStyle, FlightViewStyle.classic);
    }
  });

  test(
    'both styles survive the persisted JSON and unrelated settings edits',
    () {
      for (final style in FlightViewStyle.values) {
        final prefs = const UnitPrefs()
            .copyWith(flightViewStyle: style)
            .copyWith(distance: DistanceUnit.yards, skyScene: SkyScene.dusk);
        final restored = UnitPrefs.fromJson(
          jsonDecode(jsonEncode(prefs.toJson())),
        );
        expect(restored.flightViewStyle, style);
        expect(restored.distance, DistanceUnit.yards);
        expect(restored.skyScene, SkyScene.dusk);
        expect(restored.copyWith(speed: SpeedUnit.kmh).flightViewStyle, style);
      }
    },
  );
}
