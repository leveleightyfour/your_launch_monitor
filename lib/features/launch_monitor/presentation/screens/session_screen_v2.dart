import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/sessions_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/session_screen.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/device_picker_sheet.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/error_banner.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/session_finish_flow.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/camera_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/club_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/dispersion_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/tabs/tiles_tab.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';
import 'package:omni_sniffer/shared/app_icons.dart';

// The "Rethink" session screen, ported from the updated HTML design
// (Session Screen Rethink): one full-bleed stage the golfer flips between
// FIELD / FLIGHT / CLUB / TILES / SWING, a right rail that always answers
// "what did that shot do and why" — verdict, carry and offline heroes, and
// the metric tiles with the shot's place in its own range — and a shot
// ribbon along the bottom for scrubbing back through the bucket.
//
// It is a second front door onto the same session machinery as the classic
// screen: same providers, same stages (the existing tabs), same finish flow.
// The Profile screen's "Session screen" toggle decides which one
// /session/new opens.

// ── Route gate ────────────────────────────────────────────────────────────────

/// Opens whichever session screen the Profile toggle selects. Watching the
/// pref here means flipping the toggle changes the very next session without
/// a restart; an open session keeps the screen it started on.
class SessionScreenGate extends ConsumerWidget {
  final String? initialName;

  const SessionScreenGate({super.key, this.initialName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(unitPrefsProvider.select((p) => p.sessionLayout));
    return layout == SessionScreenLayout.rethink
        ? SessionScreenV2(initialName: initialName)
        : SessionScreen(initialName: initialName);
  }
}

// ── Design tokens ─────────────────────────────────────────────────────────────

// The rethink palette is flatter and darker than the app chrome: near-black
// grounds with hairline separations, so the stage and the numbers carry all
// the light. Values match the HTML design.
const _bg = Color(0xFF08090B);
const _panel = Color(0xFF0B0C0F);
const _stageBg = Color(0xFF070809);
const _hairline = Color(0x12FFFFFF); // white 7%
const _edge = Color(0x24FFFFFF); // white 14%, chip borders

const _ink30 = Color(0x4DFFFFFF);
const _ink42 = Color(0x6BFFFFFF);
const _ink55 = Color(0x8CFFFFFF);

/// IBM Plex Mono — the design's eyebrow / label voice.
TextStyle _mono(
  double size, {
  Color color = _ink55,
  double tracking = 1.2,
  FontWeight weight = FontWeight.w400,
}) => GoogleFonts.ibmPlexMono(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: tracking,
);

/// Barlow Condensed — the design's hero numerals. Tabular figures so live
/// values don't wobble the layout as digits roll.
TextStyle _cond(
  double size, {
  FontWeight weight = FontWeight.w700,
  Color color = Colors.white,
}) => GoogleFonts.barlowCondensed(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 0.95,
).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

// ── Stages ────────────────────────────────────────────────────────────────────

enum _Stage {
  field('FIELD', 'LANDING FIELD'),
  flight('FLIGHT', 'FLIGHT'),
  club('CLUB', 'CLUB DELIVERY'),
  tiles('TILES', 'TILES'),
  swing('SWING', 'SWING');

  const _Stage(this.chip, this.title);

  final String chip;
  final String title;

  /// The swing stage is the camera pipeline, so it is only offered where a
  /// capture backend exists — same rule as the classic nav bar.
  bool get available => this != _Stage.swing || isCameraCapturePlatform;
}

// ── Main screen ───────────────────────────────────────────────────────────────

class SessionScreenV2 extends ConsumerStatefulWidget {
  final String? initialName;

  const SessionScreenV2({super.key, this.initialName});

  @override
  ConsumerState<SessionScreenV2> createState() => _SessionScreenV2State();
}

class _SessionScreenV2State extends ConsumerState<SessionScreenV2> {
  _Stage _stage = _Stage.field;

  /// Ticks the SHOTS cell's session clock. A minute of drift is invisible at
  /// this resolution; 30s keeps the readout honest around the minute marks.
  Timer? _clock;

  String? get _sessionName =>
      widget.initialName ?? ref.read(launchMonitorProvider.notifier).draftName;

  @override
  void initState() {
    super.initState();
    // Stash the chosen name so it survives leave-and-resume, exactly as the
    // classic screen does (the resume route carries no initialName).
    if (widget.initialName != null) {
      ref.read(launchMonitorProvider.notifier).draftName = widget.initialName;
    }
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
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
    final activeClub = ref.watch(activeClubProvider);
    final filterClub = ref.watch(selectedClubProvider);
    final clubs = ref.watch(clubsProvider);
    final prefs = ref.watch(unitPrefsProvider);

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

    final stage = _stage.available ? _stage : _Stage.field;
    final Widget stageContent = switch (stage) {
      _Stage.field => DispersionTab(
        allShots: allShots,
        clubs: clubs,
        selectedClub: filterClub,
        highlightedShot: selectedShot,
        onClubSelected: (_) {},
      ),
      _Stage.flight => Flight3DTab(
        shots: shotsForClub,
        selectedShot: selectedInClub >= 0 ? selectedShot : null,
        clubs: clubs,
      ),
      _Stage.club => ClubTab(
        shots: shotsForClub,
        clubs: clubs,
        selectedShot: selectedInClub >= 0 ? selectedShot : null,
      ),
      _Stage.tiles => TilesTab(
        shots: shotsForClub,
        selectedShot: selectedShot,
        heroTag: 'rethink_tiles',
      ),
      _Stage.swing => const CameraTab(),
    };

    final selectedClubEntity = selectedShot == null
        ? null
        : clubs.where((c) => c.id == selectedShot.clubId).firstOrNull;
    final peers = selectedShot == null
        ? const <ShotData>[]
        : allShots.where((s) => s.clubId == selectedShot.clubId).toList();

    // The system back gesture must never skip the finish flow: with shots on
    // the board it routes through the same confirm dialog as the X button.
    return PopScope(
      canPop: allShots.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
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
        backgroundColor: _bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The rail earns its column only when the stage keeps a
              // workable width beside it; below that the rail's story
              // compresses into a strip above the ribbon.
              final wide = constraints.maxWidth >= 1000;

              return Column(
                children: [
                  _TopBar(
                    name: _sessionName,
                    status: status,
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
                    onSimulateShot: prefs.showTestShotButton
                        ? () => notifier.simulateShot()
                        : null,
                    onClose: () => _confirmFinish(context),
                  ),
                  if (status != LaunchMonitorStatus.connected)
                    _ConnBanner(status: status),
                  if (error != null) ErrorBanner(message: error),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ColoredBox(
                            color: _stageBg,
                            child: Column(
                              children: [
                                _StageHeader(
                                  stage: stage,
                                  onChanged: (s) => setState(() => _stage = s),
                                ),
                                Expanded(child: stageContent),
                              ],
                            ),
                          ),
                        ),
                        if (wide)
                          SizedBox(
                            width: 380,
                            child: _Rail(
                              shot: selectedShot,
                              shotIndex: safeIdx,
                              shotCount: allShots.length,
                              peers: peers,
                              club: selectedClubEntity,
                              prefs: prefs,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!wide)
                    _CompactSummary(
                      shot: selectedShot,
                      shotIndex: safeIdx,
                      shotCount: allShots.length,
                      peers: peers,
                      club: selectedClubEntity,
                      prefs: prefs,
                    ),
                  _ShotRibbon(
                    allShots: allShots,
                    clubs: clubs,
                    selectedIndex: safeIdx,
                    prefs: prefs,
                    activeClub: activeClub,
                    startedAt: notifier.draftCreatedAt,
                    onShotTap: (i) =>
                        ref.read(selectedShotIndexProvider.notifier).state = i,
                    onClubTap: () =>
                        _showClubPicker(context, clubs, activeClub),
                  ),
                ],
              );
            },
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

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String? name;
  final LaunchMonitorStatus status;
  final int? batteryPercent;
  final bool capacitorReady;
  final bool detecting;
  final bool ballDetected;
  final bool ballReady;
  final VoidCallback? onToggleArm;
  final VoidCallback? onSimulateShot;
  final VoidCallback onClose;

  const _TopBar({
    this.name,
    required this.status,
    this.batteryPercent,
    required this.capacitorReady,
    required this.detecting,
    required this.ballDetected,
    required this.ballReady,
    this.onToggleArm,
    this.onSimulateShot,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final connected = status == LaunchMonitorStatus.connected;

    // Ball state reads through both hue and fill, as the classic indicator
    // does: hollow ring = nothing on the mat, filled = detected, glowing =
    // ready to hit.
    final (ballColor, ballLabel) = !detecting
        ? (AppColors.textDimmed, 'Detection off')
        : ballReady
        ? (Colors.green, 'Ball ready')
        : ballDetected
        ? (Colors.orange, 'Ball detected, not ready')
        : (Colors.red, 'No ball detected');

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: accent.withAlpha(178), blurRadius: 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'RECORDING · ${(name ?? 'RANGE SESSION').toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono(11, tracking: 1.5),
            ),
          ),
          const Spacer(),
          if (connected) ...[
            if (batteryPercent != null) ...[
              Icon(
                batteryPercent! <= 15
                    ? AppIcons.batteryAlert
                    : AppIcons.battery,
                size: 13,
                color: batteryPercent! <= 15 ? Colors.red : _ink42,
              ),
              const SizedBox(width: 4),
              Text('$batteryPercent%', style: _mono(11, color: _ink42)),
              const _BarDivider(),
            ],
            if (!capacitorReady) ...[
              const Icon(
                AppIcons.batteryCharging,
                size: 13,
                color: Colors.orange,
              ),
              const _BarDivider(),
            ],
            _MonoChip(
              label: detecting ? 'ARMED' : 'ARM',
              active: detecting,
              onTap: onToggleArm,
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: ballLabel,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: !detecting || (!ballDetected && !ballReady)
                      ? Colors.transparent
                      : ballColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: ballColor, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ] else
            _MonoChip(
              label: switch (status) {
                LaunchMonitorStatus.connecting => 'CONNECTING…',
                LaunchMonitorStatus.scanning => 'SCANNING…',
                _ => 'CONNECT',
              },
              active: false,
              onTap: status == LaunchMonitorStatus.disconnected
                  ? () => DevicePickerSheet.show(context)
                  : null,
            ),
          if (onSimulateShot != null) ...[
            const SizedBox(width: 8),
            _MonoChip(
              label: '+ TEST SHOT',
              active: true,
              onTap: onSimulateShot,
            ),
          ],
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: 'Finish session',
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(AppIcons.close, size: 17, color: _ink42),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 12,
    color: _edge,
    margin: const EdgeInsets.symmetric(horizontal: 10),
  );
}

/// The design's bordered mono chip — the one interactive control style the
/// whole screen uses.
class _MonoChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _MonoChip({required this.label, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: active ? accent.withAlpha(115) : _edge),
            color: active ? accent.withAlpha(26) : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            label,
            style: _mono(10, color: active ? accent : _ink55, tracking: 1.3),
          ),
        ),
      ),
    );
  }
}

// ── Connection banner ─────────────────────────────────────────────────────────

/// A mid-bucket drop must never be silent: without a connection, swings
/// simply don't register. Same message as the classic banner, restated in
/// the rethink's mono voice.
class _ConnBanner extends StatelessWidget {
  final LaunchMonitorStatus status;

  const _ConnBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final busy =
        status == LaunchMonitorStatus.connecting ||
        status == LaunchMonitorStatus.scanning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textMuted,
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.errorText,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy
                  ? (status == LaunchMonitorStatus.scanning
                        ? 'SCANNING FOR DEVICES…'
                        : 'CONNECTING…')
                  : "DEVICE NOT CONNECTED — SWINGS WON'T BE CAPTURED",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono(
                10,
                color: busy ? _ink42 : AppColors.errorText,
                tracking: 1.3,
              ),
            ),
          ),
          if (!busy)
            GestureDetector(
              onTap: () => DevicePickerSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.errorText),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'CONNECT',
                  style: _mono(10, color: AppColors.errorText, tracking: 1.3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Stage header ──────────────────────────────────────────────────────────────

/// Stage title on the left, the FIELD/FLIGHT/CLUB/TILES/SWING switch on the
/// right. A bar rather than the design's floating overlay: the existing tabs
/// carry their own in-canvas controls, and an overlay would sit on top of
/// them.
class _StageHeader extends StatelessWidget {
  final _Stage stage;
  final ValueChanged<_Stage> onChanged;

  const _StageHeader({required this.stage, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stage.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono(10, color: _ink30, tracking: 1.6),
            ),
          ),
          // On a phone the five chips outgrow the bar; they scroll from the
          // right edge instead of overflowing (reverse keeps the active end
          // anchored where the design puts it).
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Container(
                decoration: BoxDecoration(
                  color: _edge,
                  border: Border.all(color: _edge),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in _Stage.values.where((s) => s.available))
                      Padding(
                        padding: EdgeInsets.only(
                          left: s == _Stage.field ? 0 : 1,
                        ),
                        child: Semantics(
                          button: true,
                          selected: s == stage,
                          label: s.title,
                          child: GestureDetector(
                            onTap: () => onChanged(s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 7,
                              ),
                              color: s == stage ? accent.withAlpha(36) : _panel,
                              child: Text(
                                s.chip,
                                style: _mono(
                                  10,
                                  color: s == stage ? accent : _ink42,
                                  tracking: 1.5,
                                ),
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
        ],
      ),
    );
  }
}

// ── Verdict ───────────────────────────────────────────────────────────────────

class _Verdict {
  final String text;
  final String cost;
  final Color color;

  const _Verdict(this.text, this.cost, this.color);
}

/// Plain language, one cause, one cost — the design's verdict logic on real
/// shot data. Candidate diagnoses are ranked by the yards they actually cost
/// this shot; a cause only earns the verdict if the cost survives rounding.
_Verdict _verdictFor(
  ShotData shot,
  List<ShotData> peers,
  Club? club,
  UnitPrefs prefs,
  Color accent,
) {
  final clubName = club?.shortName.toUpperCase() ?? 'CLUB';
  final unit = prefs.distLabel;
  final lat = shot.lateralOffset;
  final latDisp = prefs.dist(lat.abs());
  final sideWord = lat >= 0 ? 'right' : 'left';

  // With no window built yet there is nothing to judge against — the shot
  // itself becomes the window.
  if (peers.length < 2) {
    return _Verdict(
      'Launch ${shot.launchAngle.toStringAsFixed(1)}° and '
          '${(shot.spinRate / 10).round() * 10} rpm on the board. More $clubName '
          'shots will build the window.',
      'Carry ${prefs.dist(shot.carry).toStringAsFixed(1)} $unit · '
          '${latDisp.toStringAsFixed(1)} $unit $sideWord',
      accent,
    );
  }

  double avgOf(double Function(ShotData) f) =>
      peers.map(f).reduce((a, b) => a + b) / peers.length;
  final avgCarry = avgOf((s) => s.carry);
  final dCarry = shot.carry - avgCarry;
  final mean = avgCarry;
  final sigma = math.sqrt(
    peers
            .map((s) => (s.carry - mean) * (s.carry - mean))
            .reduce((a, b) => a + b) /
        (peers.length - 1),
  );
  final bestSmash = peers.map((s) => s.smashFactor).reduce(math.max);
  final face = shot.faceAngle;

  // (costYds, text, note, eligible)
  final candidates =
      <(double, String, String, bool)>[
        (
          lat.abs() * 0.6,
          'Face ${face?.abs().toStringAsFixed(1)}° ${(face ?? 0) > 0 ? 'open' : 'closed'} '
              'at impact — the ball started ${(face ?? 0) > 0 ? 'right' : 'left'} '
              'and never came back.',
          '${latDisp.toStringAsFixed(1)} $unit $sideWord of target',
          face != null &&
              face.abs() > 1.6 &&
              lat.abs() > 3 &&
              face.sign == lat.sign,
        ),
        (
          math.max(0.0, bestSmash - shot.smashFactor) * shot.clubSpeed,
          'Strike is off centre — smash ${shot.smashFactor.toStringAsFixed(2)} '
              'against your $clubName best of ${bestSmash.toStringAsFixed(2)}.',
          'centre-face contact',
          shot.smashFactor < bestSmash - 0.05,
        ),
        (
          math.max(0.0, -dCarry),
          'Carry is short of your $clubName window — '
              '${prefs.dist(shot.carry).toStringAsFixed(1)} against an average of '
              '${prefs.dist(avgCarry).toStringAsFixed(1)}.',
          'distance control',
          dCarry < -math.max(sigma, 4),
        ),
      ].where((c) => c.$4 && prefs.dist(c.$1).round() >= 1).toList()..sort(
        (a, b) => b.$1.compareTo(a.$1),
      );

  if (candidates.isNotEmpty) {
    final top = candidates.first;
    return _Verdict(
      top.$2,
      'Costs about ${prefs.dist(top.$1).round()} $unit · ${top.$3}',
      top.$1 > 9 ? AppColors.severityCritical : AppColors.severityWarning,
    );
  }

  return _Verdict(
    'Clean strike. Launch ${shot.launchAngle.toStringAsFixed(1)}° and '
        '${(shot.spinRate / 10).round() * 10} rpm sit inside your $clubName '
        'window.',
    'Carry ${dCarry >= 0 ? '+' : ''}${prefs.dist(dCarry).toStringAsFixed(1)} '
        '$unit vs your $clubName average · '
        '${latDisp.toStringAsFixed(1)} $unit $sideWord',
    accent,
  );
}

// ── Right rail ────────────────────────────────────────────────────────────────

class _Rail extends ConsumerWidget {
  final ShotData? shot;
  final int shotIndex;
  final int shotCount;
  final List<ShotData> peers;
  final Club? club;
  final UnitPrefs prefs;

  const _Rail({
    required this.shot,
    required this.shotIndex,
    required this.shotCount,
    required this.peers,
    required this.club,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.accent;
    final metrics = ref.watch(selectedTilesProvider);
    final current = shot;

    return Container(
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(left: BorderSide(color: _hairline)),
      ),
      child: current == null
          ? Center(
              child: Text(
                'WAITING FOR THE FIRST SHOT',
                style: _mono(10, color: _ink30, tracking: 1.6),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VerdictBlock(
                  shot: current,
                  shotIndex: shotIndex,
                  shotCount: shotCount,
                  peers: peers,
                  club: club,
                  prefs: prefs,
                ),
                _HeroRow(shot: current, peers: peers, club: club, prefs: prefs),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                  child: Row(
                    children: [
                      Text(
                        'TILES · ${metrics.length} ACTIVE',
                        style: _mono(9.5, color: _ink30, tracking: 1.5),
                      ),
                      const Spacer(),
                      _MonoChip(
                        label: 'CUSTOMIZE',
                        active: false,
                        onTap: () => showTilesCustomizeSheet(context, ref),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: metrics.isEmpty
                      ? Center(
                          child: Text(
                            'NO TILES SELECTED',
                            style: _mono(10, color: _ink30, tracking: 1.6),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.only(top: 1),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisExtent: 118,
                                crossAxisSpacing: 1,
                                mainAxisSpacing: 1,
                              ),
                          itemCount: metrics.length,
                          itemBuilder: (context, i) => _MiniTile(
                            metric: metrics[i],
                            shot: current,
                            peers: peers,
                            prefs: prefs,
                            accent: accent,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _VerdictBlock extends StatelessWidget {
  final ShotData shot;
  final int shotIndex;
  final int shotCount;
  final List<ShotData> peers;
  final Club? club;
  final UnitPrefs prefs;

  const _VerdictBlock({
    required this.shot,
    required this.shotIndex,
    required this.shotCount,
    required this.peers,
    required this.club,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final verdict = _verdictFor(shot, peers, club, prefs, context.accent);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: club?.color ?? AppColors.textDimmed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _shotEyebrow(shotIndex, shotCount, club),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(11, tracking: 1.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            verdict.text,
            style: AppTextStyles.sans(
              size: 17,
              weight: FontWeight.w500,
            ).copyWith(height: 1.32),
          ),
          const SizedBox(height: 8),
          Text(
            verdict.cost,
            style: _mono(11, color: verdict.color, tracking: 0.4),
          ),
        ],
      ),
    );
  }
}

/// "SHOT 07 · 7 IRON" — [shotIndex] indexes the newest-first list, but the
/// golfer counts shots in the order they were hit.
String _shotEyebrow(int shotIndex, int shotCount, Club? club) {
  final ordinal = shotCount - shotIndex;
  return 'SHOT ${ordinal.toString().padLeft(2, '0')} · '
      '${(club?.shortName ?? 'UNKNOWN').toUpperCase()}';
}

class _HeroRow extends StatelessWidget {
  final ShotData shot;
  final List<ShotData> peers;
  final Club? club;
  final UnitPrefs prefs;

  const _HeroRow({
    required this.shot,
    required this.peers,
    required this.club,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final carry = prefs.dist(shot.carry);
    final lat = shot.lateralOffset;
    final latDisp = prefs.dist(lat.abs());
    final offlineWarn = latDisp > prefs.dist(8);

    final avgCarry = peers.isEmpty
        ? null
        : prefs.dist(
            peers.map((s) => s.carry).reduce((a, b) => a + b) / peers.length,
          );
    final dCarry = avgCarry == null ? null : carry - avgCarry;
    final deltaColor = dCarry == null || dCarry.abs() < 4
        ? _ink42
        : dCarry < 0
        ? AppColors.severityWarning
        : accent;

    // Offline bar scale: the shot's own miss against a fixed ±25yd window,
    // clamped — far enough that a fairway miss reads proportionally and a
    // wild one pins the bar rather than rescaling everything else.
    final maxLat = math.max(25.0, latDisp);
    final frac = (latDisp / maxLat).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CARRY', style: _mono(10, color: _ink42, tracking: 1.8)),
                // Scale-down keeps a four-digit carry (metres × long drive)
                // from overflowing the rail instead of throwing.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(carry.toStringAsFixed(1), style: _cond(76)),
                      const SizedBox(width: 6),
                      Text(
                        prefs.distLabel,
                        style: _mono(11, color: _ink42, tracking: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dCarry == null
                      ? 'FIRST OF THE SESSION'
                      : '${dCarry >= 0 ? '+' : ''}${dCarry.toStringAsFixed(1)} '
                            'vs ${(club?.shortName ?? '').toUpperCase()} avg '
                            '${avgCarry!.toStringAsFixed(1)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(10, color: deltaColor, tracking: 0.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OFFLINE',
                    style: _mono(10, color: _ink42, tracking: 1.8),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        latDisp.toStringAsFixed(1),
                        style: _cond(
                          44,
                          color: offlineWarn
                              ? AppColors.severityWarning
                              : Colors.white,
                        ),
                      ),
                      Text(
                        lat >= 0 ? 'R' : 'L',
                        style: _cond(
                          22,
                          color: offlineWarn
                              ? AppColors.severityWarning
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        prefs.distLabel,
                        style: _mono(11, color: _ink42, tracking: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 4,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final half = c.maxWidth / 2;
                        final w = half * frac;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned.fill(
                              child: ColoredBox(color: _hairline),
                            ),
                            Positioned(
                              left: lat >= 0 ? half : half - w,
                              width: w,
                              top: 0,
                              bottom: 0,
                              child: ColoredBox(
                                color: offlineWarn
                                    ? AppColors.severityWarning
                                    : context.accent,
                              ),
                            ),
                            Positioned(
                              left: half - 0.5,
                              width: 1,
                              top: -3,
                              bottom: -3,
                              child: const ColoredBox(color: _ink30),
                            ),
                          ],
                        );
                      },
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

// ── Metric mini tile ──────────────────────────────────────────────────────────

/// One rail tile: the metric's value for the selected shot, every peer shot
/// as a dot across the club's own min–max range, and the selected shot's
/// place in it as the bright bar. Uses the same metric vocabulary and
/// formatting as the Tiles tab.
class _MiniTile extends StatelessWidget {
  final TileMetric metric;
  final ShotData shot;
  final List<ShotData> peers;
  final UnitPrefs prefs;
  final Color accent;

  const _MiniTile({
    required this.metric,
    required this.shot,
    required this.peers,
    required this.prefs,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final (number, suffix) = splitValueSuffix(metricValue(metric, shot, prefs));
    final vals = peers
        .map((s) => metricRaw(metric, s, prefs))
        .whereType<double>()
        .toList();
    final v = metricRaw(metric, shot, prefs);
    final lo = vals.isEmpty ? 0.0 : vals.reduce(math.min);
    final hi = vals.isEmpty ? 0.0 : vals.reduce(math.max);
    final span = hi - lo;
    double pos(double x) => span > 0 ? ((x - lo) / span).clamp(0.0, 1.0) : 0.5;

    final dec = metric == TileMetric.spinRate
        ? 0
        : metric == TileMetric.smashFactor
        ? 2
        : 1;
    String fmt(double x) => x.toStringAsFixed(dec);

    return Container(
      color: _panel,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _mono(9, color: _ink42, tracking: 1.1),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  number,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: _cond(32, weight: FontWeight.w600),
                ),
              ),
              if (suffix.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(suffix, style: _cond(16, weight: FontWeight.w600)),
              ],
              const SizedBox(width: 4),
              Text(
                tileUnit(metric, prefs),
                style: _mono(9, color: _ink30, tracking: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 18,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(height: 1, color: _hairline),
                ),
                for (final x in vals)
                  Align(
                    alignment: FractionalOffset(pos(x), 0.5),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: _ink30,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (v != null)
                  Align(
                    alignment: FractionalOffset(pos(v), 0.5),
                    child: Container(
                      width: 2,
                      height: 14,
                      decoration: BoxDecoration(
                        color: accent,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withAlpha(128),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            vals.isEmpty ? '—' : '${fmt(lo)}–${fmt(hi)}',
            style: _mono(8.5, color: _ink30, tracking: 0.6),
          ),
        ],
      ),
    );
  }
}

// ── Compact summary (narrow layouts) ──────────────────────────────────────────

/// The rail's story at phone width: eyebrow + verdict on the left, carry and
/// offline numbers on the right.
class _CompactSummary extends StatelessWidget {
  final ShotData? shot;
  final int shotIndex;
  final int shotCount;
  final List<ShotData> peers;
  final Club? club;
  final UnitPrefs prefs;

  const _CompactSummary({
    required this.shot,
    required this.shotIndex,
    required this.shotCount,
    required this.peers,
    required this.club,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final current = shot;
    if (current == null) return const SizedBox.shrink();
    final verdict = _verdictFor(current, peers, club, prefs, context.accent);
    final lat = current.lateralOffset;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: club?.color ?? AppColors.textDimmed,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _shotEyebrow(shotIndex, shotCount, club),
                      style: _mono(9.5, tracking: 1.4),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  verdict.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sans(size: 12).copyWith(height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('CARRY', style: _mono(8.5, color: _ink42, tracking: 1.6)),
              Text(
                prefs.dist(current.carry).toStringAsFixed(1),
                style: _cond(30),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('OFFLINE', style: _mono(8.5, color: _ink42, tracking: 1.6)),
              Text(
                '${prefs.dist(lat.abs()).toStringAsFixed(1)}'
                '${lat >= 0 ? 'R' : 'L'}',
                style: _cond(30),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shot ribbon ───────────────────────────────────────────────────────────────

/// One bar per shot along the bottom, height scaled to carry and coloured by
/// club — the whole bucket at a glance, and a scrubber for the rail. Newest
/// shots keep the right edge.
class _ShotRibbon extends StatelessWidget {
  final List<ShotData> allShots;
  final List<Club> clubs;
  final int selectedIndex;
  final UnitPrefs prefs;
  final Club? activeClub;
  final DateTime? startedAt;
  final ValueChanged<int> onShotTap;
  final VoidCallback onClubTap;

  const _ShotRibbon({
    required this.allShots,
    required this.clubs,
    required this.selectedIndex,
    required this.prefs,
    required this.activeClub,
    required this.startedAt,
    required this.onShotTap,
    required this.onClubTap,
  });

  String get _sessionLength {
    final start = startedAt;
    if (start == null) return '—';
    final mins = DateTime.now().difference(start).inMinutes;
    return mins < 60 ? '$mins MIN' : '${mins ~/ 60}H ${mins % 60}M';
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final carries = allShots.map((s) => s.carry).toList();
    final maxC = carries.isEmpty ? 1.0 : carries.reduce(math.max);
    final minC = carries.isEmpty ? 0.0 : carries.reduce(math.min);

    return Container(
      height: 112,
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 128,
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: _hairline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SHOTS', style: _mono(9.5, color: _ink30, tracking: 1.6)),
                Text('${allShots.length}', style: _cond(38)),
                Text(
                  _sessionLength,
                  style: _mono(9, color: _ink30, tracking: 0.8),
                ),
                const Spacer(),
                // The active club decides what the next swing is tagged as —
                // it lives beside the count of what the current one produced.
                Semantics(
                  button: true,
                  label: 'Active club',
                  child: GestureDetector(
                    onTap: onClubTap,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: activeClub?.color ?? AppColors.textDimmed,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (activeClub?.shortName ?? 'CLUB').toUpperCase(),
                          style: _mono(10, tracking: 1.2),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          AppIcons.chevronDown,
                          size: 11,
                          color: _ink42,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: allShots.isEmpty
                ? Center(
                    child: Text(
                      'SHOTS LAND HERE',
                      style: _mono(10, color: _ink30, tracking: 1.6),
                    ),
                  )
                // reverse:true keeps the newest bar parked at the right
                // edge without any scroll bookkeeping; allShots is already
                // newest-first, so item i is simply allShots[i].
                : ListView.builder(
                    reverse: true,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    itemCount: allShots.length,
                    itemBuilder: (context, i) {
                      final s = allShots[i];
                      final on = i == selectedIndex;
                      final clubColor =
                          clubs
                              .where((c) => c.id == s.clubId)
                              .firstOrNull
                              ?.color ??
                          AppColors.textDimmed;
                      final norm = maxC > minC
                          ? (s.carry - minC) / (maxC - minC)
                          : 0.5;
                      final h = 20 + norm * 42;
                      final ordinal = allShots.length - i;
                      return Semantics(
                        button: true,
                        selected: on,
                        label: 'Shot $ordinal',
                        child: GestureDetector(
                          onTap: () => onShotTap(i),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 40,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  prefs.dist(s.carry).toStringAsFixed(0),
                                  style: _cond(
                                    14,
                                    weight: FontWeight.w600,
                                    color: on ? Colors.white : _ink30,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: on ? 18 : 12,
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: on
                                        ? clubColor
                                        : clubColor.withAlpha(128),
                                    border: on
                                        ? Border.all(color: _ink55)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  ordinal.toString().padLeft(2, '0'),
                                  style: _mono(
                                    8,
                                    color: on ? accent : _ink30,
                                    tracking: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
