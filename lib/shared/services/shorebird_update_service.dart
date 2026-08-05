/// Self-managed Shorebird OTA patch updates.
///
/// `shorebird.yaml` must set `auto_update: false` — that hands update control
/// to this service instead of the engine silently applying patches on the
/// next cold start. The service polls the stable track periodically, exposes
/// a manual check, and reports [UpdatePhase.readyToRestart] once a patch is
/// downloaded. A patch only takes effect after a cold process restart
/// ([restartToUpdate]) — a widget rebuild is not enough.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

enum UpdatePhase { idle, checking, downloading, readyToRestart, failed }

class ShorebirdUpdateService extends ChangeNotifier {
  ShorebirdUpdateService({
    ShorebirdUpdater? updater,
    this.pollInterval = const Duration(minutes: 20),
  }) : _updater = updater ?? ShorebirdUpdater();

  final ShorebirdUpdater _updater;
  final Duration pollInterval;

  Timer? _timer;
  bool _inFlight = false;
  UpdatePhase _phase = UpdatePhase.idle;
  DateTime? _lastCheckedAt;
  int? _nextPatchNumber;

  UpdatePhase get phase => _phase;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  int? get nextPatchNumber => _nextPatchNumber;
  bool get updateReady => _phase == UpdatePhase.readyToRestart;

  /// Whether this build can receive OTA patches at all. False on platforms
  /// Shorebird does not patch (desktop, web) and in non-Shorebird builds
  /// (debug runs, plain `flutter build` releases) — every check would no-op,
  /// so update UI should not render.
  bool get isAvailable => _updater.isAvailable;

  /// Call ONCE at app start. Starts the poll + does an immediate boot check.
  /// No-ops in debug / non-Shorebird builds ([ShorebirdUpdater.isAvailable]).
  void start() {
    if (!_updater.isAvailable) return;
    _timer ??= Timer.periodic(pollInterval, (_) => checkNow());
    scheduleMicrotask(checkNow);
  }

  /// Manual check (also used by the poll timer). Re-entrancy guarded.
  Future<void> checkNow() async {
    if (_inFlight || !_updater.isAvailable) return;
    _inFlight = true;
    _set(UpdatePhase.checking);
    try {
      // No `track:` arg → defaults to the stable track.
      final status =
          await _updater.checkForUpdate().timeout(const Duration(seconds: 10));
      switch (status) {
        case UpdateStatus.outdated:
          _set(UpdatePhase.downloading);
          await _updater.update(); // downloads the patch
          _nextPatchNumber = (await _updater.readNextPatch())?.number;
          _set(UpdatePhase.readyToRestart);
        case UpdateStatus.restartRequired:
          // Already downloaded on a previous check, awaiting restart.
          _nextPatchNumber = (await _updater.readNextPatch())?.number;
          _set(UpdatePhase.readyToRestart);
        case UpdateStatus.upToDate:
        case UpdateStatus.unavailable:
          _set(UpdatePhase.idle);
      }
    } catch (_) {
      _set(UpdatePhase.failed);
    } finally {
      _lastCheckedAt = DateTime.now();
      _inFlight = false;
      notifyListeners();
    }
  }

  /// Whether this platform can only quit (not relaunch) to apply a patch.
  /// iOS has no sanctioned relaunch API — the patch boots on the next
  /// manual open after the process exits.
  bool get quitOnlyRestart => !kIsWeb && Platform.isIOS;

  /// Apply the downloaded patch: cold-restart on Android, quit on iOS.
  ///
  /// On iOS `restart_app` either schedules a notification + exit(0)
  /// (needs notification permission — silently no-ops when denied) or
  /// reports process restart as unsupported, so we exit directly instead.
  /// The caller's dialog copy must make clear the user reopens the app
  /// themselves ([quitOnlyRestart]).
  Future<void> restartToUpdate() async {
    if (quitOnlyRestart) {
      exit(0);
    }
    await Restart.restartApp();
  }

  void _set(UpdatePhase p) {
    _phase = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
