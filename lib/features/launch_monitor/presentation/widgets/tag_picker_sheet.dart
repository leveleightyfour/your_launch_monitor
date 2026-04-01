import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/tag.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Opens the tag picker bottom sheet.
///
/// [currentTagIds] — the tag IDs already applied to the shot(s).
/// [onDone] — called with the final set of selected tag IDs.
Future<void> showTagPickerSheet(
  BuildContext context, {
  required List<int> currentTagIds,
  required ValueChanged<List<int>> onDone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => TagPickerSheet(
      currentTagIds: currentTagIds,
      onDone: onDone,
    ),
  );
}

class TagPickerSheet extends ConsumerStatefulWidget {
  final List<int> currentTagIds;
  final ValueChanged<List<int>> onDone;

  const TagPickerSheet({
    super.key,
    required this.currentTagIds,
    required this.onDone,
  });

  @override
  ConsumerState<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<TagPickerSheet> {
  late Set<int> _selected;
  bool _showNewForm = false;
  final _nameController = TextEditingController();
  Color _newColor = Tag.palette.first;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.currentTagIds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(tagsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ───────────────────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Tags',
                    style: AppTextStyles.sans(
                        size: 16, weight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    widget.onDone(_selected.toList());
                    Navigator.of(context).pop();
                  },
                  child: Text('Done',
                      style: AppTextStyles.sans(
                          size: 14, color: AppColors.accent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          // ── Existing tags ─────────────────────────────────────────────────
          tagsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading tags',
                  style: AppTextStyles.sans(color: AppColors.textMuted)),
            ),
            data: (tags) => tags.isEmpty && !_showNewForm
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('No tags yet — create one below',
                        style: AppTextStyles.sans(
                            size: 13, color: AppColors.textMuted)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tags.length,
                    itemBuilder: (_, i) {
                      final tag = tags[i];
                      final active = _selected.contains(tag.id);
                      return _TagRow(
                        tag: tag,
                        active: active,
                        onTap: () {
                          if (active) {
                            _selected.remove(tag.id);
                          } else {
                            _selected.add(tag.id);
                          }
                          widget.onDone(_selected.toList());
                          Navigator.of(context).pop();
                        },
                        onDelete: () async {
                          await ref
                              .read(tagsProvider.notifier)
                              .removeTag(tag.id);
                          setState(() => _selected.remove(tag.id));
                        },
                      );
                    },
                  ),
          ),
          // ── New tag form ──────────────────────────────────────────────────
          if (_showNewForm) ...[
            const Divider(height: 1, color: AppColors.border),
            _NewTagForm(
              nameController: _nameController,
              selectedColor: _newColor,
              onColorChanged: (c) => setState(() => _newColor = c),
              onSubmit: () async {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;
                final tag = await ref
                    .read(tagsProvider.notifier)
                    .addTag(name, _newColor);
                setState(() {
                  _selected.add(tag.id);
                  _showNewForm = false;
                  _nameController.clear();
                  _newColor = Tag.palette.first;
                });
              },
              onCancel: () => setState(() {
                _showNewForm = false;
                _nameController.clear();
              }),
            ),
          ],
          // ── Add new tag button ────────────────────────────────────────────
          if (!_showNewForm)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: GestureDetector(
                onTap: () => setState(() => _showNewForm = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 16, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text('New tag',
                          style: AppTextStyles.sans(
                              size: 13, color: AppColors.accent)),
                    ],
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Existing tag row ───────────────────────────────────────────────────────────

class _TagRow extends StatelessWidget {
  final Tag tag;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TagRow({
    required this.tag,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: tag.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tag.name,
                  style: AppTextStyles.sans(size: 14)),
            ),
            if (active)
              const Icon(Icons.check, size: 18, color: AppColors.accent)
            else
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(Icons.close,
                      size: 16, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── New tag creation form ─────────────────────────────────────────────────────

class _NewTagForm extends StatelessWidget {
  final TextEditingController nameController;
  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _NewTagForm({
    required this.nameController,
    required this.selectedColor,
    required this.onColorChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            autofocus: true,
            style: AppTextStyles.sans(size: 14),
            decoration: InputDecoration(
              hintText: 'Tag name',
              hintStyle:
                  AppTextStyles.sans(size: 14, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          // Colour palette
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Tag.palette.map((color) {
              final isSelected = color.toARGB32() == selectedColor.toARGB32();
              return GestureDetector(
                onTap: () => onColorChanged(color),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          size: 14, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: Text('Cancel',
                    style: AppTextStyles.sans(
                        size: 13, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text('Add',
                    style: AppTextStyles.sans(
                        size: 13, weight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
