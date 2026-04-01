import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/data/database.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/tag.dart';

/// Singleton database — shared by tags, activities, and any other feature
/// that needs DB access. keepAlive so it is never torn down.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) {
    final db = AppDatabase();
    ref.onDispose(db.close);
    return db;
  },
  dependencies: const [],
);

/// Live list of all user-created tags, loaded once and kept alive.
final tagsProvider =
    AsyncNotifierProvider<TagsNotifier, List<Tag>>(TagsNotifier.new);

class TagsNotifier extends AsyncNotifier<List<Tag>> {
  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  Future<List<Tag>> build() => _db.getAllTags();

  Future<Tag> addTag(String name, Color color) async {
    final tag = await _db.insertTag(name, color);
    state = AsyncData([...state.value ?? [], tag]);
    return tag;
  }

  Future<void> removeTag(int id) async {
    await _db.deleteTag(id);
    state = AsyncData(
      (state.value ?? []).where((t) => t.id != id).toList(),
    );
  }
}
