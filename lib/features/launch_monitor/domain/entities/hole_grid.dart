/// A hole painted cell by cell, instead of described by a handful of numbers.
///
/// The analytic [HoleSetup] can say "fairway 40 yards wide running to a green
/// at 165". It cannot say "the fairway pinches to 22 yards at the 240 mark,
/// there is water down the right from 180, and the left side is trees". A grid
/// can, and it answers the same question the analytic hole does —
/// `terrainAt(x, z)` — so everything downstream is unchanged.
///
/// Storage is the reason for the run-length encoding. A shot stores a snapshot
/// of the hole it was played to, so a replay always shows what the player was
/// actually aiming at, and a snapshot has to be small enough to sit on every
/// row. A 400x120 yard hole at 5-yard cells is 1,920 cells; almost all of them
/// are the same as their neighbour, so RLE takes a typical hole to well under
/// a hundred bytes.
library;

import 'dart:math' as math;

import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';

class HoleGrid {
  /// Cell edge length in yards.
  final double cellSize;

  /// Cells across, centred on the target line.
  final int cols;

  /// Cells downrange, starting at the tee.
  final int rows;

  /// Row-major, `rows * cols` entries. Row 0 is at the tee.
  final List<Terrain> cells;

  const HoleGrid({
    required this.cellSize,
    required this.cols,
    required this.rows,
    required this.cells,
  });

  static const defaultCellSize = 5.0;
  static const minCellSize = 2.0;
  static const maxCellSize = 25.0;

  static const _yardsPerMetre = 1.0936133;

  /// Cells are always five of whatever the player reads distances in — five
  /// yards, or five metres — rather than a number they have to choose.
  ///
  /// The grid itself is stored in yards, because everything downstream of it
  /// is: the trajectory, the ground models, [HoleSetup]. Only the size of the
  /// square changes with the preference, never the units it is kept in.
  static double cellSizeForUnit({required bool metric}) =>
      metric ? 5 * _yardsPerMetre : 5.0;

  /// How far a hole grows or shrinks by in one press — ten cells, so the
  /// change is worth the tap without overshooting.
  static const lengthStepCells = 10;

  static const minRows = 8;
  static const maxRows = 400;

  /// A copy running to a different distance, keeping everything painted.
  ///
  /// Ground added at the far end starts as rough; ground removed takes
  /// whatever was on it. The tee end never moves, so shortening a hole cannot
  /// silently delete the part the player is standing on.
  HoleGrid withRows(int newRows) {
    final r = newRows.clamp(minRows, maxRows);
    if (r == rows) return this;
    final next = <Terrain>[];
    for (var row = 0; row < r; row++) {
      for (var col = 0; col < cols; col++) {
        next.add(row < rows ? at(col, row) : Terrain.rough);
      }
    }
    return HoleGrid(cellSize: cellSize, cols: cols, rows: r, cells: next);
  }

  HoleGrid extended() => withRows(rows + lengthStepCells);

  HoleGrid shortened() => withRows(rows - lengthStepCells);

  /// Widening adds a column to each side at once, so the step is even and the
  /// target line stays exactly down the middle. An odd step would shift the
  /// centre of the hole every press.
  static const widthStepCells = 2;

  static const minCols = 6;
  static const maxCols = 120;

  /// A copy spanning a different width, keeping everything painted.
  ///
  /// Growth and loss are shared equally between the two sides, because the
  /// target line runs down the centre and everything — the mown bands, the
  /// physics, [left] — is measured from it. Taking cells off one side only
  /// would slide the whole hole sideways under the player.
  ///
  /// New ground at either edge starts as rough.
  HoleGrid withCols(int newCols) {
    final c = newCols.clamp(minCols, maxCols);
    if (c == cols) return this;
    // Positive when growing: how far the old grid sits in from the new left
    // edge. Negative when shrinking, which drops cells off both sides.
    final offset = (c - cols) ~/ 2;
    final next = <Terrain>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < c; col++) {
        final source = col - offset;
        next.add(
          source >= 0 && source < cols ? at(source, row) : Terrain.rough,
        );
      }
    }
    return HoleGrid(cellSize: cellSize, cols: c, rows: rows, cells: next);
  }

  HoleGrid widened() => withCols(cols + widthStepCells);

  HoleGrid narrowed() => withCols(cols - widthStepCells);

  /// A hole wide enough to miss badly on and long enough for a driver.
  factory HoleGrid.blank({
    double cellSize = defaultCellSize,
    double width = 120,
    double length = 400,
    Terrain fill = Terrain.rough,
  }) {
    final c = math.max(1, (width / cellSize).round());
    final r = math.max(1, (length / cellSize).round());
    return HoleGrid(
      cellSize: cellSize,
      cols: c,
      rows: r,
      cells: List.filled(c * r, fill),
    );
  }

  double get width => cols * cellSize;
  double get length => rows * cellSize;

  /// Leftmost edge, in yards from the target line.
  double get left => -width / 2;

  /// Column containing [x], or null when off the grid.
  int? colFor(double x) {
    final i = ((x - left) / cellSize).floor();
    return (i < 0 || i >= cols) ? null : i;
  }

  /// Row containing [z], or null when off the grid.
  int? rowFor(double z) {
    final i = (z / cellSize).floor();
    return (i < 0 || i >= rows) ? null : i;
  }

  Terrain at(int col, int row) => cells[row * cols + col];

  /// The terrain under a point.
  ///
  /// Anywhere off the grid is out of bounds — a built hole has been told where
  /// its edges are, so leaving it means something, unlike the analytic hole
  /// where the world simply carries on as rough.
  Terrain terrainAt(double x, double z) {
    final c = colFor(x);
    final r = rowFor(z);
    if (c == null || r == null) return Terrain.outOfBounds;
    return at(c, r);
  }

  /// A copy with one cell repainted.
  HoleGrid withCell(int col, int row, Terrain terrain) {
    if (col < 0 || col >= cols || row < 0 || row >= rows) return this;
    final next = List<Terrain>.of(cells);
    next[row * cols + col] = terrain;
    return HoleGrid(
      cellSize: cellSize,
      cols: cols,
      rows: rows,
      cells: next,
    );
  }

  /// A copy with a rectangular block repainted — what a drag across the editor
  /// produces.
  HoleGrid withBlock(
    int fromCol,
    int fromRow,
    int toCol,
    int toRow,
    Terrain terrain,
  ) {
    final next = List<Terrain>.of(cells);
    final c0 = math.max(0, math.min(fromCol, toCol));
    final c1 = math.min(cols - 1, math.max(fromCol, toCol));
    final r0 = math.max(0, math.min(fromRow, toRow));
    final r1 = math.min(rows - 1, math.max(fromRow, toRow));
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        next[r * cols + c] = terrain;
      }
    }
    return HoleGrid(
      cellSize: cellSize,
      cols: cols,
      rows: rows,
      cells: next,
    );
  }

  /// Resample onto a different cell size, keeping the ground it covers.
  ///
  /// Nearest-neighbour: the point of changing cell size is to work coarser or
  /// finer, not to blur what is already painted.
  HoleGrid resized(double newCellSize) {
    final size = newCellSize.clamp(minCellSize, maxCellSize).toDouble();
    if (size == cellSize) return this;
    final c = math.max(1, (width / size).round());
    final r = math.max(1, (length / size).round());
    final next = <Terrain>[];
    for (var row = 0; row < r; row++) {
      for (var col = 0; col < c; col++) {
        // Sample at the middle of the new cell so a 2x change lands cleanly.
        final x = left + (col + 0.5) * size;
        final z = (row + 0.5) * size;
        final sc = colFor(x) ?? (x < 0 ? 0 : cols - 1);
        final sr = rowFor(z) ?? (z < 0 ? 0 : rows - 1);
        next.add(at(sc, sr));
      }
    }
    return HoleGrid(cellSize: size, cols: c, rows: r, cells: next);
  }

  /// Cells as runs: `12f8r3w...`, read row-major.
  ///
  /// A count of 1 drops its digits, which is worth it — a hand-painted bunker
  /// edge produces a lot of singletons.
  String encode() {
    if (cells.isEmpty) return '';
    final buf = StringBuffer();
    var run = 1;
    for (var i = 1; i <= cells.length; i++) {
      if (i < cells.length && cells[i] == cells[i - 1]) {
        run++;
        continue;
      }
      if (run > 1) buf.write(run);
      buf.write(cells[i - 1].code);
      run = 1;
    }
    return buf.toString();
  }

  static List<Terrain> _decodeCells(String encoded, int expected) {
    final out = <Terrain>[];
    var digits = '';
    for (final ch in encoded.split('')) {
      if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        digits += ch;
        continue;
      }
      final run = digits.isEmpty ? 1 : int.parse(digits);
      digits = '';
      final terrain = Terrain.fromCode(ch);
      // Guard the run length: a corrupt count must not allocate the world.
      for (var i = 0; i < run && out.length < expected; i++) {
        out.add(terrain);
      }
    }
    // Short or damaged data is padded rather than rejected. A hole that is
    // partly readable still tells the player something; throwing loses the
    // whole shot's context.
    while (out.length < expected) {
      out.add(Terrain.rough);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'cell': cellSize,
        'cols': cols,
        'rows': rows,
        'g': encode(),
      };

  factory HoleGrid.fromJson(Map<String, dynamic> json) {
    final cellSize = (json['cell'] as num?)?.toDouble() ?? defaultCellSize;
    final cols = math.max(1, (json['cols'] as num?)?.toInt() ?? 1);
    final rows = math.max(1, (json['rows'] as num?)?.toInt() ?? 1);
    return HoleGrid(
      cellSize: cellSize.clamp(minCellSize, maxCellSize).toDouble(),
      cols: cols,
      rows: rows,
      cells: _decodeCells(json['g'] as String? ?? '', cols * rows),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoleGrid &&
          cellSize == other.cellSize &&
          cols == other.cols &&
          rows == other.rows &&
          _sameCells(cells, other.cells);

  static bool _sameCells(List<Terrain> a, List<Terrain> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(cellSize, cols, rows, encode());

  @override
  String toString() =>
      'HoleGrid(${cols}x$rows @ ${cellSize}y, ${encode().length}B)';
}
