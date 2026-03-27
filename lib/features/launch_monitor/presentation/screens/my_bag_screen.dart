import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/shared/theme.dart';

class MyBagScreen extends ConsumerWidget {
  const MyBagScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
                ),
                child: TabBar(
                  indicatorColor: AppColors.accent,
                  indicatorWeight: 2,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textDimmed,
                  labelStyle: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w400,
                  ),
                  unselectedLabelStyle: AppTextStyles.sans(size: 12),
                  tabs: const [
                    Tab(text: 'Clubs'),
                    Tab(text: 'Distances'),
                    Tab(text: 'Dispersion'),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _ClubsTab(),
                    _DistancesTab(),
                    _DispersionTabWrapper(),
                  ],
                ),
              ),
            ],
          ),
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
                    color: AppColors.textMuted),
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
                  _ClubTile(
                    club: club,
                    isSelected: isSelected,
                    onTap: () =>
                        ref.read(selectedClubProvider.notifier).state = club,
                    onEdit: () => _showEditSheet(context, ref, club),
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
    context.push('/bag/add-clubs');
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
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

  const _ClubTile({
    required this.club,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
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
          color: isSelected ? AppColors.accent : Colors.white,
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
          if (isSelected)
            const Icon(Icons.check, color: AppColors.accent, size: 16),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEdit,
            child: const Icon(
              Icons.edit,
              size: 16,
              color: AppColors.textMuted,
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
              borderSide: const BorderSide(color: AppColors.accent),
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
    final allShots = ref.watch(launchMonitorProvider.select((s) => s.shots));

    // Build per-club distance stats
    final stats =
        <({Club club, double avg, double high, double low, int count})>[];
    for (final club in clubs) {
      final shots = allShots.where((s) => s.clubId == club.id).toList();
      if (shots.isEmpty) continue;
      final carries = shots.map((s) => s.carry).toList();
      final avg = carries.reduce((a, b) => a + b) / carries.length;
      final high = carries.reduce((a, b) => a > b ? a : b);
      final low = carries.reduce((a, b) => a < b ? a : b);
      stats.add((
        club: club,
        avg: avg,
        high: high,
        low: low,
        count: shots.length,
      ));
    }

    if (stats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.straighten, size: 40, color: AppColors.textDimmed),
            const SizedBox(height: 12),
            Text(
              'No distance data yet',
              style: AppTextStyles.sans(color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'Hit shots in a session to see per-club distances',
              style: AppTextStyles.sans(size: 12, color: AppColors.textDimmed),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Column headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              _DistTh('AVG'),
              _DistTh('HIGH'),
              _DistTh('LOW'),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: stats.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final s = stats[i];
              return Padding(
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
                          Text(
                            '(${s.count})',
                            style: AppTextStyles.sans(
                              size: 10,
                              color: AppColors.textDimmed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _DistCell(s.avg.toStringAsFixed(0), highlight: true),
                    _DistCell(s.high.toStringAsFixed(0)),
                    _DistCell(s.low.toStringAsFixed(0)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
    final allShots = ref.watch(launchMonitorProvider.select((s) => s.shots));
    final clubs = ref.watch(clubsProvider);
    final selected = ref.watch(selectedClubProvider);

    if (allShots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.blur_on, size: 40, color: AppColors.textDimmed),
            const SizedBox(height: 12),
            Text(
              'No dispersion data yet',
              style: AppTextStyles.sans(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return DispersionTab(
      allShots: allShots,
      clubs: clubs,
      selectedClub: selected,
      onClubSelected: (club) =>
          ref.read(selectedClubProvider.notifier).state = club,
      showSidebar: true,
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
  // Local selection mirror — initialised from the current bag.
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(clubsProvider).map((c) => c.id).toSet();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _apply() {
    final notifier = ref.read(clubsProvider.notifier);
    final current = ref.read(clubsProvider).map((c) => c.id).toSet();

    // Add newly selected clubs (in catalog order).
    for (final club in Club.catalog) {
      if (_selected.contains(club.id) && !current.contains(club.id)) {
        notifier.addClub(club);
      }
    }
    // Remove de-selected clubs.
    for (final id in current) {
      if (!_selected.contains(id)) {
        notifier.removeClub(id);
      }
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
                    child: const Icon(Icons.arrow_back_ios,
                        size: 18, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    'Add clubs',
                    style: AppTextStyles.sans(
                        size: 17, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _apply,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_selected.length}/${Club.catalog.length}',
                            style: AppTextStyles.sans(
                                size: 13,
                                weight: FontWeight.w600,
                                color: Colors.black),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: Colors.black),
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
  final VoidCallback onTap;

  const _ClubCircle({
    required this.club,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? AppColors.accentGhost
              : AppColors.card,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border2,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            club.shortName,
            style: AppTextStyles.sans(
              size: 13,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.accent : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
