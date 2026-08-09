/// Carries saved data out of the old macOS sandbox container.
///
/// Turning the sandbox off moves both roots the app stores things under:
/// Application Support and Documents stop resolving inside
/// `~/Library/Containers/<bundle id>/Data` and start resolving to the real
/// `~/Library/Application Support/<bundle id>` and `~/Documents`. Without this,
/// the first unsandboxed launch would look like a factory reset — every
/// session and shot lives in `omni_sniffer.sqlite` under Documents, and every
/// preference is a flat file under Application Support.
///
/// The copy is one-way and never overwrites: anything already at the new
/// location wins, so a second run can't undo work done since the first.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class MacosDataMigration {
  MacosDataMigration._();

  /// Dropped into the new support folder once the copy has run, so deleting a
  /// preference afterwards doesn't resurrect it from the container on the next
  /// launch.
  static const markerName = '.migrated-from-sandbox-container';

  /// The drift database, named in [database.dart] as `omni_sniffer`. The
  /// journal siblings only exist if the app was killed mid-write; copying the
  /// `.sqlite` without them would silently drop the last transactions.
  static const _databaseFiles = [
    'omni_sniffer.sqlite',
    'omni_sniffer.sqlite-wal',
    'omni_sniffer.sqlite-shm',
  ];

  /// Copies container data forward if there is any. Safe to call on every
  /// platform and every launch; it does nothing after the first success.
  ///
  /// Runs before the database is opened or any preference is read, and
  /// swallows its own failures — a migration that can't complete is a reason
  /// to start empty, not a reason not to start.
  static Future<void> run() async {
    if (!Platform.isMacOS) return;
    try {
      final support = await getApplicationSupportDirectory();
      // Still sandboxed: these paths already point inside the container, so
      // there is nothing to move and the marker would be written to the very
      // folder it is meant to protect.
      if (support.path.contains('/Library/Containers/')) return;

      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;

      // The support folder is `.../Application Support/<bundle id>`, so its
      // own name is the bundle id — no plugin needed to ask for it.
      final bundleId = support.path.split('/').last;
      await migrate(
        container: Directory('$home/Library/Containers/$bundleId/Data'),
        support: support,
        // The database moves to Application Support on macOS — see
        // _openConnection in database.dart. Landing it in the real ~/Documents
        // would also mean a TCC prompt during launch, before the window is up.
        databaseDirectory: support,
        bundleId: bundleId,
      );
    } catch (error) {
      debugPrint('[migration] container migration skipped — $error');
    }
  }

  /// The copy itself, with every location handed in so it can be exercised
  /// against temp folders. Returns how many files moved across.
  @visibleForTesting
  static Future<int> migrate({
    required Directory container,
    required Directory support,
    required Directory databaseDirectory,
    required String bundleId,
  }) async {
    final marker = File('${support.path}/$markerName');
    if (await marker.exists()) return 0;
    if (!await container.exists()) {
      await _markDone(marker);
      return 0;
    }

    var copied = 0;
    copied += await _copyPreferences(
      Directory('${container.path}/Library/Application Support/$bundleId'),
      support,
    );
    copied += await _copyDatabase(
      Directory('${container.path}/Documents'),
      databaseDirectory,
    );

    final oldClips = Directory('${container.path}/Documents/clips');
    if (await oldClips.exists()) {
      debugPrint(
        '[migration] earlier exports are still in ${oldClips.path} — '
        'left in place rather than stalling launch on a large copy',
      );
    }

    debugPrint('[migration] carried $copied file(s) out of the container');
    await _markDone(marker);
    return copied;
  }

  /// Everything the app keeps flat in Application Support: `unit_prefs.json`,
  /// `hole_setup.json`, the rest, plus the cached font files google_fonts
  /// leaves alongside them — cheap to copy and one less first-run download.
  /// Dotfiles are skipped, `.DS_Store` being Finder's rather than ours, and so
  /// are subdirectories: nothing here writes one, and recursing would risk
  /// dragging an unbounded cache into launch.
  static Future<int> _copyPreferences(Directory from, Directory to) async {
    if (!await from.exists()) return 0;
    await to.create(recursive: true);
    var copied = 0;
    await for (final entity in from.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (await _copyIfAbsent(entity, '${to.path}/$name')) copied++;
    }
    return copied;
  }

  static Future<int> _copyDatabase(Directory from, Directory to) async {
    if (!await from.exists()) return 0;
    // A half-copied database is worse than none: if the main file is already
    // at the new location it is the live one, and dropping a stale journal
    // beside it would corrupt it.
    if (await File('${to.path}/${_databaseFiles.first}').exists()) return 0;
    await to.create(recursive: true);
    var copied = 0;
    for (final name in _databaseFiles) {
      final file = File('${from.path}/$name');
      if (!await file.exists()) continue;
      if (await _copyIfAbsent(file, '${to.path}/$name')) copied++;
    }
    return copied;
  }

  static Future<bool> _copyIfAbsent(File source, String target) async {
    if (await File(target).exists()) return false;
    await source.copy(target);
    debugPrint('[migration] ${source.path} → $target');
    return true;
  }

  static Future<void> _markDone(File marker) async {
    try {
      await marker.parent.create(recursive: true);
      await marker.writeAsString('');
    } catch (_) {}
  }
}
