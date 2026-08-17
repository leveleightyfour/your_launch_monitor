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
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/session_finish_flow.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/shot_list_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/camera_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/club_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/table_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';
import 'package:omni_sniffer/shared/app_icons.dart';

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

/// The camera feed needs a capture backend, so it is offered only where one
/// exists — in the nav bar, in the pane picker, and when restoring a stored
/// pane choice (prefs travel between devices via the same account, so a
/// choice stored on a desktop can arrive on a platform without one).
bool _viewAvailable(_ActiveView v) =>
    v != _ActiveView.camera || isCameraCapturePlatform;

bool _paneAvailable(_ActivePaneView v) =>
    v != _ActivePaneView.camera || isCameraCapturePlatform;

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
  _ActivePaneView _splitFourth = _ActivePaneView.flight;
  SplitLayoutMode _splitLayout = SplitLayoutMode.auto;
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
    _splitFourth = _paneFromName(prefs.splitFourthPane, _ActivePaneView.flight);
    _splitLayout = SplitLayoutMode.values.firstWhere(
      (m) => m.name == prefs.splitLayout,
      orElse: () => SplitLayoutMode.auto,
    );
    // The legacy single-angle panes both map to the camera pane, so a stored
    // DTL-and-FO pair would come back as two camera panes; keep the first
    // and hand the rest back to data views.
    var cameraSeen = false;
    _ActivePaneView dedupe(_ActivePaneView v, _ActivePaneView fallback) {
      if (v != _ActivePaneView.camera) return v;
      if (cameraSeen) return fallback;
      cameraSeen = true;
      return v;
    }

    _splitLeft = dedupe(_splitLeft, _ActivePaneView.table);
    _splitRight = dedupe(_splitRight, _ActivePaneView.dispersion);
    _splitThird = dedupe(_splitThird, _ActivePaneView.optimizer);
    _splitFourth = dedupe(_splitFourth, _ActivePaneView.flight);
  }

  static _ActivePaneView _paneFromName(String name, _ActivePaneView fallback) {
    // Pane names stored before the camera pane learned to hold both angles
    // itself ('cameraDtl'/'cameraFo') fold into it.
    final effective = name == 'cameraDtl' || name == 'cameraFo'
        ? 'camera'
        : name;
    return _ActivePaneView.values.firstWhere(
      (v) => v.name == effective && _paneAvailable(v),
      orElse: () => fallback,
    );
  }

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

    // The moment a second camera is configured, make sure the split holds a
    // camera pane at all — it widens to half the view on its own. Only on
    // the transition: any pane choice made after that is the golfer's and
    // stays.
    ref.listen(
      unitPrefsProvider.select(
        (p) => p.cameraSlots.length > 1 && !p.cameraSlots[1].isEmpty,
      ),
      (previous, next) {
        if (previous == false && next == true) {
          final hasCamera =
              _splitLeft == _ActivePaneView.camera ||
              _splitRight == _ActivePaneView.camera ||
              _splitThird == _ActivePaneView.camera ||
              _splitFourth == _ActivePaneView.camera;
          if (!hasCamera) {
            setState(() => _splitThird = _ActivePaneView.camera);
            ref.read(unitPrefsProvider.notifier).setSplitPanes(third: 'camera');
          }
        }
      },
    );

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
        fourthPane: _splitFourth,
        layoutChoice: _splitLayout,
        // With both angles configured, the camera pane holds two feeds and
        // earns double width — half the view on an ultrawide strip.
        dualCamera: ref.watch(
          unitPrefsProvider.select(
            (p) => p.cameraSlots.length > 1 && !p.cameraSlots[1].isEmpty,
          ),
        ),
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
        onFourthChanged: (v) {
          setState(() => _splitFourth = v);
          ref.read(unitPrefsProvider.notifier).setSplitPanes(fourth: v.name);
        },
        onLayoutChanged: (m) {
          setState(() => _splitLayout = m);
          ref.read(unitPrefsProvider.notifier).setSplitLayout(m.name);
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
      builder: (dialogCtx) => FinishConfirmDialog(
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
      builder: (_) => SessionSummarySheet(
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
      builder: (_) => ClubPickerSheet(
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
              AppIcons.close,
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
                  AppIcons.batteryCharging,
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
                detecting ? AppIcons.locateFixed : AppIcons.locate,
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
              child: Icon(AppIcons.sessions, size: 14, color: context.accent),
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
              AppIcons.dot,
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
    (_ActiveView.split, AppIcons.columns, 'Split view'),
    (_ActiveView.tiles, AppIcons.tiles, 'Tiles'),
    (_ActiveView.dispersion, AppIcons.dispersion, 'Dispersion'),
    (_ActiveView.flight, AppIcons.flight3d, '3D Flight'),
    (_ActiveView.club, AppIcons.golf, 'Club'),
    (_ActiveView.table, AppIcons.table, 'Table'),
    (_ActiveView.optimizer, AppIcons.optimizer, 'Optimizer'),
    (_ActiveView.camera, AppIcons.video, 'Camera'),
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

  /// Only rendered where there is room for it — see [resolveSplitLayout].
  final _ActivePaneView thirdPane;

  /// Only rendered by the 2×2 grid.
  final _ActivePaneView fourthPane;

  /// The golfer's layout pick; [resolveSplitLayout] folds it to what the
  /// window can actually hold.
  final SplitLayoutMode layoutChoice;

  /// Both camera slots are configured, so the camera pane holds two feeds
  /// and earns double the width of a data pane.
  final bool dualCamera;
  final int selectedShotIndex;
  final ValueChanged<_ActivePaneView> onLeftChanged;
  final ValueChanged<_ActivePaneView> onRightChanged;
  final ValueChanged<_ActivePaneView> onThirdChanged;
  final ValueChanged<_ActivePaneView> onFourthChanged;
  final ValueChanged<SplitLayoutMode> onLayoutChanged;
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
    required this.fourthPane,
    required this.layoutChoice,
    required this.dualCamera,
    required this.selectedShotIndex,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onThirdChanged,
    required this.onFourthChanged,
    required this.onLayoutChanged,
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

  static const _divider = VerticalDivider(
    width: 1,
    thickness: 1,
    color: AppColors.border,
  );
  static const _rowDivider = Divider(height: 1, color: AppColors.border);

  Widget _twoAcross() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _pane(leftPane, onLeftChanged, 'left')),
        _divider,
        Expanded(child: _pane(rightPane, onRightChanged, 'right')),
      ],
    );
  }

  Widget _threeStrip(BuildContext context, BoxConstraints constraints) {
    final panes = [
      (leftPane, onLeftChanged, 'left'),
      (rightPane, onRightChanged, 'right'),
      (thirdPane, onThirdChanged, 'third'),
    ];

    // With both angles configured, the camera pane holds two feeds and
    // earns double width: on an ultrawide strip that is half the view
    // — a quarter per angle — with the data panes on the other half.
    // On an ordinary desktop tall enough to stack, the camera takes a
    // full-width row of its own instead, keeping both feeds large.
    final cameraIdx = dualCamera
        ? panes.indexWhere((p) => p.$1 == _ActivePaneView.camera)
        : -1;

    if (cameraIdx >= 0 &&
        dualCameraPrefersOwnRow(
          context,
          constraints.maxWidth,
          constraints.maxHeight,
        )) {
      final camera = panes[cameraIdx];
      final others = [
        for (var i = 0; i < panes.length; i++)
          if (i != cameraIdx) panes[i],
      ];
      final cameraRow = Expanded(child: _pane(camera.$1, camera.$2, camera.$3));
      final dataRow = Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _pane(others[0].$1, others[0].$2, others[0].$3)),
            _divider,
            Expanded(child: _pane(others[1].$1, others[1].$2, others[1].$3)),
          ],
        ),
      );
      // The camera row keeps its configured position: chosen as the
      // left pane it leads, anywhere else it sits below the data.
      return Column(
        children: cameraIdx == 0
            ? [cameraRow, _rowDivider, dataRow]
            : [dataRow, _rowDivider, cameraRow],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < panes.length; i++) ...[
          if (i > 0) _divider,
          Expanded(
            flex: i == cameraIdx ? 2 : 1,
            child: _pane(panes[i].$1, panes[i].$2, panes[i].$3),
          ),
        ],
      ],
    );
  }

  Widget _grid() {
    final panes = [
      (leftPane, onLeftChanged, 'left'),
      (rightPane, onRightChanged, 'right'),
      (thirdPane, onThirdChanged, 'third'),
      (fourthPane, onFourthChanged, 'fourth'),
    ];

    // A two-angle camera pane takes a full-height column instead of one
    // cell: rotated portrait swing video is tall, and half-width ×
    // full-height splits into two stacked angles the shape of phone
    // screens. The two highest-priority data panes stack in the other
    // column; the third data choice returns when the camera moves out.
    final cameraIdx = dualCamera
        ? panes.indexWhere((p) => p.$1 == _ActivePaneView.camera)
        : -1;

    if (cameraIdx >= 0) {
      final camera = panes[cameraIdx];
      final others = [
        for (var i = 0; i < panes.length; i++)
          if (i != cameraIdx) panes[i],
      ];
      final cameraCol = Expanded(child: _pane(camera.$1, camera.$2, camera.$3));
      final dataCol = Expanded(
        child: Column(
          children: [
            Expanded(child: _pane(others[0].$1, others[0].$2, others[0].$3)),
            _rowDivider,
            Expanded(child: _pane(others[1].$1, others[1].$2, others[1].$3)),
          ],
        ),
      );
      // The camera column keeps its configured position, as in the strip:
      // chosen as the left pane it leads, anywhere else it sits right.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cameraIdx == 0
            ? [cameraCol, _divider, dataCol]
            : [dataCol, _divider, cameraCol],
      );
    }

    Widget cell((_ActivePaneView, ValueChanged<_ActivePaneView>, String) p) =>
        Expanded(child: _pane(p.$1, p.$2, p.$3));
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cell(panes[0]), _divider, cell(panes[1])],
          ),
        ),
        _rowDivider,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cell(panes[2]), _divider, cell(panes[3])],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isTablet(context)) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final mode = resolveSplitLayout(
            layoutChoice,
            context,
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final body = switch (mode) {
            SplitLayoutMode.two => _twoAcross(),
            SplitLayoutMode.three => _threeStrip(context, constraints),
            SplitLayoutMode.grid => _grid(),
            // resolveSplitLayout never returns auto.
            SplitLayoutMode.auto => _twoAcross(),
          };
          // The toggle floats over the pane-header strip's right end, which
          // the left-aligned header content leaves empty.
          return Stack(
            children: [
              Positioned.fill(child: body),
              Positioned(
                top: 7,
                right: 8,
                child: _SplitLayoutToggle(
                  choice: layoutChoice,
                  onChanged: onLayoutChanged,
                  // Computed from the same tests the resolver applies, so
                  // every option on offer is one that will be honoured.
                  showThree: supportsThirdSplitPane(
                    context,
                    constraints.maxWidth,
                  ),
                  showGrid: supportsGridSplitPanes(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                ),
              ),
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

/// Compact Auto / 2 / 3 / 2×2 switcher floated over the pane headers.
///
/// An explicit pick is remembered across sessions; Auto hands the decision
/// to [resolveSplitLayout]. A pick the window can't honour folds down to
/// fewer panes rather than greying out — the label states intent, the
/// resolver keeps every pane legible.
class _SplitLayoutToggle extends StatelessWidget {
  final SplitLayoutMode choice;
  final ValueChanged<SplitLayoutMode> onChanged;

  /// Whether the room exists for these layouts right now. An option the
  /// resolver would silently fold back to two panes is not offered at all
  /// — a chip that does nothing when tapped reads as broken.
  final bool showThree;
  final bool showGrid;

  const _SplitLayoutToggle({
    required this.choice,
    required this.onChanged,
    required this.showThree,
    required this.showGrid,
  });

  static const _options = [
    (SplitLayoutMode.auto, 'Auto', 'Fit the layout to the window'),
    (SplitLayoutMode.two, '2', 'Two panes'),
    (SplitLayoutMode.three, '3', 'Three panes across'),
    (SplitLayoutMode.grid, '2×2', 'Four panes in a grid'),
  ];

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final option in _options)
        if ((option.$1 != SplitLayoutMode.three || showThree) &&
            (option.$1 != SplitLayoutMode.grid || showGrid))
          option,
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, label, tip) in options)
            Tooltip(
              message: tip,
              child: GestureDetector(
                onTap: () => onChanged(mode),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: mode == choice
                      ? BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: Text(
                    label,
                    style: AppTextStyles.sans(
                      size: 11,
                      weight: mode == choice
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: mode == choice
                          ? context.accent
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pane header (dropdown to switch pane view) ─────────────────────────────────

class _ActivePaneHeader extends StatelessWidget {
  final _ActivePaneView current;
  final ValueChanged<_ActivePaneView> onChanged;

  const _ActivePaneHeader({required this.current, required this.onChanged});

  static const _options = [
    (_ActivePaneView.tiles, AppIcons.tiles, 'Tiles'),
    (_ActivePaneView.dispersion, AppIcons.dispersion, 'Dispersion'),
    (_ActivePaneView.flight, AppIcons.flight3d, '3D Flight'),
    (_ActivePaneView.club, AppIcons.golf, 'Club'),
    (_ActivePaneView.table, AppIcons.table, 'Table'),
    (_ActivePaneView.optimizer, AppIcons.optimizer, 'Optimizer'),
    // One entry for any number of angles: the camera pane carries every
    // configured feed itself and widens when a second one arrives.
    (_ActivePaneView.camera, AppIcons.video, 'Camera'),
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
                  AppIcons.chevronDown,
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
                    ? Icon(AppIcons.check, color: context.accent, size: 18)
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
                              AppIcons.menu,
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
                        AppIcons.golf,
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
                      AppIcons.chevronDown,
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
        ? AppIcons.batteryAlert
        : percent >= 95
        ? AppIcons.batteryFull
        : AppIcons.battery;
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
