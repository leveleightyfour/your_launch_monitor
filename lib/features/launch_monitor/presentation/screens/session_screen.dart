import 'dart:async';

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
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/device_picker_sheet.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/error_banner.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/shot_optimizer_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/shot_list_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/camera_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/club_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/table_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

// ── View enums ─────────────────────────────────────────────────────────────────

enum _ActiveView {
  split,
  tiles,
  dispersion,
  flight,
  club,
  table,
  optimizer,
  camera,
}

enum _ActivePaneView {
  tiles,
  dispersion,
  flight,
  club,
  table,
  optimizer,
  camera,
}

/// The camera feed needs a desktop camera backend, so it is offered only
/// there — in the nav bar, in the pane picker, and when restoring a stored
/// pane choice (prefs travel between a desktop and a phone via the same
/// account).
bool _viewAvailable(_ActiveView v) =>
    v != _ActiveView.camera || isDesktopPlatform;

bool _paneAvailable(_ActivePaneView v) =>
    v != _ActivePaneView.camera || isDesktopPlatform;

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
  _ActivePaneView _splitThird = _ActivePaneView.optimizer;
  bool _showShotList = false;
  ShotListMetric _shotListMetric = ShotListMetric.carry;

  /// The session's chosen name. Falls back to the name stashed on the
  /// notifier so leaving and resuming the session doesn't lose it (the
  /// resume route carries no `initialName`).
  String? get _sessionName =>
      widget.initialName ?? ref.read(launchMonitorProvider.notifier).draftName;

  @override
  void initState() {
    super.initState();
    // Stash the chosen name so it survives leave-and-resume.
    if (widget.initialName != null) {
      ref.read(launchMonitorProvider.notifier).draftName = widget.initialName;
    }
    // The split opens on whatever pair it was last configured to.
    final prefs = ref.read(unitPrefsProvider);
    _splitLeft = _paneFromName(prefs.splitLeftPane, _ActivePaneView.table);
    _splitRight = _paneFromName(
      prefs.splitRightPane,
      _ActivePaneView.dispersion,
    );
    _splitThird = _paneFromName(
      prefs.splitThirdPane,
      _ActivePaneView.optimizer,
    );
  }

  static _ActivePaneView _paneFromName(String name, _ActivePaneView fallback) =>
      _ActivePaneView.values.firstWhere(
        (v) => v.name == name && _paneAvailable(v),
        orElse: () => fallback,
      );

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(launchMonitorProvider.select((s) => s.status));
    final allShots = ref.watch(launchMonitorProvider.select((s) => s.shots));
    final error = ref.watch(launchMonitorProvider.select((s) => s.error));
    final battery = ref.watch(
      launchMonitorProvider.select((s) => s.batteryPercent),
    );
    final capacitorReady = ref.watch(
      launchMonitorProvider.select((s) => s.capacitorReady),
    );
    final detecting = ref.watch(
      launchMonitorProvider.select((s) => s.detecting),
    );
    final ballDetected = ref.watch(
      launchMonitorProvider.select((s) => s.ballDetected),
    );
    final ballReady = ref.watch(
      launchMonitorProvider.select((s) => s.ballReady),
    );
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
    ref.listen(launchMonitorProvider.select((s) => s.shots.length), (
      prev,
      next,
    ) {
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
        thirdPane: _splitThird,
        selectedShotIndex: selectedInClub >= 0 ? selectedInClub : 0,
        onLeftChanged: (v) {
          setState(() => _splitLeft = v);
          ref.read(unitPrefsProvider.notifier).setSplitPanes(left: v.name);
        },
        onRightChanged: (v) {
          setState(() => _splitRight = v);
          ref.read(unitPrefsProvider.notifier).setSplitPanes(right: v.name);
        },
        onThirdChanged: (v) {
          setState(() => _splitThird = v);
          ref.read(unitPrefsProvider.notifier).setSplitPanes(third: v.name);
        },
        onShotSelected: (i) =>
            ref.read(selectedShotIndexProvider.notifier).state = i ?? 0,
      ),
      _ActiveView.tiles => TilesTab(
        shots: shotsForClub,
        selectedShot: selectedShot,
      ),
      _ActiveView.dispersion => DispersionTab(
        allShots: allShots,
        clubs: clubs,
        selectedClub: filterClub,
        highlightedShot: selectedShot,
        onClubSelected: (_) {},
      ),
      _ActiveView.flight => Flight3DTab(
        shots: shotsForClub,
        selectedShot: selectedInClub >= 0 ? selectedShot : null,
        clubs: clubs,
      ),
      _ActiveView.club => ClubTab(
        shots: shotsForClub,
        clubs: clubs,
        selectedShot: selectedInClub >= 0 ? selectedShot : null,
      ),
      _ActiveView.table => _TableWrapper(
        shots: shotsForClub,
        selectedIndex: selectedInClub >= 0 ? selectedInClub : 0,
        onRowTap: (i) => ref.read(selectedShotIndexProvider.notifier).state = i,
      ),
      _ActiveView.optimizer => const ShotOptimizerPanel(showLeftBorder: false),
      _ActiveView.camera => const CameraTab(),
    };

    // The system back gesture must never skip the finish flow: with shots on
    // the board it routes through the same confirm dialog as the X button.
    // An empty session may leave freely (discarding any empty draft row).
    return PopScope(
      canPop: allShots.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Only an empty session pops directly; discard its empty draft.
          // A completed pop with shots on board is always programmatic
          // (leave / save / abandon), and those flows already handled the
          // draft — abandoning here would destroy a left-open session.
          if (ref.read(launchMonitorProvider).shots.isEmpty) {
            unawaited(
              ref.read(launchMonitorProvider.notifier).abandonSession(),
            );
          }
          return;
        }
        _confirmFinish(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _ActiveSessionTopBar(
                status: status,
                name: _sessionName,
                batteryPercent: battery,
                capacitorReady: capacitorReady,
                detecting: detecting,
                ballDetected: ballDetected,
                ballReady: ballReady,
                onToggleArm: status == LaunchMonitorStatus.connected
                    ? () => detecting
                          ? notifier.disarmBallDetection()
                          : notifier.armBallDetection()
                    : null,
                onClose: () => _confirmFinish(context),
                onSimulateShot:
                    ref.watch(
                      unitPrefsProvider.select((p) => p.showTestShotButton),
                    )
                    ? () => notifier.simulateShot()
                    : null,
              ),
              _ActiveNavBar(
                view: _view,
                onChanged: (v) => setState(() => _view = v),
              ),
              if (status != LaunchMonitorStatus.connected)
                _ConnectionBanner(status: status),
              if (error != null) ErrorBanner(message: error),
              Expanded(
                child: isUltraWide(context)
                    // ── Ultra-wide: shot list always pinned, content fills the
                    // rest. The optimizer is no longer a fixed rail here — it
                    // is one of the views the split's third pane can hold, so
                    // the width goes to whatever the golfer actually wants.
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
                                  ref
                                          .read(
                                            selectedShotIndexProvider.notifier,
                                          )
                                          .state =
                                      i,
                              onUpdateShotTags: notifier.updateShotTags,
                              onDeleteShots: notifier.deleteShots,
                            ),
                          ),
                          Expanded(child: content),
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
                                    ref
                                            .read(
                                              selectedShotIndexProvider
                                                  .notifier,
                                            )
                                            .state =
                                        i,
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
                                    onShotSelected: (i) {
                                      ref
                                              .read(
                                                selectedShotIndexProvider
                                                    .notifier,
                                              )
                                              .state =
                                          i;
                                      // Picking a shot is the whole point of
                                      // this drawer, and here it covers the
                                      // view — get out of the way so the shot
                                      // is visible.
                                      setState(() => _showShotList = false);
                                    },
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
      ),
    );
  }

  void _confirmFinish(BuildContext context) {
    final allShots = ref.read(launchMonitorProvider.select((s) => s.shots));
    final clubs = ref.read(clubsProvider);
    final notifier = ref.read(launchMonitorProvider.notifier);

    // Nothing recorded — nothing worth a dialog or an empty saved session.
    // Leave directly, discarding any empty draft row left by bulk-delete.
    if (allShots.isEmpty) {
      unawaited(notifier.abandonSession());
      context.pop();
      return;
    }

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
        onLeave: () {
          // Keep everything — shots, draft, connection — and step out.
          // The session list shows an active-session tile to return here.
          Navigator.of(dialogCtx).pop();
          context.pop(); // ignore: use_build_context_synchronously
        },
        onAbandon: () {
          unawaited(notifier.abandonSession());
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
        initialName: _sessionName,
        onSave: (name) {
          final draftId = notifier.draftSessionId;
          final createdAt = notifier.draftCreatedAt ?? DateTime.now();
          final session = Session(
            id:
                draftId?.toString() ??
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
  final int? batteryPercent;
  final bool capacitorReady;
  final bool detecting;
  final bool ballDetected;
  final bool ballReady;
  final VoidCallback? onToggleArm;
  final VoidCallback onClose;

  /// Injects a jittered seed shot for visualisation testing. Only non-null
  /// when the "Test shots" profile toggle is on.
  final VoidCallback? onSimulateShot;

  const _ActiveSessionTopBar({
    required this.status,
    this.name,
    this.batteryPercent,
    this.capacitorReady = false,
    this.detecting = false,
    this.ballDetected = false,
    this.ballReady = false,
    this.onToggleArm,
    required this.onClose,
    this.onSimulateShot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _CircleButton(
            onTap: onClose,
            label: 'Finish session',
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
                      decoration: BoxDecoration(
                        color: context.accent,
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
          if (status == LaunchMonitorStatus.connected) ...[
            if (batteryPercent != null) ...[
              _BatteryChip(percent: batteryPercent!),
              const SizedBox(width: 8),
            ],
            // Capacitor charging indicator — shown until the cap is ready.
            if (!capacitorReady) ...[
              const _CircleButton(
                onTap: null,
                label: 'Capacitor charging',
                child: Icon(
                  Icons.battery_charging_full,
                  size: 14,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Arm / disarm ball detection.
            _CircleButton(
              onTap: onToggleArm,
              label: detecting ? 'Stop ball detection' : 'Start ball detection',
              child: Icon(
                detecting ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 14,
                color: !capacitorReady
                    ? AppColors.textDimmed
                    : detecting
                    ? context.accent
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            // Ball ready / not-ready indicator.
            _BallReadyIndicator(
              detecting: detecting,
              ballDetected: ballDetected,
              ballReady: ballReady,
            ),
            const SizedBox(width: 8),
          ],
          if (onSimulateShot != null) ...[
            _CircleButton(
              onTap: onSimulateShot,
              label: 'Add test shot',
              child: Icon(Icons.bolt, size: 14, color: context.accent),
            ),
            const SizedBox(width: 8),
          ],
          _CircleButton(
            onTap: status == LaunchMonitorStatus.disconnected
                ? () => DevicePickerSheet.show(context)
                : null,
            label: switch (status) {
              LaunchMonitorStatus.connected => 'Connected',
              LaunchMonitorStatus.connecting => 'Connecting',
              LaunchMonitorStatus.scanning => 'Scanning for devices',
              LaunchMonitorStatus.disconnected =>
                'Disconnected. Tap to connect',
            },
            child: Icon(
              Icons.circle,
              size: 10,
              color: switch (status) {
                LaunchMonitorStatus.connected => Colors.green,
                LaunchMonitorStatus.connecting => Colors.orange,
                LaunchMonitorStatus.scanning => Colors.blue,
                LaunchMonitorStatus.disconnected => Colors.red,
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connection banner ──────────────────────────────────────────────────────────

/// Persistent banner shown whenever the device is anything but connected, so
/// a mid-bucket drop is never silent: without a connection, swings simply
/// don't register. Reconnection happens in place via the device picker.
class _ConnectionBanner extends StatelessWidget {
  final LaunchMonitorStatus status;

  const _ConnectionBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final busy =
        status == LaunchMonitorStatus.connecting ||
        status == LaunchMonitorStatus.scanning;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: busy ? AppColors.surface : AppColors.errorBackground,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textMuted,
              ),
            )
          else
            // A plain dot rather than an icon: it mirrors the top bar's
            // status-dot language, and it adds no new glyph to the
            // tree-shaken icon font (new glyphs can't ship in an OTA patch).
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.errorText,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              busy
                  ? (status == LaunchMonitorStatus.scanning
                        ? 'Scanning for devices…'
                        : 'Connecting…')
                  : "Device not connected. Swings won't be captured.",
              style: AppTextStyles.sans(
                size: 12,
                color: busy ? AppColors.textMuted : AppColors.errorText,
              ),
            ),
          ),
          if (!busy)
            GestureDetector(
              onTap: () => DevicePickerSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.errorText),
                ),
                child: Text(
                  'Connect',
                  style: AppTextStyles.sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.errorText,
                  ),
                ),
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
    (_ActiveView.flight, Icons.view_in_ar, '3D Flight'),
    (_ActiveView.club, Icons.sports_golf, 'Club'),
    (_ActiveView.table, Icons.table_rows, 'Table'),
    (_ActiveView.optimizer, Icons.tune, 'Optimizer'),
    (_ActiveView.camera, Icons.videocam, 'Camera'),
  ];

  /// Below this the labels start colliding, so the bar scrolls instead.
  static const _minItemWidth = 62.0;

  @override
  Widget build(BuildContext context) {
    final items = _items.where((item) => _viewAvailable(item.$1)).map((item) {
      final (v, icon, label) = item;
      return _NavItem(
        icon: icon,
        label: label,
        active: view == v,
        onTap: () => onChanged(v),
      );
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        color: AppColors.background,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fits = constraints.maxWidth >= _minItemWidth * items.length;
          if (fits) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: items,
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: items),
          );
        },
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
    final color = active ? context.accent : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
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

  /// Only rendered where there is room for it — see [supportsThirdSplitPane].
  final _ActivePaneView thirdPane;
  final int selectedShotIndex;
  final ValueChanged<_ActivePaneView> onLeftChanged;
  final ValueChanged<_ActivePaneView> onRightChanged;
  final ValueChanged<_ActivePaneView> onThirdChanged;
  final ValueChanged<int?> onShotSelected;

  const _ActiveSplitView({
    required this.shots,
    required this.allShots,
    required this.clubs,
    required this.filterClub,
    required this.highlightedShot,
    required this.leftPane,
    required this.rightPane,
    required this.thirdPane,
    required this.selectedShotIndex,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onThirdChanged,
    required this.onShotSelected,
  });

  Widget _paneContent(_ActivePaneView view, String paneId) {
    switch (view) {
      case _ActivePaneView.tiles:
        return TilesTab(
          shots: shots,
          selectedShot: highlightedShot,
          // Both panes can show tiles at once; Hero tags must stay unique.
          heroTag: 'tiles_fullscreen_$paneId',
        );
      case _ActivePaneView.dispersion:
        return DispersionTab(
          allShots: allShots,
          clubs: clubs,
          selectedClub: filterClub,
          highlightedShot: highlightedShot,
          onClubSelected: (_) {},
        );
      case _ActivePaneView.flight:
        return Flight3DTab(
          shots: shots,
          selectedShot: highlightedShot,
          clubs: clubs,
          // Half a screen is too small to spend a row on numbers the
          // neighbouring pane already shows.
          showStatBar: false,
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
      case _ActivePaneView.optimizer:
        return const ShotOptimizerPanel(showLeftBorder: false);
      case _ActivePaneView.camera:
        return const CameraTab();
    }
  }

  Widget _pane(
    _ActivePaneView view,
    ValueChanged<_ActivePaneView> onChanged,
    String paneId,
  ) {
    return Column(
      children: [
        _ActivePaneHeader(current: view, onChanged: onChanged),
        Expanded(child: _paneContent(view, paneId)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isTablet(context)) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final third = supportsThirdSplitPane(context, constraints.maxWidth);
          // Every pane is a flex-1 Expanded, so the panes split the row into
          // equal shares — halves, or exact thirds once the third is in.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _pane(leftPane, onLeftChanged, 'left')),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.border,
              ),
              Expanded(child: _pane(rightPane, onRightChanged, 'right')),
              if (third) ...[
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.border,
                ),
                Expanded(child: _pane(thirdPane, onThirdChanged, 'third')),
              ],
            ],
          );
        },
      );
    }
    return Column(
      children: [
        Expanded(child: _pane(leftPane, onLeftChanged, 'left')),
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: _pane(rightPane, onRightChanged, 'right')),
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
    (_ActivePaneView.flight, Icons.view_in_ar, '3D Flight'),
    (_ActivePaneView.club, Icons.sports_golf, 'Club'),
    (_ActivePaneView.table, Icons.table_rows, 'Table'),
    (_ActivePaneView.optimizer, Icons.tune, 'Optimizer'),
    (_ActivePaneView.camera, Icons.videocam, 'Camera'),
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
      child: Semantics(
        button: true,
        label: 'Change pane view. Current: $_label',
        child: GestureDetector(
          onTap: () => _showPicker(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
            ..._options.where((o) => _paneAvailable(o.$1)).map((opt) {
              final (view, icon, label) = opt;
              final isSel = view == current;
              return ListTile(
                leading: Icon(
                  icon,
                  size: 18,
                  color: isSel ? context.accent : AppColors.textMuted,
                ),
                title: Text(
                  label,
                  style: AppTextStyles.sans(
                    size: 14,
                    weight: isSel ? FontWeight.w600 : FontWeight.w400,
                    color: isSel ? context.accent : Colors.white,
                  ),
                ),
                trailing: isSel
                    ? Icon(Icons.check, color: context.accent, size: 18)
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
    final allShots = ref.watch(launchMonitorProvider.select((s) => s.shots));
    return TableTab(
      shots: shots,
      club: club,
      allShots: allShots,
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
              child: Tooltip(
                message: showShotList ? 'Hide shot list' : 'Show shot list',
                child: Semantics(
                  button: true,
                  selected: showShotList,
                  label: showShotList ? 'Hide shot list' : 'Show shot list',
                  child: GestureDetector(
                    onTap: onShotListToggle,
                    behavior: HitTestBehavior.opaque,
                    // 44px hit target around the 36px visual circle.
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: showShotList
                                  ? context.accentSubtle
                                  : AppColors.card,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: showShotList
                                    ? context.accent
                                    : AppColors.border2,
                              ),
                            ),
                            child: Icon(
                              Icons.menu,
                              size: 16,
                              color: showShotList
                                  ? context.accent
                                  : AppColors.textMuted,
                            ),
                          ),
                          if (shotCount > 0)
                            Positioned(
                              top: 0,
                              right: -2,
                              child: Container(
                                // Sizes to content so 3-digit counts never
                                // clip; a fixed 15px circle broke at 100+.
                                constraints: const BoxConstraints(minWidth: 15),
                                height: 15,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: context.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    shotCount > 999 ? '999+' : '$shotCount',
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
                ),
              ),
            ),
          // Centre: active club pill
          Semantics(
            button: true,
            label: activeClub == null
                ? 'Select club'
                : 'Active club: ${activeClub!.shortName}',
            child: GestureDetector(
              onTap: onClubTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
          ),
        ],
      ),
    );
  }
}

// ── Circle button ──────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  /// Announced by screen readers and shown as the tooltip. Icon-only
  /// controls are illegible to assistive tech without it.
  final String label;

  const _CircleButton({
    required this.onTap,
    required this.child,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          // 44px minimum hit target; the visible circle stays 32px.
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
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
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ball ready indicator ─────────────────────────────────────────────────────

/// Small circular indicator for ball state:
/// - grey  : detection not armed
/// - red   : armed, no ball detected
/// - amber : ball detected but not in a ready position
/// - green : ball detected and ready to hit
class _BallReadyIndicator extends StatelessWidget {
  final bool detecting;
  final bool ballDetected;
  final bool ballReady;

  const _BallReadyIndicator({
    required this.detecting,
    required this.ballDetected,
    required this.ballReady,
  });

  @override
  Widget build(BuildContext context) {
    final (color, tooltip) = !detecting
        ? (AppColors.textDimmed, 'Detection off')
        : ballReady
        ? (Colors.green, 'Ball ready')
        : ballDetected
        ? (Colors.orange, 'Ball detected, not ready')
        : (Colors.red, 'No ball detected');

    // State reads through shape as well as hue, so red-vs-green is never
    // the only signal: hollow ring = no ball, filled dot = ball detected,
    // filled dot with glow = ready to hit.
    final hollow = !detecting || (!ballDetected && !ballReady);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        // Sized to align with the 44px _CircleButton targets beside it.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border2),
              ),
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: hollow ? Colors.transparent : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                    boxShadow: detecting && ballReady
                        ? [
                            BoxShadow(
                              color: color.withAlpha(153),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Battery chip ───────────────────────────────────────────────────────────────

class _BatteryChip extends StatelessWidget {
  final int percent;

  const _BatteryChip({required this.percent});

  @override
  Widget build(BuildContext context) {
    final color = percent <= 15
        ? Colors.red
        : percent <= 30
        ? Colors.orange
        : AppColors.textMuted;
    final icon = percent <= 15
        ? Icons.battery_alert
        : percent >= 95
        ? Icons.battery_full
        : Icons.battery_std;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text('$percent%', style: AppTextStyles.sans(size: 11, color: color)),
      ],
    );
  }
}

// ── Step 1: confirm dialog ─────────────────────────────────────────────────────

/// Two-stage finish dialog. Stage one offers the save path, a leave-and-
/// resume-later path, and abandonment; choosing "Abandon Session" swaps to
/// an explicit red confirm naming exactly what is destroyed, so one stray
/// tap can never delete a session.
class _FinishConfirmDialog extends StatefulWidget {
  final int shotCount;
  final VoidCallback onFinish;
  final VoidCallback onLeave;
  final VoidCallback onAbandon;
  final VoidCallback onNevermind;

  const _FinishConfirmDialog({
    required this.shotCount,
    required this.onFinish,
    required this.onLeave,
    required this.onAbandon,
    required this.onNevermind,
  });

  @override
  State<_FinishConfirmDialog> createState() => _FinishConfirmDialogState();
}

class _FinishConfirmDialogState extends State<_FinishConfirmDialog> {
  bool _confirmingAbandon = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.shotCount;
    final shotsWord = count == 1 ? 'shot' : 'shots';
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _confirmingAbandon
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Abandon Session?',
                    style: AppTextStyles.sans(
                      size: 17,
                      weight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This deletes all $count $shotsWord. '
                    'It cannot be undone.',
                    style: AppTextStyles.sans(
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.errorBackground,
                        foregroundColor: AppColors.errorText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppColors.errorText),
                        ),
                      ),
                      onPressed: widget.onAbandon,
                      child: Text(
                        'Delete $count $shotsWord',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: AppColors.errorText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.onNevermind,
                      child: Text(
                        'Keep Session',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Finish Session?',
                    style: AppTextStyles.sans(
                      size: 17,
                      weight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$count $shotsWord recorded. Leaving keeps the session '
                    'active so you can return to it from the home screen.',
                    style: AppTextStyles.sans(
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.onFinish,
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
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.onLeave,
                      child: Text(
                        'Leave for Now',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: Colors.white,
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
                      onPressed: () =>
                          setState(() => _confirmingAbandon = true),
                      child: Text(
                        'Abandon Session',
                        style: AppTextStyles.sans(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onNevermind,
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
                        backgroundColor: context.accent,
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

/// Sort key for the active-club picker.
///
/// Groups (driver → mini → woods → hybrids → irons → wedges → putter), then
/// sorts within each group by the leading number / loft so 3w comes before
/// 5w, 4i before 7i, and 52° before 60°.
int _clubSortKey(Club c) {
  const int dr = 0;
  const int mini = 100;
  const int wood = 200;
  const int hybrid = 300;
  const int iron = 400;
  const int wedge = 500;
  const int putter = 999;

  if (c.id == 'dr') return dr;
  if (c.id == 'mdr') return mini;

  // Pull a numeric sub-key from the id (e.g. "3w" → 3, "52deg" → 52, "7i" → 7).
  final m = RegExp(r'(\d+)').firstMatch(c.id);
  final n = m == null ? 99 : int.tryParse(m.group(1)!) ?? 99;

  return switch (c.type) {
    ClubType.wood => wood + n,
    ClubType.miniDriver => mini,
    ClubType.hybrid => hybrid + n,
    ClubType.iron => iron + n,
    ClubType.wedge => wedge + _wedgeSubKey(c.id, n),
    ClubType.putter => putter,
  };
}

/// Named wedges (PW/GW/SW/LW) get fixed slots before any degree-marked wedges
/// so the picker reads pw → gw → sw → lw → 50° → 52° … in the wedge group.
int _wedgeSubKey(String id, int extractedNumber) {
  switch (id.toLowerCase()) {
    case 'pw':
      return 1;
    case 'gw':
      return 2;
    case 'sw':
      return 3;
    case 'lw':
      return 4;
    default:
      return 100 + extractedNumber;
  }
}

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
    final sorted = [...clubs]
      ..sort((a, b) => _clubSortKey(a).compareTo(_clubSortKey(b)));
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
            itemCount: sorted.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final club = sorted[i];
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
                    color: isSelected ? context.accent : Colors.white,
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
                    ? Icon(Icons.check, color: context.accent, size: 18)
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
