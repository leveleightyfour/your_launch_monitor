import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/saved_hole.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';

SavedHole _hole() {
  var grid = HoleGrid.blank(cellSize: 5, width: 50, length: 100);
  grid = grid
      .withCell(4, 15, Terrain.green)
      .withCell(5, 15, Terrain.green)
      .withCell(2, 10, Terrain.water)
      .withPin(5, 15);
  return SavedHole(
    name: 'Road Hole',
    savedAt: DateTime(2026, 7, 27, 12),
    hole: const HoleSetup(
      enabled: true,
      greenDistance: 80,
    ).copyWith(grid: grid),
  );
}

void main() {
  group('the shared document', () {
    test('survives the round trip, grid and pin included', () {
      final original = _hole();
      final decoded = SavedHole.tryDecode(original.encodeShareText());
      expect(decoded, isNotNull);
      expect(decoded!.name, 'Road Hole');
      expect(decoded.hole.grid, original.hole.grid);
      expect(decoded.hole.grid!.pinCol, 5);
      expect(decoded.hole.grid!.pinRow, 15);
      expect(decoded.hole.grid!.terrainAt(-12.5, 52.5), Terrain.water);
    });

    test('declares what it is', () {
      final json = _hole().toJson();
      expect(json[SavedHole.magicKey], SavedHole.formatVersion);
    });

    test('rejects text that is not a hole', () {
      expect(SavedHole.tryDecode('hello'), isNull);
      expect(SavedHole.tryDecode('{"a": 1}'), isNull);
      expect(SavedHole.tryDecode('[1, 2]'), isNull);
      expect(SavedHole.tryDecode(''), isNull);
    });

    test('rejects a document with no name', () {
      final json = _hole().toJson()..['name'] = '  ';
      expect(SavedHole.tryDecode(json.toString()), isNull);
    });

    test('tolerates surrounding whitespace from messengers', () {
      final text = '\n  ${_hole().encodeShareText()}  \n';
      expect(SavedHole.tryDecode(text), isNotNull);
    });
  });

  group('uniqueName', () {
    test('keeps a free name', () {
      expect(SavedHole.uniqueName('Road Hole', ['Island']), 'Road Hole');
    });

    test('counts past taken names', () {
      expect(
        SavedHole.uniqueName('Road Hole', ['Road Hole', 'Road Hole (2)']),
        'Road Hole (3)',
      );
    });

    test('an empty name becomes Hole', () {
      expect(SavedHole.uniqueName('  ', []), 'Hole');
    });
  });
}
