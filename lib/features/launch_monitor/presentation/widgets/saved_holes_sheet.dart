/// The hole library: save the hole being built, load a saved one, share a
/// hole with another player, or import one they shared.
///
/// Holes travel as [SavedHole]'s portable text document, so sharing works
/// through any messenger and importing is a paste.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omni_sniffer/features/launch_monitor/application/saved_holes_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/saved_hole.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/snackbars.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// Opens the library. Returns the hole the player chose to load, or null.
Future<HoleSetup?> showSavedHolesSheet(
  BuildContext context, {
  required HoleSetup current,
}) {
  return showModalBottomSheet<HoleSetup>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SavedHolesSheet(current: current),
  );
}

class SavedHolesSheet extends ConsumerWidget {
  /// The hole as it stands in the builder — what "Save this hole" keeps.
  final HoleSetup current;

  const SavedHolesSheet({super.key, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holes = ref.watch(savedHolesProvider);
    final prefs = ref.watch(unitPrefsProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Saved holes',
                  style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ListTile(
            leading: Icon(Icons.add, size: 18, color: context.accent),
            title: Text(
              'Save this hole',
              style: AppTextStyles.sans(size: 14, color: context.accent),
            ),
            onTap: () => _saveCurrent(context, ref),
          ),
          ListTile(
            leading: const Icon(
              Icons.ios_share,
              size: 18,
              color: AppColors.textMuted,
            ),
            title: Text(
              'Import from text',
              style: AppTextStyles.sans(size: 14),
            ),
            subtitle: Text(
              'Paste a hole another player shared',
              style: AppTextStyles.sans(size: 11, color: AppColors.textMuted),
            ),
            onTap: () => _importFromText(context, ref),
          ),
          if (holes.isNotEmpty)
            const Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: holes.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final saved = holes[i];
                final grid = saved.hole.grid;
                final length = grid?.length ?? saved.hole.greenDistance;
                return ListTile(
                  title: Text(saved.name, style: AppTextStyles.sans(size: 14)),
                  subtitle: Text(
                    '${prefs.dist(length).round()} ${prefs.distLabel}',
                    style: AppTextStyles.sans(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: 'Share',
                        child: Semantics(
                          button: true,
                          label: 'Share ${saved.name}',
                          child: GestureDetector(
                            onTap: () => _share(context, saved),
                            behavior: HitTestBehavior.opaque,
                            child: const SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.ios_share,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Delete',
                        child: Semantics(
                          button: true,
                          label: 'Delete ${saved.name}',
                          child: GestureDetector(
                            onTap: () => _delete(context, ref, saved),
                            behavior: HitTestBehavior.opaque,
                            child: const SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.pop(context, saved.hole),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _saveCurrent(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(savedHolesProvider.notifier);
    final existing = ref.read(savedHolesProvider).map((h) => h.name);
    final ctrl = TextEditingController(
      text: SavedHole.uniqueName('Hole', existing),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Save hole',
          style: AppTextStyles.sans(size: 17, weight: FontWeight.w600),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: AppTextStyles.sans(size: 15),
          decoration: InputDecoration(
            hintText: 'Hole name',
            hintStyle: AppTextStyles.sans(size: 15, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTextStyles.sans(color: AppColors.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(
              'Save',
              style: AppTextStyles.sans(
                weight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !context.mounted) return;
    notifier.save(
      SavedHole(name: trimmed, savedAt: DateTime.now(), hole: current),
    );
    showTransientSnackBar(context, message: '"$trimmed" saved');
  }

  Future<void> _importFromText(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(savedHolesProvider.notifier);
    final ctrl = TextEditingController();
    String? error;
    final imported = await showDialog<SavedHole>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Import hole',
            style: AppTextStyles.sans(size: 17, weight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 5,
                style: AppTextStyles.mono(size: 11),
                decoration: InputDecoration(
                  hintText: 'Paste the shared hole text here',
                  hintStyle: AppTextStyles.sans(
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: AppTextStyles.sans(
                    size: 12,
                    color: AppColors.errorText,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTextStyles.sans(color: AppColors.textMuted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ctx.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                final hole = SavedHole.tryDecode(ctrl.text);
                if (hole == null) {
                  setDialogState(
                    () => error = "That text isn't a shared hole.",
                  );
                  return;
                }
                Navigator.pop(ctx, hole);
              },
              child: Text(
                'Import',
                style: AppTextStyles.sans(
                  weight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (imported == null || !context.mounted) return;
    final existing = ref.read(savedHolesProvider).map((h) => h.name);
    final named = SavedHole(
      name: SavedHole.uniqueName(imported.name, existing),
      savedAt: DateTime.now(),
      hole: imported.hole,
    );
    notifier.save(named);
    showTransientSnackBar(context, message: '"${named.name}" imported');
  }

  Future<void> _share(BuildContext context, SavedHole saved) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: saved.encodeShareText(),
        subject: '${saved.name} (Your Launch Monitor hole)',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref, SavedHole saved) {
    final notifier = ref.read(savedHolesProvider.notifier);
    notifier.delete(saved.name);
    showTransientSnackBar(
      context,
      message: '"${saved.name}" deleted',
      action: SnackBarAction(
        label: 'Undo',
        textColor: context.accent,
        onPressed: () => notifier.save(saved),
      ),
    );
  }
}
