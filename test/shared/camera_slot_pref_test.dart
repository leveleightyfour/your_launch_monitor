/// A camera slot's orientation is remembered across launches, so the golfer
/// sets the rig up once. These pin the serialisation: the mirror has to
/// survive a round trip, and prefs written before the mirror existed have to
/// keep loading rather than resetting the whole slot.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

void main() {
  test('a mirrored slot survives a round trip', () {
    const pref = CameraSlotPref(
      deviceName: 'FaceTime HD Camera',
      width: 1280,
      height: 720,
      fps: 60,
      rotationQuarterTurns: 3,
      mirrored: true,
    );

    final restored = CameraSlotPref.fromJson(pref.toJson());

    expect(restored.deviceName, 'FaceTime HD Camera');
    expect(restored.width, 1280);
    expect(restored.height, 720);
    expect(restored.fps, 60);
    expect(restored.rotationQuarterTurns, 3);
    expect(restored.mirrored, isTrue);
  });

  test('prefs written before the mirror existed still load', () {
    final restored = CameraSlotPref.fromJson({
      'deviceName': 'UVC Camera',
      'width': 1920,
      'height': 1080,
      'fps': 120,
      'rotation': 1,
    });

    expect(restored.deviceName, 'UVC Camera');
    expect(restored.rotationQuarterTurns, 1);
    expect(restored.mirrored, isFalse);
  });

  test('the mirror is off unless it was turned on', () {
    expect(const CameraSlotPref().mirrored, isFalse);
    expect(CameraSlotPref.fromJson(const {}).mirrored, isFalse);
  });
}
