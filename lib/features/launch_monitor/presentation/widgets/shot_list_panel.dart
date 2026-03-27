import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/tag.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tag_picker_sheet.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── Shot list metric ──────────────────────────────────────────────────────────

enum ShotListMetric {
  carry('Carry', 'yds'),
  ballSpeed('Ball Spd', 'mph'),
  clubSpeed('Club Spd', 'mph'),
  spinRate('Spin', 'rpm'),
  launchAngle('Launch Ang.', 'deg'),
  offline('Offline', 'yds');

  const ShotListMetric(this.label, this.unit);

  final String label;
  final String unit;

  String format(ShotData s) {
    switch (this) {
      case carry:
        return '${s.carry.toStringAsFixed(1)} yds';
      case ballSpeed:
        return '${s.ballSpeed.toStringAsFixed(1)} mph';
      case clubSpeed:
        return '${s.clubSpeed.toStringAsFixed(1)} mph';
      case spinRate:
        return '${s.spinRate.toStringAsFixed(0)} rpm';
      case launchAngle:
        return '${s.launchAngle.toStringAsFixed(1)}°';
      case offline:
        final yds = s.carry * (s.launchDirection * 3.14159 / 180.0);
        final abs = yds.abs();
        final dir = yds < 0 ? 'L' : 'R';
        return abs < 0.05 ? '0.0 yds' : '${abs.toStringAsFixed(1)} $dir yds';
    }
  }

  String avg(List<ShotData> shots) {
    if (shots.isEmpty) return '--';
    return format(ShotData.averageOf(shots));
  }
}

// ── Shot list panel ───────────────────────────────────────────────────────────

class ShotListPanel extends StatefulWidget {
  final List<ShotData> allShots;
  final List<Club> clubs;
  final int selectedShotIndex;
  final Future<void> Function(int shotIndex, List<int> tagIds)? onUpdateShotTags;
  final ShotListMetric metric;
  final ValueChanged<ShotListMetric> onMetricChanged;
  final ValueChanged<int> onShotSelected;

  /// When provided, shows an "Edit Shots" button at the bottom (active session).
  /// Pass null for past sessions where shots cannot be cleared.
  final VoidCallback? onClearShots;

  const ShotListPanel({
    super.key,
    required this.allShots,
    required this.clubs,
    required this.selectedShotIndex,
    required this.metric,
    required this.onMetricChanged,
    required this.onShotSelected,
    this.onClearShots,
    this.onUpdateShotTags,
  });

  @override
  State<ShotListPanel> createState() => _ShotListPanelState();
}

class _ShotListPanelState extends State<ShotListPanel> {
  final Set<String?> _collapsed = {};
  bool _editMode = false;
  final Set<int> _selectedIndices = {};

  void _exitEditMode() => setState(() {
        _editMode = false;
        _selectedIndices.clear();
      });

  Future<void> _applyBulkTags(BuildContext context) async {
    if (_selectedIndices.isEmpty || widget.onUpdateShotTags == null) return;
    final union = _selectedIndices
        .expand((i) => widget.allShots[i].tagIds)
        .toSet()
        .toList();
    showTagPickerSheet(
      context,
      currentTagIds: union,
      onDone: (selected) async {
        for (final i in _selectedIndices) {
          await widget.onUpdateShotTags!(i, selected);
        }
        if (mounted) _exitEditMode();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String?, List<({ShotData shot, int index})>> grouped = {};
    for (var i = 0; i < widget.allShots.length; i++) {
      final s = widget.allShots[i];
      grouped.putIfAbsent(s.clubId, () => []).add((shot: s, index: i));
    }

    Club? clubFor(String? id) {
      if (id == null) return null;
      return widget.clubs.where((c) => c.id == id).firstOrNull;
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: _editMode
                ? Row(
                    children: [
                      Text(
                        '${_selectedIndices.length} selected',
                        style: AppTextStyles.sans(
                            size: 15, weight: FontWeight.w600),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _exitEditMode,
                        child: Text(
                          'Cancel',
                          style: AppTextStyles.sans(
                              size: 13, color: AppColors.accent),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        'Shot List',
                        style: AppTextStyles.sans(
                            size: 15, weight: FontWeight.w600),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showMetricPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.metric.label,
                                style: AppTextStyles.sans(
                                    size: 11, color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down,
                                  size: 14, color: AppColors.textMuted),
                            ],
                          ),
                        ),
                      ),
                      if (widget.onUpdateShotTags != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _editMode = true),
                          child: const Icon(Icons.checklist,
                              size: 18, color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
          ),
          // Club sections
          Expanded(
            child: ListView(
              children: [
                for (final entry in grouped.entries)
                  ShotListClubSection(
                    club: clubFor(entry.key),
                    entries: entry.value,
                    metric: widget.metric,
                    selectedShotIndex: widget.selectedShotIndex,
                    collapsed: _collapsed.contains(entry.key),
                    onToggleCollapse: () => setState(() {
                      if (_collapsed.contains(entry.key)) {
                        _collapsed.remove(entry.key);
                      } else {
                        _collapsed.add(entry.key);
                      }
                    }),
                    onShotSelected: widget.onShotSelected,
                    onUpdateShotTags:
                        _editMode ? null : widget.onUpdateShotTags,
                    editMode: _editMode,
                    selectedIndices: _selectedIndices,
                    onToggleIndex: (i) => setState(() {
                      if (_selectedIndices.contains(i)) {
                        _selectedIndices.remove(i);
                      } else {
                        _selectedIndices.add(i);
                      }
                    }),
                    onSelectGroup: () => setState(() {
                      final indices =
                          entry.value.map((e) => e.index).toSet();
                      if (indices.every(_selectedIndices.contains)) {
                        _selectedIndices.removeAll(indices);
                      } else {
                        _selectedIndices.addAll(indices);
                      }
                    }),
                  ),
              ],
            ),
          ),
          // Footer
          if (_editMode)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: _selectedIndices.isEmpty
                    ? null
                    : () => _applyBulkTags(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedIndices.isEmpty
                        ? AppColors.card
                        : AppColors.accentSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedIndices.isEmpty
                          ? AppColors.border2
                          : AppColors.accent,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Tag Selected',
                      style: AppTextStyles.sans(
                        size: 13,
                        color: _selectedIndices.isEmpty
                            ? AppColors.textMuted
                            : AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (widget.onClearShots != null)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: widget.onClearShots,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Center(
                    child: Text(
                      'Edit Shots',
                      style: AppTextStyles.sans(
                          size: 13, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMetricPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Display metric',
              style: AppTextStyles.sans(size: 15, weight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (final m in ShotListMetric.values)
            ListTile(
              title: Text(
                '${m.label} (${m.unit})',
                style: AppTextStyles.sans(size: 14),
              ),
              trailing: m == widget.metric
                  ? const Icon(Icons.check,
                      color: AppColors.accent, size: 18)
                  : null,
              onTap: () {
                widget.onMetricChanged(m);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Shot list club section ────────────────────────────────────────────────────

class ShotListClubSection extends ConsumerWidget {
  final Club? club;
  final List<({ShotData shot, int index})> entries;
  final ShotListMetric metric;
  final int selectedShotIndex;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<int> onShotSelected;
  final Future<void> Function(int shotIndex, List<int> tagIds)? onUpdateShotTags;
  final bool editMode;
  final Set<int> selectedIndices;
  final ValueChanged<int> onToggleIndex;
  final VoidCallback onSelectGroup;

  const ShotListClubSection({
    super.key,
    required this.club,
    required this.entries,
    required this.metric,
    required this.selectedShotIndex,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onShotSelected,
    this.onUpdateShotTags,
    this.editMode = false,
    this.selectedIndices = const {},
    required this.onToggleIndex,
    required this.onSelectGroup,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shots = entries.map((e) => e.shot).toList();
    final avgStr = metric.avg(shots);
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];

    final groupTagIds =
        shots.expand((s) => s.tagIds).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Club header
        Container(
          decoration: BoxDecoration(
            border: club != null
                ? Border(left: BorderSide(color: club!.color, width: 3))
                : null,
            color: AppColors.surface,
          ),
          padding: const EdgeInsets.fromLTRB(13, 10, 12, 10),
          child: Row(
            children: [
              Text(
                club?.shortName ?? 'Unknown',
                style: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              ...groupTagIds.map((id) {
                final tag = tags.where((t) => t.id == id).firstOrNull;
                if (tag == null) return const SizedBox.shrink();
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: tag.color,
                    shape: BoxShape.circle,
                  ),
                );
              }),
              if (editMode)
                GestureDetector(
                  onTap: onSelectGroup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      entries.map((e) => e.index).every(selectedIndices.contains)
                          ? 'Deselect all'
                          : 'Select all',
                      style: AppTextStyles.sans(
                          size: 10, color: AppColors.textMuted),
                    ),
                  ),
                )
              else if (onUpdateShotTags != null)
                GestureDetector(
                  onTap: () => showTagPickerSheet(
                    context,
                    currentTagIds: groupTagIds,
                    onDone: (selected) async {
                      for (final e in entries) {
                        await onUpdateShotTags!(e.index, selected);
                      }
                    },
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      groupTagIds.isEmpty ? '+ Add tag' : 'Edit tags',
                      style: AppTextStyles.sans(
                          size: 10, color: AppColors.textMuted),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: onToggleCollapse,
                child: Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (!collapsed) ...[
          // AVG row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Text('AVG',
                    style: AppTextStyles.mono(
                        size: 11, color: AppColors.textMuted)),
                const Spacer(),
                Text(avgStr,
                    style: AppTextStyles.mono(size: 12, color: Colors.white)),
              ],
            ),
          ),
          // Shot rows
          ...List.generate(entries.length, (i) {
            final e = entries[i];
            final shotNum = entries.length - i;
            final isSelected = e.index == selectedShotIndex;
            final isChecked = selectedIndices.contains(e.index);
            final selColor = club?.color ?? AppColors.accent;
            final shotTags = e.shot.tagIds
                .map((id) => tags.where((t) => t.id == id).firstOrNull)
                .whereType<Tag>()
                .toList();

            if (editMode) {
              return GestureDetector(
                onTap: () => onToggleIndex(e.index),
                child: Container(
                  decoration: BoxDecoration(
                    color: isChecked
                        ? selColor.withAlpha(15)
                        : Colors.transparent,
                    border: Border(
                      left: isChecked
                          ? BorderSide(color: selColor, width: 2)
                          : BorderSide.none,
                      bottom: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  padding:
                      EdgeInsets.fromLTRB(isChecked ? 14 : 16, 9, 12, 9),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isChecked ? selColor : Colors.transparent,
                          border: Border.all(
                            color: isChecked ? selColor : AppColors.border2,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: isChecked
                            ? const Icon(Icons.check,
                                size: 11, color: Colors.black)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        shotNum.toString().padLeft(2, '0'),
                        style: AppTextStyles.mono(
                          size: 12,
                          color: isChecked
                              ? Colors.white
                              : AppColors.textDimmed,
                        ),
                      ),
                      ...shotTags.map((tag) => Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: tag.color,
                              shape: BoxShape.circle,
                            ),
                          )),
                      const Spacer(),
                      Text(
                        metric.format(e.shot),
                        style: AppTextStyles.mono(
                            size: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              );
            }

            return GestureDetector(
              onTap: () => onShotSelected(e.index),
              onLongPress: onUpdateShotTags != null
                  ? () => showTagPickerSheet(
                        context,
                        currentTagIds: e.shot.tagIds,
                        onDone: (selected) =>
                            onUpdateShotTags!(e.index, selected),
                      )
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? selColor.withAlpha(15)
                      : Colors.transparent,
                  border: Border(
                    left: isSelected
                        ? BorderSide(color: selColor, width: 2)
                        : BorderSide.none,
                    bottom:
                        const BorderSide(color: AppColors.border),
                  ),
                ),
                padding:
                    EdgeInsets.fromLTRB(isSelected ? 14 : 16, 9, 12, 9),
                child: Row(
                  children: [
                    Text(
                      shotNum.toString().padLeft(2, '0'),
                      style: AppTextStyles.mono(
                        size: 12,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textDimmed,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isSelected)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: selColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ...shotTags.map((tag) => Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: tag.color,
                            shape: BoxShape.circle,
                          ),
                        )),
                    const Spacer(),
                    Text(
                      metric.format(e.shot),
                      style:
                          AppTextStyles.mono(size: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
