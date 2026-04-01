import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/data/seed_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/application/tags_notifier.dart';

/// Holds the list of completed past sessions (most recent first).
final sessionsProvider = NotifierProvider<SessionsNotifier, List<Session>>(
  SessionsNotifier.new,
);

class SessionsNotifier extends Notifier<List<Session>> {
  @override
  List<Session> build() {
    _loadFromDb();
    return const [];
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(appDatabaseProvider);
    var rows = await db.getAllSessions();
    if (rows.isEmpty) {
      for (final s in seedSessions) {
        await db.saveSession(s);
      }
      rows = await db.getAllSessions();
    }
    state = rows;
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
    final rows = await db.getAllSessions();
    state = rows;
  }

  Future<void> removeSession(String id) async {
    final numId = int.tryParse(id);
    if (numId != null) {
      await ref.read(appDatabaseProvider).deleteSession(numId);
    }
    state = state.where((a) => a.id != id).toList();
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
