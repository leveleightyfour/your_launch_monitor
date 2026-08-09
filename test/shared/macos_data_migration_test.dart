/// Dropping the macOS sandbox moves Application Support and Documents out of
/// `~/Library/Containers`, which without a migration reads as a factory reset:
/// every session lives in the drift database under Documents and every
/// preference is a flat file under Application Support. These cover the shapes
/// that matter — the copy runs once, it never overwrites what's already at the
/// new location, and it doesn't drag the container's own junk along.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/shared/services/macos_data_migration.dart';

const _bundleId = 'com.example.omniSniffer';

/// A container laid out the way macOS does, seeded with [preferences] and,
/// unless [withDatabase] is false, a drift database.
Directory _seedContainer(
  Directory root, {
  Map<String, String> preferences = const {'unit_prefs.json': '{"a":1}'},
  bool withDatabase = true,
}) {
  final container = Directory('${root.path}/Containers/$_bundleId/Data')
    ..createSync(recursive: true);
  final oldSupport = Directory(
    '${container.path}/Library/Application Support/$_bundleId',
  )..createSync(recursive: true);
  preferences.forEach(
    (name, contents) =>
        File('${oldSupport.path}/$name').writeAsStringSync(contents),
  );
  final oldDocuments = Directory('${container.path}/Documents')
    ..createSync(recursive: true);
  if (withDatabase) {
    File(
      '${oldDocuments.path}/omni_sniffer.sqlite',
    ).writeAsStringSync('sessions');
  }
  return container;
}

void main() {
  late Directory root;
  late Directory support;
  late Directory documents;

  setUp(() {
    root = Directory.systemTemp.createTempSync('migration_test');
    support = Directory('${root.path}/Application Support/$_bundleId')
      ..createSync(recursive: true);
    documents = Directory('${root.path}/Documents')
      ..createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// [documents] stands in for wherever the database lands — Application
  /// Support in the real macOS call, kept separate here so the parameter is
  /// proved to be honoured rather than coinciding with [support].
  Future<int> migrate(Directory container) => MacosDataMigration.migrate(
    container: container,
    support: support,
    databaseDirectory: documents,
    bundleId: _bundleId,
  );

  test('carries preferences and the database out of the container', () async {
    final container = _seedContainer(
      root,
      preferences: {'unit_prefs.json': '{"a":1}', 'hole_setup.json': '{"b":2}'},
    );

    expect(await migrate(container), 3);
    expect(
      File('${support.path}/unit_prefs.json').readAsStringSync(),
      '{"a":1}',
    );
    expect(
      File('${support.path}/hole_setup.json').readAsStringSync(),
      '{"b":2}',
    );
    expect(
      File('${documents.path}/omni_sniffer.sqlite').readAsStringSync(),
      'sessions',
    );
  });

  test('brings the journal files along with the database', () async {
    final container = _seedContainer(root, preferences: {});
    File(
      '${container.path}/Documents/omni_sniffer.sqlite-wal',
    ).writeAsStringSync('pending');

    expect(await migrate(container), 2);
    expect(
      File('${documents.path}/omni_sniffer.sqlite-wal').readAsStringSync(),
      'pending',
    );
  });

  test('leaves the container\'s own junk behind', () async {
    final container = _seedContainer(root, withDatabase: false);
    File(
      '${container.path}/Library/Application Support/$_bundleId/.DS_Store',
    ).writeAsStringSync('junk');
    Directory(
      '${container.path}/Library/Application Support/$_bundleId/fonts',
    ).createSync();

    expect(await migrate(container), 1);
    expect(File('${support.path}/.DS_Store').existsSync(), isFalse);
    expect(Directory('${support.path}/fonts').existsSync(), isFalse);
  });

  test('never overwrites what is already at the new location', () async {
    final container = _seedContainer(root);
    File('${support.path}/unit_prefs.json').writeAsStringSync('{"newer":1}');
    File('${documents.path}/omni_sniffer.sqlite').writeAsStringSync('newer');

    expect(await migrate(container), 0);
    expect(
      File('${support.path}/unit_prefs.json').readAsStringSync(),
      '{"newer":1}',
    );
    expect(
      File('${documents.path}/omni_sniffer.sqlite').readAsStringSync(),
      'newer',
    );
  });

  test('a live database is never given a stale journal', () async {
    final container = _seedContainer(root, preferences: {});
    File(
      '${container.path}/Documents/omni_sniffer.sqlite-wal',
    ).writeAsStringSync('stale');
    File('${documents.path}/omni_sniffer.sqlite').writeAsStringSync('live');

    expect(await migrate(container), 0);
    expect(
      File('${documents.path}/omni_sniffer.sqlite-wal').existsSync(),
      isFalse,
    );
  });

  test('runs once — a deleted preference stays deleted', () async {
    final container = _seedContainer(root);
    expect(await migrate(container), 2);
    File('${support.path}/unit_prefs.json').deleteSync();

    expect(await migrate(container), 0);
    expect(File('${support.path}/unit_prefs.json').existsSync(), isFalse);
  });

  test('marks itself done when there is no container to read', () async {
    expect(await migrate(Directory('${root.path}/nothing/here')), 0);
    expect(
      File('${support.path}/${MacosDataMigration.markerName}').existsSync(),
      isTrue,
    );
  });
}
