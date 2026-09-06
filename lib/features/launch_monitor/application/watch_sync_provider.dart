import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/clubs_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tile_formatting.dart';
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/log.dart';
import 'package:omni_sniffer/features/launch_monitor/data/watch_connectivity_channel.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/tag.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/watch_tile_payload.dart';
import 'package:omni_sniffer/shared/providers/accent_color_provider.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

/// The tiles as the Apple Watch should currently show them.
///
/// Composed from exactly the state the phone's Tiles tab reads — the same
/// metric list, the same club filter, the same selected shot, the same unit
/// preferences — and formatted with the same functions, so the watch is a
/// mirror rather than a second opinion.
final watchTilePayloadProvider = Provider<WatchTilePayload>((ref) {
  final status = ref.watch(launchMonitorProvider.select((s) => s.status));
  final allShots = ref.watch(launchMonitorProvider.select((s) => s.shots));
  final battery = ref.watch(
    launchMonitorProvider.select((s) => s.batteryPercent),
  );
  final ballReady = ref.watch(launchMonitorProvider.select((s) => s.ballReady));

  final metrics = ref.watch(selectedTilesProvider);
  final prefs = ref.watch(unitPrefsProvider);
  final accent = ref.watch(accentColorProvider);
  final filterClub = ref.watch(selectedClubProvider);
  final clubs = ref.watch(clubsProvider);
  final activeClub = ref.watch(activeClubProvider);
  final selectedIdx = ref.watch(selectedShotIndexProvider);
  final tags = ref.watch(tagsProvider).value ?? const <Tag>[];

  // Same peer set the tiles average over: everything in the session, or just
  // the filtered club when the golfer has narrowed the view.
  final peers = filterClub == null
      ? allShots
      : allShots.where((s) => s.clubId == filterClub.id).toList();

  final shot = allShots.isEmpty
      ? null
      : allShots[selectedIdx.clamp(0, allShots.length - 1)];
  final avg = peers.isEmpty ? null : ShotData.averageOf(peers);

  return WatchTilePayload(
    connection: _connectionOf(status),
    tiles: [
      for (final m in metrics) watchTileFor(m, shot, avg, prefs),
    ],
    shotCount: peers.length,
    shotIndex: shot == null ? 0 : peers.indexOf(shot) + 1,
    club: _clubLabel(shot, clubs, activeClub),
    accent: _hex(accent),
    battery: battery,
    ballReady: ballReady,
    tags: [
      for (final t in tags)
        WatchTag(id: t.id, name: t.name, color: _hex(t.color)),
    ],
    shotTags: shot?.tagIds ?? const [],
    // A shot that hasn't reached the database yet has no handle the watch
    // could send back, so it reports as untaggable rather than as taggable
    // and then failing.
    shotId: shot?.dbId ?? 0,
    sentAtMs: DateTime.now().millisecondsSinceEpoch,
  );
});

MonitorConnection _connectionOf(LaunchMonitorStatus status) => switch (status) {
  LaunchMonitorStatus.disconnected => MonitorConnection.disconnected,
  LaunchMonitorStatus.scanning => MonitorConnection.scanning,
  LaunchMonitorStatus.connecting => MonitorConnection.connecting,
  LaunchMonitorStatus.connected => MonitorConnection.connected,
};

/// Which club produced the shot on screen. Falls back to the club being hit
/// when the shot doesn't name one — a shot recorded before the bag was set up.
String _clubLabel(ShotData? shot, List<Club> clubs, Club? active) {
  final id = shot?.clubId;
  if (id != null) {
    for (final c in clubs) {
      if (c.id == id) return c.shortName;
    }
  }
  return active?.shortName ?? '';
}

/// One tile of the watch screen: [metric] read off [shot], with the session
/// average from [avgShot] behind it. Public so the mapping can be tested
/// without a provider container.
WatchTile watchTileFor(
  TileMetric metric,
  ShotData? shot,
  ShotData? avgShot,
  UnitPrefs prefs,
) {
  // The impact tile is two readouts in one on the phone; it stays two here.
  if (metric == TileMetric.impactLocation) {
    return WatchTile(
      id: metric.name,
      label: metric.label,
      value: fmtImpactH(shot?.horizontalImpact),
      unit: 'mm',
      average: fmtImpactH(avgShot?.horizontalImpact),
      secondaryLabel: 'VERT',
      secondaryValue: fmtImpactV(shot?.verticalImpact),
    );
  }

  final (number, suffix) = splitValueSuffix(metricValue(metric, shot, prefs));
  final avgStr = avgShot == null ? '' : metricValue(metric, avgShot, prefs);

  var delta = '';
  final cur = metricRaw(metric, shot, prefs);
  final avg = metricRaw(metric, avgShot, prefs);
  if (cur != null && avg != null) {
    delta = '±${(cur - avg).abs().toStringAsFixed(1)}';
  }

  return WatchTile(
    id: metric.name,
    label: metric.label,
    value: number,
    suffix: suffix,
    unit: tileUnit(metric, prefs),
    average: avgStr,
    delta: delta,
  );
}

/// [current] with [tagId] added or removed. Order is preserved so the phone's
/// tag chips don't reshuffle when the watch touches them, and a repeated
/// command is a no-op rather than a duplicate.
List<int> nextTagIds(List<int> current, int tagId, {required bool on}) {
  if (on) {
    return current.contains(tagId) ? current : [...current, tagId];
  }
  return [
    for (final id in current)
      if (id != tagId) id,
  ];
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Keeps the paired Apple Watch fed with [watchTilePayloadProvider], and
/// exposes what the link is doing so the UI could show it.
///
/// Watch it once for the app's lifetime — `main.dart` does — and it runs
/// itself. Off iOS it is inert and costs nothing.
final watchSyncProvider = NotifierProvider<WatchSync, WatchLinkState>(
  WatchSync.new,
);

class WatchSync extends Notifier<WatchLinkState> {
  /// Shots arrive one at a time, but a club change or a tile re-order can
  /// churn the payload several times in a frame. Coalescing to this interval
  /// keeps the radio quiet without the watch ever feeling behind.
  static const _minInterval = Duration(milliseconds: 300);

  WatchConnectivityChannel? _channel;
  Timer? _timer;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSignature;
  bool _sending = false;

  /// A payload changed while a send was in flight. Without this the newer
  /// one is simply lost: the tag list resolves from the database moments
  /// after the app starts, which is exactly when the first send is still in
  /// the air, and nothing would change again until the next shot.
  bool _resendQueued = false;
  bool _resendForced = false;

  @override
  WatchLinkState build() {
    if (!WatchConnectivityChannel.isSupported) {
      return WatchLinkState.unsupported;
    }

    final channel = WatchConnectivityChannel();
    _channel = channel;

    // The watch app just launched, or came back into range, and wants the
    // current screen. Bypass the duplicate check: its copy may be stale even
    // though nothing changed on the phone.
    channel.onSyncRequested = () => _send(force: true);
    channel.onCommand = _handleCommand;
    channel.onStateChanged = (link) {
      state = link;
      // A watch that has only now become reachable never saw the payloads
      // sent while it was asleep.
      if (link.reachable) _send(force: true);
    };

    ref.listen<WatchTilePayload>(
      watchTilePayloadProvider,
      (_, next) => _schedule(),
      fireImmediately: true,
    );

    ref.onDispose(() {
      _timer?.cancel();
      channel.dispose();
      _channel = null;
    });

    unawaited(_refreshLink());
    return WatchLinkState.unsupported;
  }

  /// Runs a command the watch sent. The reply travels back to the wrist, so
  /// every outcome — including refusal — has to be something worth reading
  /// on a 45mm screen.
  Future<Map<String, Object>> _handleCommand(WatchCommand command) async {
    switch (command.action) {
      case 'toggleTag':
        return _toggleTag(command);
      default:
        return WatchCommand.failure('The phone does not know that command.');
    }
  }

  /// Adds or removes one tag on one shot, by database id.
  ///
  /// The id is what makes this safe: a shot arrives on the watch, the golfer
  /// tags it a moment later, and by then the selection on the phone may have
  /// moved on. Tagging by identity puts the tag on the shot they were
  /// looking at, never on whatever is selected now.
  Future<Map<String, Object>> _toggleTag(WatchCommand command) async {
    if (command.shotId <= 0 || command.tagId <= 0) {
      return WatchCommand.failure('That shot cannot be tagged.');
    }

    final shots = ref.read(launchMonitorProvider).shots;
    final index = shots.indexWhere((s) => s.dbId == command.shotId);
    if (index < 0) {
      return WatchCommand.failure('That shot is no longer in the session.');
    }

    final tags = ref.read(tagsProvider).value ?? const <Tag>[];
    if (!tags.any((t) => t.id == command.tagId)) {
      return WatchCommand.failure('That tag no longer exists.');
    }

    final next = nextTagIds(
      shots[index].tagIds,
      command.tagId,
      on: command.on,
    );
    await ref
        .read(launchMonitorProvider.notifier)
        .updateShotTags(index, next);

    // The watch showed the change optimistically the moment it was tapped;
    // this is what makes it true there as well as here.
    await _send(force: true);
    return WatchCommand.success();
  }

  Future<void> _refreshLink() async {
    final link = await _channel?.refresh();
    if (link != null && _channel != null) state = link;
  }

  /// Sends at most once per [_minInterval], and always sends the newest
  /// payload — a burst ends with the trailing edge, never a stale value.
  void _schedule() {
    if (_timer != null) return;
    final since = DateTime.now().difference(_lastSend);
    if (since >= _minInterval) {
      _send();
      return;
    }
    _timer = Timer(_minInterval - since, () {
      _timer = null;
      _send();
    });
  }

  Future<void> _send({bool force = false}) async {
    final channel = _channel;
    if (channel == null) return;
    if (_sending) {
      _resendQueued = true;
      _resendForced = _resendForced || force;
      return;
    }

    final payload = ref.read(watchTilePayloadProvider);
    if (!force && payload.signature == _lastSignature) return;

    _sending = true;
    _lastSend = DateTime.now();
    try {
      final link = await channel.send(payload);
      if (_channel == null) return;
      _lastSignature = payload.signature;
      state = link;
      lmLog(
        'watch',
        'sent ${payload.tiles.length} tiles · ${payload.tags.length} tags · '
        'shot ${payload.shotId} (${payload.shotTags.length} tagged) · '
        'paired=${link.paired} installed=${link.appInstalled} '
        'reachable=${link.reachable}',
      );
    } finally {
      _sending = false;
      if (_resendQueued) {
        _resendQueued = false;
        final forced = _resendForced;
        _resendForced = false;
        // A forced resend is answering the watch and should not wait out the
        // throttle; an ordinary one rides the next trailing edge.
        if (forced) {
          unawaited(_send(force: true));
        } else {
          _schedule();
        }
      }
    }
  }

  /// Pushes the current tiles to the watch immediately, duplicate or not.
  /// Exposed for a "resend to watch" affordance and for tests.
  @visibleForTesting
  Future<void> syncNow() => _send(force: true);
}
