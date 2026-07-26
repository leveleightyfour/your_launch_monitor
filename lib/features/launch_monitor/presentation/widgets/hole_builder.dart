/// Paint a hole cell by cell.
///
/// A top-down plan of the hole, tee at the bottom, with a terrain palette.
/// Pick a terrain, then tap or drag over the plan to lay it down. Every stroke
/// changes what the ball actually does, because the same grid the editor
/// writes is the one the flight model reads.
library;

import 'package:flutter/material.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_grid.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Opens the builder and returns the hole that was painted, or null if the
/// player backed out.
Future<HoleSetup?> showHoleBuilder(
  BuildContext context, {
  required HoleSetup hole,
  required UnitPrefs prefs,
}) {
  return showModalBottomSheet<HoleSetup>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => HoleBuilderSheet(hole: hole, prefs: prefs),
  );
}

class HoleBuilderSheet extends StatefulWidget {
  final HoleSetup hole;
  final UnitPrefs prefs;

  const HoleBuilderSheet({super.key, required this.hole, required this.prefs});

  @override
  State<HoleBuilderSheet> createState() => HoleBuilderSheetState();
}

/// Public so a test can reach [currentGrid]; nothing else should touch it.
class HoleBuilderSheetState extends State<HoleBuilderSheet> {
  late HoleGrid _grid;
  Terrain _brush = Terrain.fairway;

  /// Undo is a stack of whole grids rather than a diff. A hole is small enough
  /// that copying it is free, and painting is the kind of thing people undo a
  /// lot of.
  final List<HoleGrid> _history = [];

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Opening the builder on a hole that was only ever described by numbers
    // seeds the grid from that description, so the fairway and green already
    // there are the starting point rather than a blank sheet.
    _grid = widget.hole.grid ??
        seedHoleGrid(widget.hole, cellSize: _cellSize);
  }

  /// Five squares in whatever unit the profile is set to.
  double get _cellSize => HoleGrid.cellSizeForUnit(
        metric: widget.prefs.distance == DistanceUnit.meters,
      );

  /// The grid being edited. Exposed so the painting rules can be tested
  /// without reaching through the widget tree.
  @visibleForTesting
  HoleGrid get currentGrid => _grid;

  void _push() {
    _history.add(_grid);
    // Deep history is not worth the memory on a phone.
    if (_history.length > 40) _history.removeAt(0);
  }

  void _paintAt(Offset local, Size size, {required bool starting}) {
    final cell = _cellAt(local, size);
    if (cell == null) return;
    final (col, row) = cell;
    if (_grid.at(col, row) == _brush) return;
    setState(() {
      if (starting) _push();
      _grid = _grid.withCell(col, row, _brush);
    });
  }

  /// Which cell a point on the plan falls in. Row 0 is the tee, drawn at the
  /// bottom, so the vertical axis is flipped.
  (int, int)? _cellAt(Offset local, Size size) {
    final cw = size.width / _grid.cols;
    final ch = size.height / _grid.rows;
    final col = (local.dx / cw).floor();
    final row = ((size.height - local.dy) / ch).floor();
    if (col < 0 || col >= _grid.cols || row < 0 || row >= _grid.rows) {
      return null;
    }
    return (col, row);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Fixed height, whatever the hole is. The plan scrolls inside it, so a
    // 600-yard par 5 opens the same size as a pitch-and-putt and the palette
    // and action row never move.
    final sheetHeight = media.size.height * 0.82;

    return SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              _lengthBar(),
              Expanded(child: _plan()),
              const SizedBox(height: 10),
              _palette(),
              _actions(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// The plan, scrolling vertically.
  ///
  /// Cell size on screen comes from the width, so the hole always fits across
  /// and grows downwards — which is the axis that varies. The view starts at
  /// the tee, since that is where a hole gets built from.
  Widget _plan() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellPx = constraints.maxWidth / _grid.cols;
            final planSize = Size(constraints.maxWidth, cellPx * _grid.rows);
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                controller: _scroll,
                // Reversed so offset zero is the tee end at the bottom.
                reverse: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _paintAt(d.localPosition, planSize, starting: true),
                  onPanStart: (d) =>
                      _paintAt(d.localPosition, planSize, starting: true),
                  onPanUpdate: (d) =>
                      _paintAt(d.localPosition, planSize, starting: false),
                  child: CustomPaint(
                    painter: _PlanPainter(_grid),
                    size: planSize,
                    child: SizedBox(
                      width: planSize.width,
                      height: planSize.height,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  /// Extend or shorten the hole. The far end moves; the tee stays put.
  Widget _lengthBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            _stepButton(
              Icons.remove,
              _grid.rows <= HoleGrid.minRows
                  ? null
                  : () => setState(() {
                        _push();
                        _grid = _grid.shortened();
                      }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.prefs.dist(_grid.length).round()} '
                '${widget.prefs.distLabel} to the far end',
                textAlign: TextAlign.center,
                style: AppTextStyles.mono(
                    size: 11, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            _stepButton(
              Icons.add,
              _grid.rows >= HoleGrid.maxRows
                  ? null
                  : () => setState(() {
                        _push();
                        _grid = _grid.extended();
                      }),
            ),
          ],
        ),
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text('Hole builder',
                  style:
                      AppTextStyles.sans(size: 16, weight: FontWeight.w600)),
            ),
            Text(
              '${_grid.cols}×${_grid.rows}',
              style: AppTextStyles.mono(size: 11, color: AppColors.textDimmed),
            ),
            IconButton(
              icon: const Icon(Icons.undo, size: 18),
              color: _history.isEmpty
                  ? AppColors.textDimmed
                  : AppColors.textMuted,
              onPressed: _history.isEmpty
                  ? null
                  : () => setState(() => _grid = _history.removeLast()),
            ),
          ],
        ),
      );

  Widget _palette() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final t in Terrain.values)
              GestureDetector(
                onTap: () => setState(() => _brush = t),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _brush == t
                          ? context.accent
                          : AppColors.border,
                      width: _brush == t ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: t.surfaceColor,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: AppColors.border2),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(t.label, style: AppTextStyles.sans(size: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _stepButton(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            icon,
            size: 17,
            color: onTap == null ? AppColors.textDimmed : AppColors.textMuted,
          ),
        ),
      );

  Widget _actions(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: AppTextStyles.sans(
                      size: 13, color: AppColors.textMuted)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _push();
                _grid = HoleGrid.blank(
                  cellSize: _grid.cellSize,
                  width: _grid.width,
                  length: _grid.length,
                );
              }),
              child: Text('Clear',
                  style: AppTextStyles.sans(
                      size: 13, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.accent),
              onPressed: () => Navigator.of(context).pop(
                widget.hole.copyWith(enabled: true, grid: _grid),
              ),
              child: Text('Use hole',
                  style: AppTextStyles.sans(
                      size: 13, weight: FontWeight.w600, color: Colors.black)),
            ),
          ],
        ),
      );
}

/// Top-down plan of the grid. Tee at the bottom, target line up the middle.
class _PlanPainter extends CustomPainter {
  final HoleGrid grid;

  _PlanPainter(this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / grid.cols;
    final ch = size.height / grid.rows;

    for (var row = 0; row < grid.rows; row++) {
      // Row 0 is the tee and belongs at the bottom of the plan.
      final top = size.height - (row + 1) * ch;
      for (var col = 0; col < grid.cols; col++) {
        canvas.drawRect(
          Rect.fromLTWH(col * cw, top, cw + 0.5, ch + 0.5),
          Paint()..color = grid.at(col, row).surfaceColor,
        );
      }
    }

    // Cell lines, but only while they are far enough apart to be a guide
    // rather than a grey wash over the whole plan.
    if (cw > 5) {
      final line = Paint()
        ..color = AppColors.border.withAlpha(90)
        ..strokeWidth = 0.5;
      for (var col = 1; col < grid.cols; col++) {
        canvas.drawLine(
            Offset(col * cw, 0), Offset(col * cw, size.height), line);
      }
      for (var row = 1; row < grid.rows; row++) {
        final y = size.height - row * ch;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }

    // Target line, so left and right mean something while painting.
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = AppColors.targetLine.withAlpha(70)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.grid != grid;
}

/// Turn an analytic hole into a grid to start editing from.
///
/// Opening the builder on a hole that was only ever described by numbers
/// should show that hole, not a blank sheet — the fairway and green already
/// set up are the starting point. Every cell asks the analytic hole its own
/// question, so the seed is exactly what the player had.
HoleGrid seedHoleGrid(
  HoleSetup hole, {
  double cellSize = HoleGrid.defaultCellSize,
}) {
  // Long enough to hold the green with room past it, wide enough to miss.
  final length = (hole.greenDistance + 80).clamp(120.0, 700.0).toDouble();
  final grid = HoleGrid.blank(
    cellSize: cellSize,
    width: 140,
    length: length,
  );
  final cells = <Terrain>[];
  for (var row = 0; row < grid.rows; row++) {
    for (var col = 0; col < grid.cols; col++) {
      final x = grid.left + (col + 0.5) * grid.cellSize;
      final z = (row + 0.5) * grid.cellSize;
      cells.add(hole.enabled ? hole.terrainAt(x, z) : Terrain.rough);
    }
  }
  return HoleGrid(
    cellSize: grid.cellSize,
    cols: grid.cols,
    rows: grid.rows,
    cells: cells,
  );
}
