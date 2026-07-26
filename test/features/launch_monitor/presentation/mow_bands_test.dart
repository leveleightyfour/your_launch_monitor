import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';
import 'package:omni_sniffer/shared/theme.dart';

void main() {
  group('mown bands line up whatever the fairway is doing', () {
    test('a lane covers the same ground regardless of fairway width', () {
      // The bug: bands were anchored to the fairway edge, so narrowing the
      // fairway slid the whole pattern sideways and the stripes jumped at
      // every pinch. A lane is a strip of ground; it does not care how wide
      // the mown part is there.
      const t = Terrain.fairway;
      for (final x in [-18.0, -7.5, -2.0, 0.0, 3.0, 11.0, 22.5]) {
        // Same x, asked over and over — nothing about width enters into it.
        expect(isMowBand(x, t), isMowBand(x, t));
      }
      // Concretely: x = 3 is in the first lane right of the line, x = 7 is in
      // the second, whatever the fairway happens to be doing at that distance.
      expect(isMowBand(3, t), isTrue);
      expect(isMowBand(7, t), isFalse);
    });

    test('the pattern is symmetric about the target line', () {
      // Anchoring at grid column zero put the phase wherever the grid's left
      // edge landed, so a symmetrically narrowed fairway came out lopsided.
      const t = Terrain.fairway;
      final w = mowLaneWidthYards(t);
      for (var i = 1; i <= 8; i++) {
        final x = (i - 0.5) * w;
        expect(
          isMowBand(x, t),
          isNot(isMowBand(-x, t)),
          reason: 'lanes at ±$x should be opposite bands, mirrored on the line',
        );
      }
    });

    test('bands alternate, and do so at the lane width', () {
      const t = Terrain.fairway;
      final w = mowLaneWidthYards(t);
      var previous = isMowBand(0.5 * w, t);
      for (var lane = 1; lane < 10; lane++) {
        final here = isMowBand((lane + 0.5) * w, t);
        expect(here, isNot(previous), reason: 'lane $lane did not alternate');
        previous = here;
      }
    });

    test('a point keeps its band no matter how the grid is diced', () {
      // Cell size follows the unit preference, so the same hole is 5.0-yard
      // cells for one player and 5.4681 for another. The mowing must not
      // change with it.
      const t = Terrain.fairway;
      for (final x in [-12.3, -4.0, 1.1, 6.7, 19.9]) {
        expect(isMowBand(x, t), (x / 5.0).floor().isEven);
      }
    });
  });

  group('the green is not mown like a fairway', () {
    test('its bands are narrower', () {
      expect(mowLaneWidthYards(Terrain.green),
          lessThan(mowLaneWidthYards(Terrain.fairway)));
    });

    test('its bands are not the collar', () {
      // The collar is the ring between putting surface and surround. Using it
      // as the green's own mown band made half the green read as collar.
      expect(Terrain.green.stripeColor, isNot(AppColors.turfGreenCollar));
      expect(Terrain.green.stripeColor, AppColors.turfGreenStripe);
    });

    test('its banding is a whisper next to the fairway\'s', () {
      double lum(c) =>
          0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
      final greenGap =
          (lum(Terrain.green.stripeColor) - lum(Terrain.green.surfaceColor))
              .abs();
      final collarGap =
          (lum(AppColors.turfGreenCollar) - lum(Terrain.green.surfaceColor))
              .abs();

      // Still visible...
      expect(greenGap, greaterThan(0.005));
      // ...but nothing like the jump to the collar, which is a real edge.
      expect(greenGap, lessThan(collarGap * 0.6));
    });

    test('only mown surfaces are banded at all', () {
      for (final t in Terrain.values) {
        final banded = t == Terrain.fairway || t == Terrain.green;
        expect(
          t.stripeColor == t.surfaceColor,
          !banded,
          reason: '${t.name} banding is wrong way round',
        );
      }
    });
  });
}
