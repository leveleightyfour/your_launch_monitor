import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';

/// A 10x20 hole with a 2x2 green block around (5, 15).
HoleGrid _hole() {
  var g = HoleGrid.blank(cellSize: 5, width: 50, length: 100);
  for (var r = 14; r <= 15; r++) {
    for (var c = 4; c <= 5; c++) {
      g = g.withCell(c, r, Terrain.green);
    }
  }
  return g;
}

void main() {
  group('placing', () {
    test('a pin sticks to a green cell, at its centre', () {
      final g = _hole().withPin(5, 15);
      expect(g.hasPin, isTrue);
      expect(g.pinCentre, isNotNull);
      // Col 5 of 10, 5-yard cells: left edge -25, centre of col 5 at 2.5.
      expect(g.pinCentre!.$1, closeTo(2.5, 1e-9));
      expect(g.pinCentre!.$2, closeTo(77.5, 1e-9));
    });

    test('anything but green refuses the pin', () {
      final g = _hole();
      expect(g.withPin(0, 0).hasPin, isFalse); // rough
      expect(g.withPin(-1, 3).hasPin, isFalse); // off the grid
    });

    test('withoutPin lifts it', () {
      expect(_hole().withPin(5, 15).withoutPin().hasPin, isFalse);
    });
  });

  group('the pin never stands anywhere but green', () {
    test('painting the pin cell away takes the pin with it', () {
      final g = _hole().withPin(5, 15).withCell(5, 15, Terrain.bunker);
      expect(g.hasPin, isFalse);
    });

    test('repainting the pin cell green keeps it', () {
      final g = _hole().withPin(5, 15).withCell(5, 15, Terrain.green);
      expect(g.hasPin, isTrue);
    });

    test('a block wipe over the pin drops it', () {
      final g = _hole().withPin(5, 15).withBlock(3, 13, 6, 16, Terrain.water);
      expect(g.hasPin, isFalse);
    });

    test('a block wipe elsewhere leaves it standing', () {
      final g = _hole().withPin(5, 15).withBlock(0, 0, 2, 5, Terrain.bunker);
      expect(g.hasPin, isTrue);
    });
  });

  group('resizing', () {
    test('widening keeps the pin on the same ground', () {
      final before = _hole().withPin(5, 15);
      final ground = before.pinCentre!;
      final after = before.widened();
      expect(after.hasPin, isTrue);
      expect(after.pinCentre!.$1, closeTo(ground.$1, 1e-9));
      expect(after.pinCentre!.$2, closeTo(ground.$2, 1e-9));
      expect(after.at(after.pinCol!, after.pinRow!), Terrain.green);
    });

    test('shortening past the pin drops it', () {
      // Pin at row 15; two shortening steps take the hole to 100 - 2x50 =
      // well short of it.
      final g = _hole().withPin(5, 15).shortened().shortened();
      expect(g.hasPin, isFalse);
    });

    test('extending leaves the pin alone', () {
      expect(_hole().withPin(5, 15).extended().hasPin, isTrue);
    });

    test('resampling re-places the pin at its old ground', () {
      final before = _hole().withPin(5, 15);
      final ground = before.pinCentre!;
      final after = before.resized(2.5);
      expect(after.hasPin, isTrue);
      expect(after.pinCentre!.$1, closeTo(ground.$1, 2.5));
      expect(after.pinCentre!.$2, closeTo(ground.$2, 2.5));
      expect(after.at(after.pinCol!, after.pinRow!), Terrain.green);
    });
  });

  group('round-tripping', () {
    test('the pin survives json', () {
      final g = _hole().withPin(5, 15);
      final back = HoleGrid.fromJson(g.toJson());
      expect(back.pinCol, 5);
      expect(back.pinRow, 15);
      expect(back, g);
    });

    test('a stored pin off the green is dropped on read', () {
      final json = _hole().withPin(5, 15).toJson();
      json['pc'] = 0;
      json['pr'] = 0; // rough
      expect(HoleGrid.fromJson(json).hasPin, isFalse);
    });

    test('no pin stores no pin', () {
      final json = _hole().toJson();
      expect(json.containsKey('pc'), isFalse);
      expect(HoleGrid.fromJson(json).hasPin, isFalse);
    });
  });
}
