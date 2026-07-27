import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_sniffer/features/launch_monitor/application/bag_stats_providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/sessions_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club_gapping.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/snackbars.dart';
import 'package:omni_sniffer/shared/theme.dart';

class MyBagScreen extends ConsumerStatefulWidget {
  const MyBagScreen({super.key});

  @override
  ConsumerState<MyBagScreen> createState() => _MyBagScreenState();
}

class _MyBagScreenState extends ConsumerState<MyBagScreen> {
  int _tab = 0;

  static const _tabs = [
    (Icons.sports_golf, 'Clubs'),
    (Icons.straighten, 'Distances'),
    (Icons.scatter_plot, 'Dispersion'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    'My Bag',
                    style: AppTextStyles.sans(
                      size: 20,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Tab bar
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
                color: AppColors.background,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int i = 0; i < _tabs.length; i++)
                    _BagNavItem(
                      icon: _tabs[i].$1,
                      label: _tabs[i].$2,
                      active: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                1 => const _DistancesTab(),
                2 => const _DispersionTabWrapper(),
                _ => const _ClubsTab(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BagNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BagNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? context.accent : AppColors.textMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: AppTextStyles.sans(
                        size: 10,
                        weight: active ? FontWeight.w600 : FontWeight.w400,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (active)
              Positioned(
                bottom: 0,
                left: 8,
                right: 8,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: context.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Clubs tab ─────────────────────────────────────────────────────────────────

class _ClubsTab extends ConsumerWidget {
  const _ClubsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final selected = ref.watch(selectedClubProvider);

    // Group clubs by type, preserving bag order within each group.
    final groups = <ClubType, List<Club>>{};
    for (final c in clubs) {
      groups.putIfAbsent(c.type, () => []).add(c);
    }

    // Section order matches catalog top-to-bottom.
    const sectionOrder = [
      ClubType.wood,
      ClubType.miniDriver,
      ClubType.hybrid,
      ClubType.iron,
      ClubType.wedge,
      ClubType.putter,
    ];

    final sections = sectionOrder.where((t) => groups.containsKey(t)).toList();

    // Build a flat list: header rows + club rows
    final items = <Object>[];
    for (final type in sections) {
      items.add(type); // section header
      items.addAll(groups[type]!);
    }

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                '${clubs.length} clubs',
                style: AppTextStyles.sans(
                  size: 13,
                  weight: FontWeight.w400,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              _OutlineButton(
                label: 'Add clubs',
                onTap: () => _openAddClubs(context, ref),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is ClubType) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    Club.groupLabel(item),
                    style: AppTextStyles.sans(
                      size: 9,
                      weight: FontWeight.w600,
                      color: AppColors.textDimmed,
                    ),
                  ),
                );
              }
              final club = item as Club;
              final isSelected = club.id == selected?.id;
              return Column(
                children: [
                  Dismissible(
                    key: ValueKey(club.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _removeFromBag(context, ref, club),
                    background: Container(
                      color: AppColors.errorBackground,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppColors.errorText,
                      ),
                    ),
                    child: _ClubTile(
                      club: club,
                      isSelected: isSelected,
                      onTap: () =>
                          ref.read(selectedClubProvider.notifier).state = club,
                      onEdit: () => _showEditSheet(context, ref, club),
                      onRemove: () => _removeFromBag(context, ref, club),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border, indent: 16),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _openAddClubs(BuildContext context, WidgetRef ref) {
    // A lingering remove-undo snackbar would follow onto the next screen —
    // the messenger is root-level, not per-route.
    ScaffoldMessenger.of(context).clearSnackBars();
    context.push('/bag/add-clubs');
  }

  /// Takes a club out of the bag, with undo. Shots already tagged with it
  /// keep their data; the club can also come back via "Add clubs".
  void _removeFromBag(BuildContext context, WidgetRef ref, Club club) {
    final clubs = ref.read(clubsProvider);
    final index = clubs.indexWhere((c) => c.id == club.id);
    if (index < 0) return;
    final wasActive = ref.read(activeClubProvider)?.id == club.id;
    final wasFilter = ref.read(selectedClubProvider)?.id == club.id;

    // Captured up front so the undo action outlives this widget.
    final clubsNotifier = ref.read(clubsProvider.notifier);
    final activeNotifier = ref.read(activeClubProvider.notifier);
    final filterNotifier = ref.read(selectedClubProvider.notifier);

    clubsNotifier.removeClub(club.id);

    // Never leave the device tracking a club that left the bag: hand the
    // active slot to the first club still in it. The active-club listener
    // pushes the change to the device (re-arming if detection is on).
    if (wasActive) {
      final remaining = ref.read(clubsProvider);
      activeNotifier.state = remaining.isEmpty ? null : remaining.first;
    }
    if (wasFilter) filterNotifier.state = null;

    showTransientSnackBar(
      context,
      message: '${club.shortName} removed from bag',
      action: SnackBarAction(
        label: 'Undo',
        textColor: context.accent,
        onPressed: () {
          clubsNotifier.insertClub(club, index);
          if (wasActive) activeNotifier.state = club;
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Club club) {
    final mfrCtrl = TextEditingController(text: club.manufacturer ?? '');
    final modelCtrl = TextEditingController(text: club.model ?? '');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: club.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    club.shortName,
                    style: AppTextStyles.sans(
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EditField(
                    label: 'Manufacturer',
                    controller: mfrCtrl,
                    hint: 'e.g. Callaway',
                  ),
                  const SizedBox(height: 12),
                  _EditField(
                    label: 'Model',
                    controller: modelCtrl,
                    hint: 'e.g. Stealth Plus',
                  ),
                  const SizedBox(height: 12),
                  // The protocol models a fixed club set, so off-list clubs
                  // are tracked as their nearest equivalent. Shots still
                  // carry this club's own identity.
                  Text(
                    'The launch monitor tracks this club as '
                    '${deviceClubLabel(club)}.',
                    style: AppTextStyles.sans(
                      size: 11,
                      color: AppColors.textDimmed,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        ref
                            .read(clubsProvider.notifier)
                            .updateClubTags(
                              club.id,
                              manufacturer: mfrCtrl.text.trim().isEmpty
                                  ? null
                                  : mfrCtrl.text.trim(),
                              model: modelCtrl.text.trim().isEmpty
                                  ? null
                                  : modelCtrl.text.trim(),
                            );
                        Navigator.pop(ctx);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClubTile extends StatelessWidget {
  final Club club;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  /// Swipe-to-remove covers touch; this visible affordance covers the
  /// Windows/mouse scene where a swipe is not a natural gesture.
  final VoidCallback onRemove;

  const _ClubTile({
    required this.club,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Colors.transparent,
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: club.color, shape: BoxShape.circle),
      ),
      title: Text(
        club.shortName,
        style: AppTextStyles.sans(
          size: 14,
          weight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? context.accent : Colors.white,
        ),
      ),
      subtitle: (club.manufacturer != null || club.model != null)
          ? Text(
              [
                if (club.manufacturer != null) club.manufacturer!,
                if (club.model != null) club.model!,
              ].join(' · '),
              style: AppTextStyles.sans(size: 11, color: AppColors.textMuted),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected) Icon(Icons.check, color: context.accent, size: 16),
          Tooltip(
            message: 'Edit club',
            child: Semantics(
              button: true,
              label: 'Edit ${club.shortName}',
              child: GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.edit, size: 16, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Remove from bag',
            child: Semantics(
              button: true,
              label: 'Remove ${club.shortName} from bag',
              child: GestureDetector(
                onTap: onRemove,
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
      onTap: onTap,
    );
  }
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;

  const _EditField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.sans(
            size: 9,
            color: AppColors.textDimmed,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: AppTextStyles.sans(size: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.sans(
              size: 14,
              color: AppColors.textDimmed,
            ),
            filled: true,
            fillColor: AppColors.card,
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
              borderSide: BorderSide(color: context.accent),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Distances tab ─────────────────────────────────────────────────────────────

class _DistancesTab extends ConsumerWidget {
  const _DistancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final shots = ref.watch(bagShotsProvider);
    final includeOutliers = ref.watch(bagIncludeOutliersProvider);
    final prefs = ref.watch(unitPrefsProvider);

    // Robust per-club stats, in bag order.
    final stats = <ClubCarryStats>[];
    for (final club in clubs) {
      final carries = <double>[
        for (final s in shots)
          if (s.clubId == club.id) prefs.dist(s.carry),
      ];
      if (carries.isEmpty) continue;
      final st = ClubCarryStats.fromCarries(
        club,
        carries,
        includeOutliers: includeOutliers,
      );
      if (st.hasData) stats.add(st);
    }

    if (stats.isEmpty) {
      return Column(
        children: [
          const _BagScopeBar(showOutlierToggle: false),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.straighten,
                    size: 40,
                    color: AppColors.textDimmed,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No distance data in this range',
                    style: AppTextStyles.sans(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hit shots in a session, or widen the scope above',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textDimmed,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final excludedTotal = stats.fold<int>(
      0,
      (sum, s) => sum + s.excluded.length,
    );

    // Shared scale across all clubs so the bars are comparable.
    var min = stats.first.shortest;
    var max = stats.first.longest;
    for (final s in stats) {
      if (s.shortest < min) min = s.shortest;
      if (s.longest > max) max = s.longest;
    }
    final pad = (max - min) * 0.05 + 1;
    min -= pad;
    max += pad;

    return Column(
      children: [
        const _BagScopeBar(showOutlierToggle: true),
        if (excludedTotal > 0 && !includeOutliers)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  '$excludedTotal ${excludedTotal == 1 ? 'shot' : 'shots'} '
                  'excluded as outliers',
                  style: AppTextStyles.sans(
                    size: 11,
                    color: AppColors.textDimmed,
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: ListView(
            children: [
              // ── Gapping chart ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  'CARRY GAPPING · ${prefs.distLabel.toUpperCase()}',
                  style: AppTextStyles.sans(
                    size: 9,
                    weight: FontWeight.w600,
                    color: AppColors.textDimmed,
                  ),
                ),
              ),
              for (final s in stats)
                _GapRow(stats: s, scaleMin: min, scaleMax: max),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              // ── Stats table ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'CLUB',
                        style: AppTextStyles.sans(
                          size: 9,
                          weight: FontWeight.w400,
                          color: AppColors.textDimmed,
                        ),
                      ),
                    ),
                    const _DistTh('MED'),
                    const _DistTh('AVG'),
                    const _DistTh('HIGH'),
                    const _DistTh('LOW'),
                  ],
                ),
              ),
              for (final s in stats) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: s.club.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              s.club.shortName,
                              style: AppTextStyles.sans(size: 14),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                s.excluded.isEmpty
                                    ? '(${s.kept.length})'
                                    : '(${s.kept.length} · ${s.excluded.length} out)',
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.sans(
                                  size: 10,
                                  color: AppColors.textDimmed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _DistCell(s.median.toStringAsFixed(0), highlight: true),
                      _DistCell(s.average.toStringAsFixed(0)),
                      _DistCell(s.longest.toStringAsFixed(0)),
                      _DistCell(s.shortest.toStringAsFixed(0)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One club's carry range on the shared scale: a colored band from shortest
/// to longest kept carry, with a tick at the median.
class _GapRow extends StatelessWidget {
  final ClubCarryStats stats;
  final double scaleMin;
  final double scaleMax;

  const _GapRow({
    required this.stats,
    required this.scaleMin,
    required this.scaleMax,
  });

  @override
  Widget build(BuildContext context) {
    final span = (scaleMax - scaleMin).clamp(1, double.infinity);
    final startF = (stats.shortest - scaleMin) / span;
    final endF = (stats.longest - scaleMin) / span;
    final medF = (stats.median - scaleMin) / span;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              stats.club.shortName,
              style: AppTextStyles.sans(size: 11, color: Colors.white),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 16,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Positioned(
                        left: w * startF,
                        width: ((endF - startF) * w).clamp(6.0, w),
                        top: 4,
                        height: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: stats.club.color.withAlpha(150),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (w * medF - 1).clamp(0.0, w - 2),
                        width: 2,
                        top: 1,
                        height: 14,
                        child: const ColoredBox(color: Colors.white),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              stats.median.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: AppTextStyles.mono(size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scope chips shared by the Distances and Dispersion tabs, plus the
/// outlier toggle where stats are computed.
class _BagScopeBar extends ConsumerWidget {
  final bool showOutlierToggle;

  const _BagScopeBar({required this.showOutlierToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(bagScopeProvider);
    final include = ref.watch(bagIncludeOutliersProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ScopeChip(
              label: 'Last 5',
              selected: scope.kind == BagScopeKind.lastFive,
              onTap: () => ref.read(bagScopeProvider.notifier).state =
                  const BagScope.lastFive(),
            ),
            const SizedBox(width: 8),
            _ScopeChip(
              label: 'All time',
              selected: scope.kind == BagScopeKind.allTime,
              onTap: () => ref.read(bagScopeProvider.notifier).state =
                  const BagScope.allTime(),
            ),
            const SizedBox(width: 8),
            _ScopeChip(
              label: scope.kind == BagScopeKind.single
                  ? (scope.sessionName ?? 'Session')
                  : 'Pick session',
              selected: scope.kind == BagScopeKind.single,
              onTap: () => _pickSession(context, ref),
            ),
            if (showOutlierToggle) ...[
              const SizedBox(width: 16),
              _ScopeChip(
                label: 'Include outliers',
                selected: include,
                onTap: () =>
                    ref.read(bagIncludeOutliersProvider.notifier).state =
                        !include,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _pickSession(BuildContext context, WidgetRef ref) {
    final liveShots = ref.read(launchMonitorProvider).shots;
    final sessions = ref.read(sessionsProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Show data from',
              style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (liveShots.isNotEmpty)
                  ListTile(
                    title: Text(
                      'Active session',
                      style: AppTextStyles.sans(size: 14),
                    ),
                    subtitle: Text(
                      '${liveShots.length} shots',
                      style: AppTextStyles.sans(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onTap: () {
                      ref
                          .read(bagScopeProvider.notifier)
                          .state = const BagScope.single(
                        BagScope.liveSessionId,
                        'Active session',
                      );
                      Navigator.pop(ctx);
                    },
                  ),
                for (final s in sessions)
                  ListTile(
                    title: Text(
                      s.name.isEmpty ? 'Recovered session' : s.name,
                      style: AppTextStyles.sans(size: 14),
                    ),
                    subtitle: Text(
                      '${s.shots.length} shots',
                      style: AppTextStyles.sans(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onTap: () {
                      ref
                          .read(bagScopeProvider.notifier)
                          .state = BagScope.single(
                        s.id,
                        s.name.isEmpty ? 'Recovered session' : s.name,
                      );
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.accentSubtle : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? context.accent : AppColors.border2,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.sans(
              size: 12,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? context.accent : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _DistTh extends StatelessWidget {
  final String label;

  const _DistTh(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Text(
        label,
        style: AppTextStyles.sans(
          size: 9,
          weight: FontWeight.w400,
          color: AppColors.textDimmed,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _DistCell extends StatelessWidget {
  final String value;
  final bool highlight;

  const _DistCell(this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Text(
        value,
        style: AppTextStyles.mono(
          size: 14,
          color: highlight ? Colors.white : AppColors.textMuted,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

// ── Dispersion tab wrapper ────────────────────────────────────────────────────

class _DispersionTabWrapper extends ConsumerWidget {
  const _DispersionTabWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Session history under the shared bag scope — not just the live
    // session, which is empty whenever you browse the bag between rounds.
    final shots = ref.watch(bagShotsProvider);
    final clubs = ref.watch(clubsProvider);
    final selected = ref.watch(selectedClubProvider);

    return Column(
      children: [
        const _BagScopeBar(showOutlierToggle: false),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: shots.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.blur_on,
                        size: 40,
                        color: AppColors.textDimmed,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No dispersion data in this range',
                        style: AppTextStyles.sans(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hit shots in a session, or widen the scope above',
                        style: AppTextStyles.sans(
                          size: 12,
                          color: AppColors.textDimmed,
                        ),
                      ),
                    ],
                  ),
                )
              : DispersionTab(
                  allShots: shots,
                  clubs: clubs,
                  selectedClub: selected,
                  onClubSelected: (club) =>
                      ref.read(selectedClubProvider.notifier).state = club,
                  showSidebar: true,
                ),
        ),
      ],
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.sans(size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

// ── Add Clubs screen ───────────────────────────────────────────────────────────

class AddClubsScreen extends ConsumerStatefulWidget {
  const AddClubsScreen({super.key});

  @override
  ConsumerState<AddClubsScreen> createState() => _AddClubsScreenState();
}

class _AddClubsScreenState extends ConsumerState<AddClubsScreen> {
  /// Clubs already in the bag — shown locked. This screen only adds;
  /// removal lives in the bag list, which has undo and keeps club tags.
  late final Set<String> _inBag;

  /// Newly picked clubs, added on apply.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _inBag = ref.read(clubsProvider).map((c) => c.id).toSet();
  }

  void _toggle(String id) {
    if (_inBag.contains(id)) return;
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _apply() {
    final notifier = ref.read(clubsProvider.notifier);
    // Catalog order, so new clubs land in their natural section order.
    for (final club in Club.catalog) {
      if (_selected.contains(club.id)) notifier.addClub(club);
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    const sectionOrder = [
      ClubType.wood,
      ClubType.miniDriver,
      ClubType.hybrid,
      ClubType.iron,
      ClubType.wedge,
      ClubType.putter,
    ];

    // Group catalog clubs by type.
    final groups = <ClubType, List<Club>>{};
    for (final c in Club.catalog) {
      groups.putIfAbsent(c.type, () => []).add(c);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Add clubs',
                    style: AppTextStyles.sans(
                      size: 17,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _apply,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selected.isEmpty
                                ? 'Done'
                                : 'Add ${_selected.length}',
                            style: AppTextStyles.sans(
                              size: 13,
                              weight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Club grid
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    for (final type in sectionOrder)
                      if (groups.containsKey(type)) ...[
                        // Full-width section header
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12, top: 8),
                            child: Text(
                              Club.groupLabel(type),
                              style: AppTextStyles.sans(
                                size: 9,
                                weight: FontWeight.w600,
                                color: AppColors.textDimmed,
                              ),
                            ),
                          ),
                        ),
                        // Club circles row
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final club in groups[type]!)
                                _ClubCircle(
                                  club: club,
                                  selected: _selected.contains(club.id),
                                  inBag: _inBag.contains(club.id),
                                  onTap: () => _toggle(club.id),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClubCircle extends StatelessWidget {
  final Club club;
  final bool selected;

  /// Already in the bag: rendered locked. Removal is the bag list's job.
  final bool inBag;

  final VoidCallback onTap;

  const _ClubCircle({
    required this.club,
    required this.selected,
    required this.inBag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: inBag ? '${club.shortName} is already in the bag' : '',
      child: Semantics(
        button: !inBag,
        selected: selected,
        label: inBag ? '${club.shortName}, already in bag' : club.shortName,
        child: GestureDetector(
          onTap: inBag ? null : onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? context.accentGhost : AppColors.card,
              border: Border.all(
                color: selected ? context.accent : AppColors.border2,
                width: selected ? 2.0 : 1.0,
              ),
            ),
            child: Center(
              child: inBag
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          club.shortName,
                          style: AppTextStyles.sans(
                            size: 13,
                            color: AppColors.textDimmed,
                          ),
                        ),
                        const Icon(
                          Icons.check,
                          size: 10,
                          color: AppColors.textDimmed,
                        ),
                      ],
                    )
                  : Text(
                      club.shortName,
                      style: AppTextStyles.sans(
                        size: 13,
                        weight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? context.accent : Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
