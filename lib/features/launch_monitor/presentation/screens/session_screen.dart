import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/sessions_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/error_banner.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/shot_optimizer_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/shot_list_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/club_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/table_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── View enums ─────────────────────────────────────────────────────────────────

enum _ActiveView { split, tiles, dispersion, club, table }

enum _ActivePaneView { tiles, dispersion, club, table }

// ── Main screen ───────────────────────────────────────────────────────────────

class SessionScreen extends ConsumerStatefulWidget {
  final String? initialName;

  const SessionScreen({super.key, this.initialName});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  _ActiveView _view = _ActiveView.split;
  _ActivePaneView _splitLeft = _ActivePaneView.table;
  _ActivePaneView _splitRight = _ActivePaneView.dispersion;
  bool _showShotList = false;
  ShotListMetric _shotListMetric = ShotListMetric.carry;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(launchMonitorProvider.select((s) => s.status));
    final allShots = ref.watch(launchMonitorProvider.select((s) => s.shots));
    final error = ref.watch(launchMonitorProvider.select((s) => s.error));
    final notifier = ref.read(launchMonitorProvider.notifier);
    // activeClub: sets which club new shots are tagged with (bottom pill)
    final activeClub = ref.watch(activeClubProvider);
    // filterClub: filters TABLE / TILES / CLUB views (set by shot-list panel)
    final filterClub = ref.watch(selectedClubProvider);
    final clubs = ref.watch(clubsProvider);

    final shotsForClub = filterClub == null
        ? allShots
        : allShots.where((s) => s.clubId == filterClub.id).toList();

    // Auto-advance selection to the newest shot when a new shot arrives.
    ref.listen(launchMonitorProvider.select((s) => s.shots.length),
        (prev, next) {
      if (next > (prev ?? 0)) {
        ref.read(selectedShotIndexProvider.notifier).state = 0;
      }
    });

    final selectedShotIdx = ref.watch(selectedShotIndexProvider);
    final safeIdx = allShots.isEmpty
        ? 0
        : selectedShotIdx.clamp(0, allShots.length - 1);
    final selectedShot = allShots.isEmpty ? null : allShots[safeIdx];
    final selectedInClub = selectedShot == null
        ? -1
        : shotsForClub.indexOf(selectedShot);

    Widget content = switch (_view) {
      _ActiveView.split => _ActiveSplitView(
        shots: shotsForClub,
        allShots: allShots,
        clubs: clubs,
        filterClub: filterClub,
        highlightedShot: selectedShot,
        leftPane: _splitLeft,
        rightPane: _splitRight,
        selectedShotIndex: selectedInClub >= 0 ? selectedInClub : 0,
        onLeftChanged: (v) => setState(() => _splitLeft = v),
        onRightChanged: (v) => setState(() => _splitRight = v),
        onShotSelected: (i) =>
            ref.read(selectedShotIndexProvider.notifier).state = i ?? 0,
      ),
      _ActiveView.tiles => TilesTab(shots: shotsForClub, selectedShot: selectedShot),
      _ActiveView.dispersion => DispersionTab(
        allShots: allShots,
        clubs: clubs,
        selectedClub: filterClub,
        highlightedShot: selectedShot,
        onClubSelected: (_) {},
      ),
      _ActiveView.club => ClubTab(
        shots: shotsForClub,
        clubs: clubs,
        selectedShot: selectedInClub >= 0 ? selectedShot : null,
      ),
      _ActiveView.table => _TableWrapper(
        shots: shotsForClub,
        selectedIndex: selectedInClub >= 0 ? selectedInClub : 0,
        onRowTap: (i) =>
            ref.read(selectedShotIndexProvider.notifier).state = i,
      ),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ActiveSessionTopBar(
              status: status,
              name: widget.initialName,
              onClose: () => _confirmFinish(context),
            ),
            _ActiveNavBar(
              view: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
            if (error != null) ErrorBanner(message: error),
            Expanded(
              child: isUltraWide(context)
                  // ── Ultra-wide: shot list always pinned + content + analysis panel
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: ShotListPanel(
                            allShots: allShots,
                            clubs: clubs,
                            selectedShotIndex: safeIdx,
                            metric: _shotListMetric,
                            onMetricChanged: (m) =>
                                setState(() => _shotListMetric = m),
                            onShotSelected: (i) =>
                                ref.read(selectedShotIndexProvider.notifier).state = i,
                            onClearShots: notifier.clearShots,
                            onUpdateShotTags: notifier.updateShotTags,
                            onDeleteShots: notifier.deleteShots,
                          ),
                        ),
                        Expanded(child: content),
                        SizedBox(
                          width: 380,
                          child: const ShotOptimizerPanel(),
                        ),
                      ],
                    )
                  : isTablet(context)
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
                                  ref.read(selectedShotIndexProvider.notifier).state = i,
                              onClearShots: notifier.clearShots,
                              onUpdateShotTags: notifier.updateShotTags,
                              onDeleteShots: notifier.deleteShots,
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
                              child: const ColoredBox(color: AppColors.scrim,
                                child: SizedBox.expand()),
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
                                    ref.read(selectedShotIndexProvider.notifier).state = i,
                                onClearShots: notifier.clearShots,
                                onUpdateShotTags: notifier.updateShotTags,
                                onDeleteShots: notifier.deleteShots,
                              ),
                            ),
                          ),
                        ),
                        ],
                      ),
                    ),
            ),
            _ActiveBottomBar(
              shotCount: allShots.length,
              activeClub: activeClub,
              onClubTap: () => _showClubPicker(context, clubs, activeClub),
              onShotListToggle: () =>
                  setState(() => _showShotList = !_showShotList),
              showShotList: _showShotList,
              hideShotListToggle: isUltraWide(context),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmFinish(BuildContext context) {
    final allShots = ref.read(launchMonitorProvider.select((s) => s.shots));
    final clubs = ref.read(clubsProvider);
    final notifier = ref.read(launchMonitorProvider.notifier);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _FinishConfirmDialog(
        shotCount: allShots.length,
        onFinish: () {
          Navigator.of(dialogCtx).pop();
          Future.microtask(() {
            if (!mounted) return;
            _showSessionSummary(
              context, // ignore: use_build_context_synchronously
              notifier,
              allShots,
              clubs,
            );
          });
        },
        onAbandon: () {
          notifier.clearShots();
          Navigator.of(dialogCtx).pop();
          context.pop(); // ignore: use_build_context_synchronously
        },
        onNevermind: () => Navigator.of(dialogCtx).pop(),
      ),
    );
  }

  void _showSessionSummary(
    BuildContext context,
    dynamic notifier,
    List<ShotData> allShots,
    List<Club> clubs,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SessionSummarySheet(
        allShots: allShots,
        clubs: clubs,
        initialName: widget.initialName,
        onSave: (name) {
          final draftId = notifier.draftSessionId;
          final createdAt = notifier.draftCreatedAt ?? DateTime.now();
          final session = Session(
            id: draftId?.toString() ??
                DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            createdAt: createdAt,
            shots: List.from(allShots),
          );
          ref
              .read(sessionsProvider.notifier)
              .addSession(session, draftSessionId: draftId);
          notifier.clearShots();
          if (mounted) {
            context.pop(); // close sheet
            context.pop(); // close session screen
          }
        },
      ),
    );
  }

  void _showClubPicker(BuildContext context, List<Club> clubs, Club? selected) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ClubPickerSheet(
        clubs: clubs,
        selected: selected,
        onSelect: (club) {
          ref.read(activeClubProvider.notifier).state = club;
          context.pop();
        },
      ),
    );
  }
}

// ── Active session top bar ─────────────────────────────────────────────────────

class _ActiveSessionTopBar extends StatelessWidget {
  final LaunchMonitorStatus status;
  final String? name;
  final VoidCallback onClose;

  const _ActiveSessionTopBar({required this.status, this.name, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _CircleButton(
            onTap: onClose,
            child: const Icon(
              Icons.close,
              size: 14,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Active session',
                  style: AppTextStyles.sans(size: 15, weight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Live',
                      style: AppTextStyles.sans(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _CircleButton(
            onTap: () {},
            child: Icon(
              Icons.circle,
              size: 10,
              color: switch (status) {
                LaunchMonitorStatus.connected    => Colors.green,
                LaunchMonitorStatus.connecting   => Colors.orange,
                LaunchMonitorStatus.scanning     => Colors.blue,
                LaunchMonitorStatus.disconnected => Colors.red,
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Navigation bar ─────────────────────────────────────────────────────────────

class _ActiveNavBar extends StatelessWidget {
  final _ActiveView view;
  final ValueChanged<_ActiveView> onChanged;

  const _ActiveNavBar({required this.view, required this.onChanged});

  static const _items = [
    (_ActiveView.split, Icons.view_column, 'Split view'),
    (_ActiveView.tiles, Icons.grid_view_rounded, 'Tiles'),
    (_ActiveView.dispersion, Icons.scatter_plot, 'Dispersion'),
    (_ActiveView.club, Icons.sports_golf, 'Club'),
    (_ActiveView.table, Icons.table_rows, 'Table'),
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

// ── Configurable split view ────────────────────────────────────────────────────

class _ActiveSplitView extends StatelessWidget {
  final List<ShotData> shots;
  final List<ShotData> allShots;
  final List<Club> clubs;
  final Club? filterClub;
  final ShotData? highlightedShot;
  final _ActivePaneView leftPane;
  final _ActivePaneView rightPane;
  final int selectedShotIndex;
  final ValueChanged<_ActivePaneView> onLeftChanged;
  final ValueChanged<_ActivePaneView> onRightChanged;
  final ValueChanged<int?> onShotSelected;

  const _ActiveSplitView({
    required this.shots,
    required this.allShots,
    required this.clubs,
    required this.filterClub,
    required this.highlightedShot,
    required this.leftPane,
    required this.rightPane,
    required this.selectedShotIndex,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onShotSelected,
  });

  Widget _paneContent(_ActivePaneView view) {
    switch (view) {
      case _ActivePaneView.tiles:
        return TilesTab(shots: shots, selectedShot: highlightedShot);
      case _ActivePaneView.dispersion:
        return DispersionTab(
          allShots: allShots,
          clubs: clubs,
          selectedClub: filterClub,
          highlightedShot: highlightedShot,
          onClubSelected: (_) {},
        );
      case _ActivePaneView.club:
        return ClubTab(
          shots: shots,
          clubs: clubs,
          selectedShot: highlightedShot,
        );
      case _ActivePaneView.table:
        return _TableWrapper(
          shots: shots,
          selectedIndex: selectedShotIndex,
          onRowTap: (i) => onShotSelected(selectedShotIndex == i ? null : i),
        );
    }
  }

  Widget _pane(_ActivePaneView view, ValueChanged<_ActivePaneView> onChanged) {
    return Column(
      children: [
        _ActivePaneHeader(current: view, onChanged: onChanged),
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
            width: 1,
            thickness: 1,
            color: AppColors.border,
          ),
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

// ── Pane header (dropdown to switch pane view) ─────────────────────────────────

class _ActivePaneHeader extends StatelessWidget {
  final _ActivePaneView current;
  final ValueChanged<_ActivePaneView> onChanged;

  const _ActivePaneHeader({required this.current, required this.onChanged});

  static const _options = [
    (_ActivePaneView.tiles, Icons.grid_view_rounded, 'Tiles'),
    (_ActivePaneView.dispersion, Icons.scatter_plot, 'Dispersion'),
    (_ActivePaneView.club, Icons.sports_golf, 'Club'),
    (_ActivePaneView.table, Icons.table_rows, 'Table'),
  ];

  String get _label => _options.firstWhere((o) => o.$1 == current).$3;
  IconData get _icon => _options.firstWhere((o) => o.$1 == current).$2;

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
              const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.textMuted,
              ),
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
        builder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Select View',
                    style: AppTextStyles.sans(
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            ..._options.map((opt) {
              final (view, icon, label) = opt;
              final isSel = view == current;
              return ListTile(
                leading: Icon(
                  icon,
                  size: 18,
                  color: isSel ? AppColors.accent : AppColors.textMuted,
                ),
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
                onTap: () {
                  onChanged(view);
                  context.pop();
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    });
  }
}

// ── TableTab wrapper ───────────────────────────────────────────────────────────

class _TableWrapper extends ConsumerWidget {
  final List<ShotData> shots;
  final int selectedIndex;
  final ValueChanged<int>? onRowTap;

  const _TableWrapper({
    required this.shots,
    this.selectedIndex = 0,
    this.onRowTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(selectedClubProvider);
    return TableTab(
      shots: shots,
      club: club,
      selectedIndex: selectedIndex,
      onRowTap: onRowTap,
    );
  }
}

// ── Active bottom bar ──────────────────────────────────────────────────────────

class _ActiveBottomBar extends StatelessWidget {
  final int shotCount;
  final Club? activeClub;
  final VoidCallback onClubTap;
  final VoidCallback onShotListToggle;
  final bool showShotList;
  final bool hideShotListToggle;

  const _ActiveBottomBar({
    required this.shotCount,
    required this.activeClub,
    required this.onClubTap,
    required this.onShotListToggle,
    required this.showShotList,
    this.hideShotListToggle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: AppColors.background,
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left: shot-list toggle with count badge (hidden in ultra-wide)
          if (!hideShotListToggle)
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
                  if (shotCount > 0)
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
                            '$shotCount',
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
          // Centre: active club pill
          GestureDetector(
            onTap: onClubTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: activeClub?.color ?? AppColors.border2,
                  width: activeClub != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeClub != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: activeClub!.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else ...[
                    const Icon(
                      Icons.sports_golf,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    activeClub?.shortName ?? 'Select Club',
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: FontWeight.w600,
                      color: activeClub?.color ?? Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 14,
                    color: AppColors.textMuted,
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

// ── Circle button ──────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _CircleButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border2),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── Step 1: confirm dialog ─────────────────────────────────────────────────────

class _FinishConfirmDialog extends StatelessWidget {
  final int shotCount;
  final VoidCallback onFinish;
  final VoidCallback onAbandon;
  final VoidCallback onNevermind;

  const _FinishConfirmDialog({
    required this.shotCount,
    required this.onFinish,
    required this.onAbandon,
    required this.onNevermind,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Finish Session?',
              style: AppTextStyles.sans(size: 17, weight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$shotCount ${shotCount == 1 ? 'shot' : 'shots'} recorded.',
              style: AppTextStyles.sans(size: 13, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onFinish,
                child: Text(
                  'Continue to Summary',
                  style: AppTextStyles.sans(
                    weight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  side: const BorderSide(color: AppColors.border2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onAbandon,
                child: Text(
                  'Abandon Session',
                  style: AppTextStyles.sans(color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onNevermind,
              child: Text(
                'Nevermind',
                style: AppTextStyles.sans(color: AppColors.textDimmed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 2: session summary sheet ─────────────────────────────────────────────

class _SessionSummarySheet extends StatelessWidget {
  final List<ShotData> allShots;
  final List<Club> clubs;
  final String? initialName;
  final ValueChanged<String> onSave;

  const _SessionSummarySheet({
    required this.allShots,
    required this.clubs,
    this.initialName,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final sessionName = initialName ?? 'Session - $dateStr';

    final clubCounts = <String, int>{};
    for (final s in allShots) {
      if (s.clubId != null) {
        clubCounts[s.clubId!] = (clubCounts[s.clubId!] ?? 0) + 1;
      }
    }
    final clubsUsed = clubs.where((c) => clubCounts.containsKey(c.id)).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session Summary',
                    style: AppTextStyles.sans(
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${allShots.length}',
                                style: AppTextStyles.mono(size: 28),
                              ),
                              Text(
                                'shots',
                                style: AppTextStyles.sans(
                                  size: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${clubsUsed.length}',
                                style: AppTextStyles.mono(size: 28),
                              ),
                              Text(
                                'clubs',
                                style: AppTextStyles.sans(
                                  size: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (clubsUsed.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Clubs Used',
                      style: AppTextStyles.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...clubsUsed.map(
                      (club) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: club.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              club.shortName,
                              style: AppTextStyles.sans(size: 13),
                            ),
                            const Spacer(),
                            Text(
                              '${clubCounts[club.id]} '
                              '${(clubCounts[club.id] ?? 0) == 1 ? 'shot' : 'shots'}',
                              style: AppTextStyles.sans(
                                size: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => onSave(sessionName),
                      child: Text(
                        'Save & Finish',
                        style: AppTextStyles.sans(
                          size: 15,
                          weight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Club picker sheet ──────────────────────────────────────────────────────────

class _ClubPickerSheet extends StatelessWidget {
  final List<Club> clubs;
  final Club? selected;
  final ValueChanged<Club> onSelect;

  const _ClubPickerSheet({
    required this.clubs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Active Club',
            style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: clubs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final club = clubs[i];
              final isSelected = club.id == selected?.id;
              return ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: club.color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  club.shortName,
                  style: AppTextStyles.sans(
                    size: 14,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.accent : Colors.white,
                  ),
                ),
                subtitle: club.manufacturer != null || club.model != null
                    ? Text(
                        [
                          if (club.manufacturer != null) club.manufacturer!,
                          if (club.model != null) club.model!,
                        ].join(' · '),
                        style: AppTextStyles.sans(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      )
                    : null,
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.accent, size: 18)
                    : null,
                tileColor: Colors.transparent,
                onTap: () => onSelect(club),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

