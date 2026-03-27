import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/shot_list_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/club_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/table_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/application/sessions_notifier.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── Top-level view options ────────────────────────────────────────────────────

enum _TopView { split, tiles, dispersion, club, table }

// Options available inside a split pane
enum _PaneView { tiles, dispersion, club, table }

// ── Main screen ───────────────────────────────────────────────────────────────

class SessionDetailScreen extends ConsumerStatefulWidget {
  final Session session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  _TopView _view = _TopView.split;

  // Split pane configuration — persists across view switches
  _PaneView _splitLeft = _PaneView.table;
  _PaneView _splitRight = _PaneView.dispersion;

  // Index into allShots.
  int _selectedShotIndex = 0;

  // Shot list panel state
  bool _showShotList = false;
  ShotListMetric _shotListMetric = ShotListMetric.carry;

  Future<void> _updateShotTags(
      List<ShotData> allShots, int shotIndex, List<int> tagIds) async {
    if (shotIndex >= allShots.length) return;
    final shot = allShots[shotIndex];
    if (shot.dbId != null) {
      await ref.read(sessionsProvider.notifier).updateShotTags(shot.dbId!, tagIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(clubsProvider);
    // Watch live session so tag updates reflect immediately.
    final allShots = ref
        .watch(sessionsProvider)
        .firstWhere((s) => s.id == widget.session.id,
            orElse: () => widget.session)
        .shots;

    final safeIdx = allShots.isEmpty
        ? 0
        : _selectedShotIndex.clamp(0, allShots.length - 1);
    final highlighted = allShots.isEmpty ? null : allShots[safeIdx];
    final shots = allShots;

    final selectedInClub = highlighted == null ? 0 : shots.indexOf(highlighted);

    Widget content = switch (_view) {
      _TopView.split => _SplitViewConfigurable(
          shots: shots,
          allShots: allShots,
          clubs: clubs,
          highlightedShot: highlighted,
          leftPane: _splitLeft,
          rightPane: _splitRight,
          selectedShotIndex: selectedInClub >= 0 ? selectedInClub : 0,
          onLeftChanged: (v) => setState(() => _splitLeft = v),
          onRightChanged: (v) => setState(() => _splitRight = v),
          onShotSelected: (i) => setState(() {
            if (i != null && i < shots.length) {
              final allIdx = allShots.indexOf(shots[i]);
              _selectedShotIndex = allIdx >= 0 ? allIdx : 0;
            }
          }),
        ),
      _TopView.tiles => TilesTab(shots: shots, selectedShot: highlighted),
      _TopView.dispersion => DispersionTab(
          allShots: allShots,
          clubs: clubs,
          highlightedShot: highlighted,
          onClubSelected: (_) {},
        ),
      _TopView.club =>
        ClubTab(shots: shots, clubs: clubs, selectedShot: highlighted),
      _TopView.table => TableTab(
          shots: shots,
          selectedIndex: selectedInClub >= 0 ? selectedInClub : 0,
          onRowTap: (i) => setState(() {
            if (i < shots.length) {
              final allIdx = allShots.indexOf(shots[i]);
              _selectedShotIndex = allIdx >= 0 ? allIdx : 0;
            }
          }),
        ),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _DetailTopBar(
              session: widget.session,
              onBack: () => context.pop(),
            ),
            _TopNav(
              view: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
            Expanded(
              child: isTablet(context)
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          width: _showShotList ? 300.0 : 0.0,
                          clipBehavior: Clip.hardEdge,
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                          ),
                          child: SizedBox(
                            width: 300,
                            child: ShotListPanel(
                              allShots: allShots,
                              clubs: clubs,
                              selectedShotIndex: safeIdx,
                              metric: _shotListMetric,
                              onMetricChanged: (m) =>
                                  setState(() => _shotListMetric = m),
                              onShotSelected: (i) =>
                                  setState(() => _selectedShotIndex = i),
                              onUpdateShotTags: (i, tags) =>
                                  _updateShotTags(allShots, i, tags),
                            ),
                          ),
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (details) {
                        final vx = details.velocity.pixelsPerSecond.dx;
                        if (!_showShotList && vx > 300) {
                          setState(() => _showShotList = true);
                        } else if (_showShotList && vx < -300) {
                          setState(() => _showShotList = false);
                        }
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(child: content),
                          IgnorePointer(
                            ignoring: !_showShotList,
                            child: AnimatedOpacity(
                              opacity: _showShotList ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _showShotList = false),
                                child: const ColoredBox(
                                  color: AppColors.scrim,
                                  child: SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: 0,
                            child: AnimatedSlide(
                              offset: _showShotList
                                  ? Offset.zero
                                  : const Offset(-1, 0),
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                              child: Container(
                                width: 300,
                                decoration: const BoxDecoration(
                                  color: AppColors.background,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 12,
                                      offset: Offset(4, 0),
                                    ),
                                  ],
                                ),
                                child: ShotListPanel(
                                  allShots: allShots,
                                  clubs: clubs,
                                  selectedShotIndex: safeIdx,
                                  metric: _shotListMetric,
                                  onMetricChanged: (m) =>
                                      setState(() => _shotListMetric = m),
                                  onShotSelected: (i) =>
                                      setState(() => _selectedShotIndex = i),
                                  onUpdateShotTags: (i, tags) =>
                                      _updateShotTags(allShots, i, tags),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            _BottomBar(
              session: widget.session,
              showShotList: _showShotList,
              onShotListToggle: () =>
                  setState(() => _showShotList = !_showShotList),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top navigation bar ────────────────────────────────────────────────────────

class _TopNav extends StatelessWidget {
  final _TopView view;
  final ValueChanged<_TopView> onChanged;

  const _TopNav({required this.view, required this.onChanged});

  static const _items = [
    (_TopView.split, Icons.view_column, 'Split view'),
    (_TopView.tiles, Icons.grid_view_rounded, 'Tiles'),
    (_TopView.dispersion, Icons.scatter_plot, 'Dispersion'),
    (_TopView.club, Icons.sports_golf, 'Club'),
    (_TopView.table, Icons.table_rows, 'Table'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        color: AppColors.background,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _items.map((item) {
          final (v, icon, label) = item;
          final active = view == v;
          return _NavItem(
            icon: icon,
            label: label,
            active: active,
            onTap: () => onChanged(v),
          );
        }).toList(),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textMuted;
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
            // Active underline indicator
            if (active)
              Positioned(
                bottom: 0,
                left: 8,
                right: 8,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
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

// ── Split view (configurable) ─────────────────────────────────────────────────

class _SplitViewConfigurable extends StatelessWidget {
  final List<ShotData> shots;
  final List<ShotData> allShots;
  final List<Club> clubs;
  final ShotData? highlightedShot;
  final _PaneView leftPane;
  final _PaneView rightPane;
  final int? selectedShotIndex;
  final ValueChanged<_PaneView> onLeftChanged;
  final ValueChanged<_PaneView> onRightChanged;
  final ValueChanged<int?> onShotSelected;

  const _SplitViewConfigurable({
    required this.shots,
    required this.allShots,
    required this.clubs,
    required this.highlightedShot,
    required this.leftPane,
    required this.rightPane,
    required this.selectedShotIndex,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onShotSelected,
  });

  Widget _paneContent(_PaneView view) {
    switch (view) {
      case _PaneView.tiles:
        return TilesTab(shots: shots, selectedShot: highlightedShot);
      case _PaneView.dispersion:
        return DispersionTab(
          allShots: allShots,
          clubs: clubs,
          highlightedShot: highlightedShot,
          onClubSelected: (_) {},
        );
      case _PaneView.club:
        return ClubTab(shots: shots, clubs: clubs, selectedShot: highlightedShot);
      case _PaneView.table:
        return TableTab(
          shots: shots,
          selectedIndex: selectedShotIndex,
          onRowTap: (i) => onShotSelected(selectedShotIndex == i ? null : i),
        );
    }
  }

  Widget _pane(_PaneView view, ValueChanged<_PaneView> onChanged) {
    return Column(
      children: [
        _PaneHeader(current: view, onChanged: onChanged),
        Expanded(child: _paneContent(view)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isTablet(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _pane(leftPane, onLeftChanged)),
          const VerticalDivider(
              width: 1, thickness: 1, color: AppColors.border),
          Expanded(child: _pane(rightPane, onRightChanged)),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: _pane(leftPane, onLeftChanged)),
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: _pane(rightPane, onRightChanged)),
      ],
    );
  }
}

// ── Pane header — "View Name ▼" dropdown style ────────────────────────────────

class _PaneHeader extends StatelessWidget {
  final _PaneView current;
  final ValueChanged<_PaneView> onChanged;

  const _PaneHeader({required this.current, required this.onChanged});

  static const _options = [
    (_PaneView.tiles, Icons.grid_view_rounded, 'Tiles'),
    (_PaneView.dispersion, Icons.scatter_plot, 'Dispersion'),
    (_PaneView.club, Icons.sports_golf, 'Club'),
    (_PaneView.table, Icons.table_rows, 'Table'),
  ];

  String get _label =>
      _options.firstWhere((o) => o.$1 == current).$3;

  IconData get _icon =>
      _options.firstWhere((o) => o.$1 == current).$2;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        color: AppColors.surface,
      ),
      child: GestureDetector(
        onTap: () => _showPicker(context),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                _label,
                style: AppTextStyles.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down,
                  size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    Future.microtask(() {
      if (!context.mounted) return;
      showModalBottomSheet<void>(
        context: context, // ignore: use_build_context_synchronously
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _PanePickerSheet(
          current: current,
          options: _options,
          onSelect: (v) {
            onChanged(v);
            // ignore: use_build_context_synchronously
            context.pop();
          },
        ),
      );
    });
  }
}

class _PanePickerSheet extends StatelessWidget {
  final _PaneView current;
  final List<(_PaneView, IconData, String)> options;
  final ValueChanged<_PaneView> onSelect;

  const _PanePickerSheet({
    required this.current,
    required this.options,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Select View',
                  style: AppTextStyles.sans(
                      size: 16, weight: FontWeight.w600)),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        ...options.map((opt) {
          final (view, icon, label) = opt;
          final isSel = view == current;
          return ListTile(
            leading: Icon(icon,
                size: 18,
                color: isSel ? AppColors.accent : AppColors.textMuted),
            title: Text(
              label,
              style: AppTextStyles.sans(
                size: 14,
                weight: isSel ? FontWeight.w600 : FontWeight.w400,
                color: isSel ? AppColors.accent : Colors.white,
              ),
            ),
            trailing: isSel
                ? const Icon(Icons.check, color: AppColors.accent, size: 18)
                : null,
            tileColor: Colors.transparent,
            onTap: () => onSelect(view),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _DetailTopBar extends StatelessWidget {
  final Session session;
  final VoidCallback onBack;

  const _DetailTopBar({
    required this.session,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border2),
              ),
              child: const Center(
                child: Icon(Icons.arrow_back,
                    size: 14, color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style:
                      AppTextStyles.sans(size: 15, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDate(session.createdAt),
                  style: AppTextStyles.sans(
                      size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── Bottom bar: summary + centered club pill ──────────────────────────────────

class _BottomBar extends StatelessWidget {
  final Session session;
  final bool showShotList;
  final VoidCallback onShotListToggle;

  const _BottomBar({
    required this.session,
    required this.showShotList,
    required this.onShotListToggle,
  });

  @override
  Widget build(BuildContext context) {
    final total = session.shotCount;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: AppColors.background,
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left: shot list toggle with count badge
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onShotListToggle,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: showShotList
                          ? AppColors.accentSubtle
                          : AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: showShotList
                            ? AppColors.accent
                            : AppColors.border2,
                      ),
                    ),
                    child: Icon(
                      Icons.menu,
                      size: 16,
                      color: showShotList
                          ? AppColors.accent
                          : AppColors.textMuted,
                    ),
                  ),
                  if (total > 0)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$total',
                            style: AppTextStyles.sans(
                              size: 8,
                              weight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
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
