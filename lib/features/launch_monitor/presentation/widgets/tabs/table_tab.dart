import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

const _fCol = 3;
const _shotColW = 28.0;

// ── Column helpers ────────────────────────────────────────────────────────────

double _offlineYds(ShotData s) =>
    s.carry * math.sin(s.launchDirection * math.pi / 180.0);

String _fmtVal(double val, {bool withDir = false, double? rawForDir}) {
  final abs = val.abs();
  if (withDir) {
    final src = rawForDir ?? val;
    if (abs < 0.05) return '0.0';
    return '${abs.toStringAsFixed(1)} ${src < 0 ? 'L' : 'R'}';
  }
  return abs < 0.05 ? '0.0' : abs.toStringAsFixed(1);
}

/// Display unit label for [col] respecting [prefs].
String tableColUnit(TableColumn col, UnitPrefs prefs) => switch (col) {
  TableColumn.ballSpeed || TableColumn.clubSpeed => prefs.speedLabel,
  TableColumn.carry ||
  TableColumn.offline ||
  TableColumn.apex ||
  TableColumn.run ||
  TableColumn.totalDistance => prefs.distLabel,
  _ => col.unit,
};

String tableColumnValue(TableColumn col, ShotData s, UnitPrefs prefs) {
  return switch (col) {
    TableColumn.carry => prefs.dist(s.carry).toStringAsFixed(1),
    TableColumn.ballSpeed => prefs.spd(s.ballSpeed).toStringAsFixed(1),
    TableColumn.launchAngle => '${s.launchAngle.toStringAsFixed(1)}°',
    TableColumn.launchDirection => '${s.launchDirection.toStringAsFixed(1)}°',
    TableColumn.offline => _fmtVal(
        prefs.dist(_offlineYds(s)),
        withDir: true,
        rawForDir: _offlineYds(s),
      ),
    TableColumn.spinRate => s.spinRate.toStringAsFixed(0),
    TableColumn.spinAxis => '${s.spinAxis.toStringAsFixed(1)}°',
    TableColumn.apex =>
      s.apex != null ? prefs.dist(s.apex!).toStringAsFixed(1) : '--',
    TableColumn.run =>
      s.run != null ? prefs.dist(s.run!).toStringAsFixed(1) : '--',
    TableColumn.totalDistance => prefs.dist(s.totalDistance).toStringAsFixed(1),
    TableColumn.clubSpeed => prefs.spd(s.clubSpeed).toStringAsFixed(1),
    TableColumn.smashFactor => s.smashFactor.toStringAsFixed(2),
    TableColumn.swingPath => s.swingPath != null
        ? '${s.swingPath!.abs().toStringAsFixed(1)}° ${s.swingPath! >= 0 ? 'R' : 'L'}'
        : '--',
    TableColumn.faceAngle => s.faceAngle != null
        ? '${s.faceAngle!.abs().toStringAsFixed(1)}° ${s.faceAngle! >= 0 ? 'R' : 'L'}'
        : '--',
    TableColumn.angleOfAttack =>
      s.angleOfAttack != null ? '${s.angleOfAttack!.toStringAsFixed(1)}°' : '--',
    TableColumn.dynamicLoft =>
      s.dynamicLoft != null ? '${s.dynamicLoft!.toStringAsFixed(1)}°' : '--',
  };
}

double _colRaw(TableColumn col, ShotData s, UnitPrefs prefs) {
  return switch (col) {
    TableColumn.carry => prefs.dist(s.carry),
    TableColumn.ballSpeed => prefs.spd(s.ballSpeed),
    TableColumn.launchAngle => s.launchAngle,
    TableColumn.launchDirection => s.launchDirection,
    TableColumn.offline => prefs.dist(_offlineYds(s).abs()),
    TableColumn.spinRate => s.spinRate,
    TableColumn.spinAxis => s.spinAxis,
    TableColumn.apex => s.apex != null ? prefs.dist(s.apex!) : 0,
    TableColumn.run => s.run != null ? prefs.dist(s.run!) : 0,
    TableColumn.totalDistance => prefs.dist(s.totalDistance),
    TableColumn.clubSpeed => prefs.spd(s.clubSpeed),
    TableColumn.smashFactor => s.smashFactor,
    TableColumn.swingPath => s.swingPath?.abs() ?? 0,
    TableColumn.faceAngle => s.faceAngle?.abs() ?? 0,
    TableColumn.angleOfAttack => s.angleOfAttack ?? 0,
    TableColumn.dynamicLoft => s.dynamicLoft ?? 0,
  };
}

// ── Public widget ─────────────────────────────────────────────────────────────

/// Table view for a list of shots.
///
/// Designed to fill a parent with bounded height (e.g. a direct child of
/// [Expanded]). Reads [selectedTableColumnsProvider] to determine visible
/// columns and provides a Customize button to change them.
class TableTab extends ConsumerStatefulWidget {
  final List<ShotData> shots;
  final int? selectedIndex;
  final ValueChanged<int>? onRowTap;
  final Club? club;

  const TableTab({
    super.key,
    required this.shots,
    this.selectedIndex,
    this.onRowTap,
    this.club,
  });

  @override
  ConsumerState<TableTab> createState() => _TableTabState();
}

class _TableTabState extends ConsumerState<TableTab> {
  bool _showStats = true;

  // Local mirror of widget.shots used to drive the AnimatedList. We diff
  // against widget.shots in didUpdateWidget and replay the changes via
  // insertItem / removeItem so new shots slide in and deletions slide out.
  final _listKey = GlobalKey<AnimatedListState>();
  late List<ShotData> _shots;

  // Identity for diffing — dbId when persisted, the object itself otherwise
  // (seed shots and not-yet-persisted shots fall back to instance equality).
  Object _shotId(ShotData s) => s.dbId ?? s;

  @override
  void initState() {
    super.initState();
    _shots = List<ShotData>.from(widget.shots);
  }

  @override
  void didUpdateWidget(TableTab old) {
    super.didUpdateWidget(old);
    _syncShots();
  }

  void _syncShots() {
    final newIds = widget.shots.map(_shotId).toSet();
    final oldIds = _shots.map(_shotId).toSet();

    // 1. Removals — descending so indices stay valid as we splice.
    for (var i = _shots.length - 1; i >= 0; i--) {
      if (!newIds.contains(_shotId(_shots[i]))) {
        final removed = _shots.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
          (ctx, anim) => _RowReveal(
            entry: anim,
            // No flash on removal — just the reverse slide/fade.
            flashOnComplete: false,
            child: _DynamicShotRow(
              number: 0,
              shot: removed,
              columns: ref.read(selectedTableColumnsProvider),
              prefs: ref.read(unitPrefsProvider),
            ),
          ),
          duration: const Duration(milliseconds: 240),
        );
      }
    }

    // 2. Insertions / in-place updates.
    for (var i = 0; i < widget.shots.length; i++) {
      final shot = widget.shots[i];
      final id = _shotId(shot);
      if (!oldIds.contains(id)) {
        _shots.insert(i, shot);
        _listKey.currentState?.insertItem(
          i,
          duration: const Duration(milliseconds: 320),
        );
      } else {
        // Same identity, value changed (e.g. club metrics arrived after the
        // ball-only shot was inserted). Update in place — no animation.
        final idx = _shots.indexWhere((s) => _shotId(s) == id);
        if (idx != -1) _shots[idx] = shot;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = ref.watch(selectedTableColumnsProvider);
    final prefs = ref.watch(unitPrefsProvider);

    if (widget.shots.isEmpty) {
      return Center(
        child: Text('No shots yet',
            style: AppTextStyles.sans(color: AppColors.textMuted)),
      );
    }

    final shots = widget.shots;
    final avg = ShotData.averageOf(shots);

    double sd(TableColumn col) {
      if (shots.length <= 1) return 0;
      final vals = shots.map((s) => _colRaw(col, s, prefs)).toList();
      final mean = vals.reduce((a, b) => a + b) / vals.length;
      final v = vals
              .map((x) => (x - mean) * (x - mean))
              .reduce((a, b) => a + b) /
          (shots.length - 1);
      return math.sqrt(v);
    }

    return Stack(
      children: [
        Column(
          children: [
            if (widget.club != null)
              _ClubHeaderBar(
                club: widget.club!,
                shotCount: shots.length,
                showStats: _showStats,
                onToggle: () => setState(() => _showStats = !_showStats),
              ),
            _DynamicTableHeader(columns: columns, prefs: prefs),
            if (_showStats) ...[
              _DynamicStatsRow(
                label: 'AVG',
                columns: columns,
                getValue: (col) => tableColumnValue(col, avg, prefs),
                isAvg: true,
              ),
              _DynamicStatsRow(
                label: '+/-',
                columns: columns,
                getValue: (col) {
                  final val = sd(col).toStringAsFixed(1);
                  final unit = tableColUnit(col, prefs);
                  if (col == TableColumn.offline) {
                    final signed = _offlineYds(avg);
                    final dir = signed > 0.05
                        ? 'R'
                        : signed < -0.05
                            ? 'L'
                            : '';
                    return dir.isNotEmpty
                        ? '$val $dir ${prefs.distLabel}'
                        : '$val ${prefs.distLabel}';
                  }
                  if (unit == 'deg') return '$val°';
                  if (unit.isNotEmpty) return '$val $unit';
                  return val;
                },
                isAvg: false,
              ),
            ],
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: AnimatedList(
                key: _listKey,
                initialItemCount: _shots.length,
                itemBuilder: (_, i, animation) {
                  if (i >= _shots.length) return const SizedBox.shrink();
                  return _RowReveal(
                    entry: animation,
                    child: _DynamicShotRow(
                      number: _shots.length - i,
                      shot: _shots[i],
                      columns: columns,
                      prefs: prefs,
                      isSelected: widget.selectedIndex == i,
                      onTap: widget.onRowTap != null
                          ? () => widget.onRowTap!(i)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        // Customize button (floating, bottom-right)
        Positioned(
          right: 16,
          bottom: 16,
          child: GestureDetector(
            onTap: () => _showCustomizeSheet(context, ref, columns),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    'Customize',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCustomizeSheet(
    BuildContext context,
    WidgetRef ref,
    List<TableColumn> current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TableCustomizeSheet(
        current: current,
        onApply: (updated) =>
            ref.read(selectedTableColumnsProvider.notifier).state = updated,
      ),
    );
  }
}

// ── Club header ───────────────────────────────────────────────────────────────

class _ClubHeaderBar extends StatelessWidget {
  final Club club;
  final int shotCount;
  final bool showStats;
  final VoidCallback onToggle;

  const _ClubHeaderBar({
    required this.club,
    required this.shotCount,
    required this.showStats,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: club.color, width: 3),
          bottom: const BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
      child: Row(
        children: [
          Text(
            club.shortName,
            style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onToggle,
            child: Row(
              children: [
                Text(
                  '$shotCount Shots',
                  style: AppTextStyles.sans(
                      size: 12, color: AppColors.textMuted),
                ),
                const SizedBox(width: 4),
                Icon(
                  showStats
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dynamic column header ─────────────────────────────────────────────────────

class _DynamicTableHeader extends StatelessWidget {
  final List<TableColumn> columns;
  final UnitPrefs prefs;

  const _DynamicTableHeader({required this.columns, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: _shotColW,
            child: Text(
              'Shot',
              style: AppTextStyles.sans(
                size: 8,
                weight: FontWeight.w400,
                color: AppColors.textDimmed,
              ),
            ),
          ),
          ...columns.map(
            (col) => Expanded(
              flex: _fCol,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    col.label,
                    style: AppTextStyles.sans(
                      size: 8,
                      weight: FontWeight.w400,
                      color: AppColors.textDimmed,
                    ),
                  ),
                  if (tableColUnit(col, prefs).isNotEmpty)
                    Text(
                      tableColUnit(col, prefs),
                      style:
                          AppTextStyles.sans(size: 7, color: AppColors.border2),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dynamic stats row ─────────────────────────────────────────────────────────

class _DynamicStatsRow extends StatelessWidget {
  final String label;
  final List<TableColumn> columns;
  final String Function(TableColumn) getValue;
  final bool isAvg;

  const _DynamicStatsRow({
    required this.label,
    required this.columns,
    required this.getValue,
    required this.isAvg,
  });

  @override
  Widget build(BuildContext context) {
    final color = isAvg ? Colors.white : context.accent;
    final size = isAvg ? 13.0 : 11.0;

    return Container(
      color: isAvg ? AppColors.surface : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: _shotColW,
            child: Text(label,
                style:
                    AppTextStyles.mono(size: 10, color: AppColors.textMuted)),
          ),
          ...columns.map(
            (col) => Expanded(
              flex: _fCol,
              child: Text(
                getValue(col),
                style: AppTextStyles.mono(size: size, color: color),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dynamic shot row ──────────────────────────────────────────────────────────

class _DynamicShotRow extends StatelessWidget {
  final int number;
  final ShotData shot;
  final List<TableColumn> columns;
  final UnitPrefs prefs;
  final bool isSelected;
  final VoidCallback? onTap;

  const _DynamicShotRow({
    required this.number,
    required this.shot,
    required this.columns,
    required this.prefs,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? context.accentGhost : Colors.transparent,
          border: Border(
            left: isSelected
                ? BorderSide(color: context.accent, width: 2)
                : BorderSide.none,
            bottom: const BorderSide(color: AppColors.surface),
          ),
        ),
        padding: EdgeInsets.fromLTRB(isSelected ? 14 : 16, 8, 16, 8),
        child: Row(
          children: [
            SizedBox(
              width: _shotColW,
              child: Text(
                number.toString().padLeft(2, '0'),
                style:
                    AppTextStyles.mono(size: 11, color: AppColors.textDimmed),
              ),
            ),
            ...columns.map(
              (col) => Expanded(
                flex: _fCol,
                child: Text(
                  tableColumnValue(col, shot, prefs),
                  style: AppTextStyles.mono(size: 12, color: Colors.white),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Customize bottom sheet ────────────────────────────────────────────────────

class _TableCustomizeSheet extends StatefulWidget {
  final List<TableColumn> current;
  final ValueChanged<List<TableColumn>> onApply;

  const _TableCustomizeSheet({required this.current, required this.onApply});

  @override
  State<_TableCustomizeSheet> createState() => _TableCustomizeSheetState();
}

class _TableCustomizeSheetState extends State<_TableCustomizeSheet> {
  late final Set<TableColumn> _selected;

  static const _ballData = [
    TableColumn.carry,
    TableColumn.ballSpeed,
    TableColumn.launchAngle,
    TableColumn.launchDirection,
    TableColumn.offline,
    TableColumn.spinRate,
    TableColumn.spinAxis,
    TableColumn.apex,
    TableColumn.run,
    TableColumn.totalDistance,
  ];

  static const _clubData = [
    TableColumn.clubSpeed,
    TableColumn.smashFactor,
    TableColumn.swingPath,
    TableColumn.faceAngle,
    TableColumn.angleOfAttack,
    TableColumn.dynamicLoft,
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.current);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Customize Columns',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _selected.clear()),
                  child: Text(
                    'Clear all',
                    style: AppTextStyles.sans(
                        size: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.border),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _ColSection(
                  title: 'Ball data',
                  columns: _ballData,
                  selected: _selected,
                  onToggle: _toggle,
                ),
                const SizedBox(height: 16),
                _ColSection(
                  title: 'Club data',
                  columns: _clubData,
                  selected: _selected,
                  onToggle: _toggle,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final ordered =
                      TableColumn.values.where(_selected.contains).toList();
                  widget.onApply(ordered);
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(TableColumn col) => setState(() {
        if (_selected.contains(col)) {
          _selected.remove(col);
        } else {
          _selected.add(col);
        }
      });
}

// ── Animated row reveal ───────────────────────────────────────────────────────
//
// Wraps each shot row with a slide-in-from-top + fade-in entry, then triggers
// a brief accent-coloured highlight after the entry settles. Pre-existing
// rows (mounted with [entry] already at 1.0) skip the flash.

class _RowReveal extends StatefulWidget {
  final Animation<double> entry;
  final Widget child;
  final bool flashOnComplete;

  const _RowReveal({
    required this.entry,
    required this.child,
    this.flashOnComplete = true,
  });

  @override
  State<_RowReveal> createState() => _RowRevealState();
}

class _RowRevealState extends State<_RowReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashCtrl;
  bool _flashScheduled = false;

  @override
  void initState() {
    super.initState();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    if (widget.flashOnComplete) {
      // If the entry is already complete (existing rows on first build), skip
      // the flash. Otherwise wait for the entry to finish, then run it once.
      if (widget.entry.value >= 1.0) {
        _flashScheduled = true; // suppress
      } else {
        widget.entry.addStatusListener(_onEntryStatus);
      }
    }
  }

  void _onEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_flashScheduled) {
      _flashScheduled = true;
      _flashCtrl.forward();
    }
  }

  @override
  void dispose() {
    widget.entry.removeStatusListener(_onEntryStatus);
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: widget.entry, curve: Curves.easeOutCubic));

    return SizeTransition(
      sizeFactor: widget.entry,
      axisAlignment: -1.0,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: widget.entry,
          child: AnimatedBuilder(
            animation: _flashCtrl,
            builder: (_, child) {
              final flash = _flashCtrl.value;
              // Hold full intensity briefly, then fade — ease-out to 0.
              final intensity =
                  flash == 0 ? 0.0 : (1.0 - flash).clamp(0.0, 1.0);
              return Stack(
                children: [
                  child!,
                  if (intensity > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: context.accent.withAlpha(
                            (intensity * 64).round(),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _ColSection extends StatelessWidget {
  final String title;
  final List<TableColumn> columns;
  final Set<TableColumn> selected;
  final ValueChanged<TableColumn> onToggle;

  const _ColSection({
    required this.title,
    required this.columns,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.sans(
            size: 10,
            weight: FontWeight.w600,
            color: AppColors.textDimmed,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: columns.map((col) {
            final active = selected.contains(col);
            return GestureDetector(
              onTap: () => onToggle(col),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? context.accentFaint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? context.accent : AppColors.border2,
                  ),
                ),
                child: Text(
                  col.label,
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w400,
                    color: active ? context.accent : AppColors.textMuted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
