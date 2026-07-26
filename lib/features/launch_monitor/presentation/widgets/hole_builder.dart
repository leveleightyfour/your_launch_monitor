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
    // Open looking at the tee — a hole gets built from where it is played
    // from. `reverse` was doing the opposite, and only a render showed it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
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
              _widthBar(),
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

  /// Widen or narrow the hole. Both edges move together, so the target line
  /// stays down the middle.
  Widget _widthBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            // Plus/minus rather than unfold chevrons: same stepper meaning,
            // and these glyphs are already in the shipped release's icon
            // font, so the control renders on Shorebird-patched installs.
            _stepButton(
              Icons.remove,
              label: 'Narrow hole',
              _grid.cols <= HoleGrid.minCols
                  ? null
                  : () => setState(() {
                        _push();
                        _grid = _grid.narrowed();
                      }),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.prefs.dist(_grid.width).round()} '
                '${widget.prefs.distLabel} wide',
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.mono(size: 11, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            _stepButton(
              Icons.add,
              label: 'Widen hole',
              _grid.cols >= HoleGrid.maxCols
                  ? null
                  : () => setState(() {
                        _push();
                        _grid = _grid.widened();
                      }),
            ),
          ],
        ),
      );

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
            return Column(
              children: [
                // Offsets from the target line, pinned above the plan rather
                // than drawn on it. On the plan they scrolled away with the
                // ground, so they were only ever visible at the end of the
                // hole you were not shaping.
                SizedBox(
                  height: 15,
                  width: constraints.maxWidth,
                  child: CustomPaint(
                    painter: _WidthRulerPainter(_grid, widget.prefs),
                  ),
                ),
                Expanded(child: _scrollingPlan(planSize)),
              ],
            );
          },
        ),
      );

  Widget _scrollingPlan(Size planSize) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                controller: _scroll,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _paintAt(d.localPosition, planSize, starting: true),
                  onPanStart: (d) =>
                      _paintAt(d.localPosition, planSize, starting: true),
                  onPanUpdate: (d) =>
                      _paintAt(d.localPosition, planSize, starting: false),
                  child: CustomPaint(
                    painter: _PlanPainter(_grid, widget.prefs),
                    size: planSize,
                    child: SizedBox(
                      width: planSize.width,
                      height: planSize.height,
                    ),
                  ),
                ),
              ),
            );
  }

  /// Extend or shorten the hole. The far end moves; the tee stays put.
  Widget _lengthBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            _stepButton(
              Icons.remove,
              label: 'Shorten hole',
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
              label: 'Extend hole',
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
                          color: t.planColor,
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

  /// [quarterTurns] rotates the glyph. The fold icons read vertically, which
  /// is right for length and wrong for width — the arrows should point along
  /// the axis the button actually changes.
  /// [label] names what the button does. The four steppers share two glyphs
  /// between them, so the icon alone identifies neither the axis nor the
  /// direction — to a screen reader, and to anything else asking.
  Widget _stepButton(
    IconData icon,
    VoidCallback? onTap, {
    required String label,
    int quarterTurns = 0,
  }) =>
      Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: Icon(
              icon,
              size: 17,
              color: onTap == null ? AppColors.textDimmed : AppColors.textMuted,
            ),
          ),
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
/// Spacing between labelled distance lines, in the unit being displayed.
///
/// Round numbers only, and never so many that the plan turns into a ruler:
/// the step grows with the hole so a 600-yard par 5 gets the same handful of
/// lines a pitch-and-putt does.
double distanceMarkerStep(double lengthInDisplayUnits) {
  for (final step in const [10.0, 25.0, 50.0, 100.0]) {
    if (lengthInDisplayUnits / step <= 8) return step;
  }
  return 200.0;
}

class _PlanPainter extends CustomPainter {
  final HoleGrid grid;
  final UnitPrefs prefs;

  _PlanPainter(this.grid, this.prefs);

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
          Paint()..color = grid.at(col, row).planColor,
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

    _paintDistances(canvas, size);
  }

  /// Distance from the tee, so a green or a carry can be placed on a number
  /// rather than by counting squares.
  ///
  /// Measured in whatever unit the profile is set to, which is not the unit
  /// the grid is stored in — the marks land wherever that distance actually
  /// falls, not on a cell boundary.
  void _paintDistances(Canvas canvas, Size size) {
    final totalDisplay = prefs.dist(grid.length);
    final step = distanceMarkerStep(totalDisplay);

    for (var d = step; d < totalDisplay; d += step) {
      // Display units back to yards, then to a fraction of the hole, so the
      // line sits at the true distance rather than the nearest square.
      final y = size.height * (1 - prefs.toYards(d) / grid.length);
      if (y < 8 || y > size.height - 4) continue;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.targetLine.withAlpha(60)
          ..strokeWidth = 1,
      );

      final label = TextPainter(
        text: TextSpan(
          text: '${d.round()}',
          style: AppTextStyles.mono(size: 9, color: AppColors.textPrimary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // A plate behind the number: it has to stay readable over sand, water
      // and dark rough alike, and those are very different backgrounds.
      final plate = Rect.fromLTWH(
        4,
        y - label.height / 2 - 1.5,
        label.width + 8,
        label.height + 3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(plate, const Radius.circular(3)),
        Paint()..color = AppColors.background.withAlpha(190),
      );
      label.paint(canvas, Offset(8, y - label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      old.grid != grid || old.prefs.distance != prefs.distance;
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

/// Offsets from the target line, as a fixed strip above the plan.
///
/// Labelled unsigned and mirrored: shaping a hole is about how far a boundary
/// sits from the middle, not which side of the middle it is on.
class _WidthRulerPainter extends CustomPainter {
  final HoleGrid grid;
  final UnitPrefs prefs;

  _WidthRulerPainter(this.grid, this.prefs);

  @override
  void paint(Canvas canvas, Size size) {
    final halfDisplay = prefs.dist(grid.width / 2);
    final step = distanceMarkerStep(halfDisplay * 2);
    final mid = size.width / 2;

    // The centre gets a tick too — it is the line everything is measured from.
    canvas.drawLine(
      Offset(mid, size.height - 5),
      Offset(mid, size.height),
      Paint()
        ..color = AppColors.targetLine.withAlpha(110)
        ..strokeWidth = 1,
    );

    for (var d = step; d <= halfDisplay; d += step) {
      final dx = size.width * (prefs.toYards(d) / grid.width);
      for (final x in [mid - dx, mid + dx]) {
        if (x < 6 || x > size.width - 6) continue;

        canvas.drawLine(
          Offset(x, size.height - 4),
          Offset(x, size.height),
          Paint()
            ..color = AppColors.targetLine.withAlpha(70)
            ..strokeWidth = 1,
        );

        final label = TextPainter(
          text: TextSpan(
            text: '${d.round()}',
            style: AppTextStyles.mono(size: 8, color: AppColors.textDimmed),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Skip a label that would overlap the edge of the strip rather than
        // letting two numbers collide.
        if (x - label.width / 2 < 0 || x + label.width / 2 > size.width) {
          continue;
        }
        label.paint(canvas, Offset(x - label.width / 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_WidthRulerPainter old) =>
      old.grid.width != grid.width || old.prefs.distance != prefs.distance;
}
