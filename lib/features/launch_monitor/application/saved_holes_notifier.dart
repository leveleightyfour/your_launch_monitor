import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/saved_hole.dart';

/// The player's library of saved holes, newest first.
final savedHolesProvider =
    NotifierProvider<SavedHolesNotifier, List<SavedHole>>(
      SavedHolesNotifier.new,
    );

class SavedHolesNotifier extends Notifier<List<SavedHole>> {
  static const _fileName = 'saved_holes.json';

  @override
  List<SavedHole> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      state = [
        for (final entry in decoded)
          if (entry is Map) SavedHole.fromJson(entry.cast<String, dynamic>()),
      ];
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode([for (final h in state) h.toJson()]));
    } catch (_) {}
  }

  /// Saves a hole, replacing any existing hole of the same name — saving
  /// under a name you already used reads as "update that one".
  void save(SavedHole hole) {
    state = [hole, ...state.where((h) => h.name != hole.name)];
    _save();
  }

  void delete(String name) {
    state = state.where((h) => h.name != name).toList();
    _save();
  }
}
