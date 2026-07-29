import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';
import 'package:omni_sniffer/shared/providers/hole_setup_provider.dart';

/// Holds the list of completed past sessions (most recent first).
final sessionsProvider = NotifierProvider<SessionsNotifier, List<Session>>(
  SessionsNotifier.new,
);

class SessionsNotifier extends Notifier<List<Session>> {
  /// Sessions exactly as stored, before the configured hole is filled in.
  /// Kept separately so changing the hole re-derives from the database rather
  /// than from an already-stamped copy.
  List<Session> _stored = const [];

  @override
  List<Session> build() {
    // Sessions recorded before a hole was configured carry none. Rather than
    // showing them on bare ground while the app is set up to play a hole, they
    // adopt whatever is configured now. Sessions that recorded their own hole
    // keep it, so their numbers never move.
    ref.listen(
      holeSetupProvider,
      (_, next) => state = _withHole(_stored, next),
    );
    _loadFromDb();
    return const [];
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(appDatabaseProvider);
    _stored = await db.getAllSessions();
    state = _withHole(_stored, ref.read(holeSetupProvider));
  }

  List<Session> _withHole(List<Session> sessions, HoleSetup setting) {
    final active = setting.enabled ? setting : null;
    if (active == null) return sessions;
    return [
      for (final session in sessions)
        Session(
          id: session.id,
          name: session.name,
          createdAt: session.createdAt,
          shots: [
            for (final shot in session.shots)
              shot.hole == null ? shot.copyWith(hole: active) : shot,
          ],
        ),
    ];
  }

  /// Called when the user finishes a session — persists to DB.
  ///
  /// If [draftSessionId] is provided the shots are already in the DB
  /// (written live during the session) — only the name needs updating.
  /// Otherwise the session is inserted fresh (fallback / seed sessions).
  Future<void> addSession(Session session, {int? draftSessionId}) async {
    final db = ref.read(appDatabaseProvider);
    if (draftSessionId != null) {
      await db.finalizeSession(draftSessionId, session.name);
    } else {
      await db.saveSession(session);
    }
    // Reload from DB so all shots carry their dbIds.
    await _loadFromDb();
  }

  /// Removes a session from the list without touching the DB — used when a
  /// recovered draft is resumed and its row becomes the live session again
  /// (the active-session tile takes over). Finishing reloads from the DB,
  /// so the session reappears here once saved.
  void detachSession(String id) {
    _stored = _stored.where((s) => s.id != id).toList();
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> removeSession(String id) async {
    final numId = int.tryParse(id);
    if (numId != null) {
      await ref.read(appDatabaseProvider).deleteSession(numId);
    }
    state = state.where((a) => a.id != id).toList();
  }

  /// Renames a stored session in the DB and patches the in-memory list.
  Future<void> renameSession(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final numId = int.tryParse(id);
    if (numId != null) {
      await ref.read(appDatabaseProvider).finalizeSession(numId, trimmed);
    }
    state = [
      for (final s in state)
        s.id == id
            ? Session(
                id: s.id,
                name: trimmed,
                createdAt: s.createdAt,
                shots: s.shots,
              )
            : s,
    ];
  }

  /// Permanently deletes shots by their DB IDs and patches in-memory state.
  Future<void> deleteShots(List<int> shotDbIds) async {
    final db = ref.read(appDatabaseProvider);
    for (final id in shotDbIds) {
      await db.deleteShotById(id);
    }
    state = [
      for (final session in state)
        Session(
          id: session.id,
          name: session.name,
          createdAt: session.createdAt,
          shots: session.shots
              .where((s) => !shotDbIds.contains(s.dbId))
              .toList(),
        ),
    ];
  }

  /// Updates the tags for a single shot inside a stored session.
  Future<void> updateShotTags(int shotDbId, List<int> tagIds) async {
    final db = ref.read(appDatabaseProvider);
    await db.updateShotTagIds(shotDbId, tagIds);
    // Patch in-memory state so detail screen updates without a full reload.
    state = [
      for (final session in state)
        Session(
          id: session.id,
          name: session.name,
          createdAt: session.createdAt,
          shots: [
            for (final shot in session.shots)
              shot.dbId == shotDbId ? shot.copyWith(tagIds: tagIds) : shot,
          ],
        ),
    ];
  }
}
