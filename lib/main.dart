import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/features/launch_monitor/application/watch_sync_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/data/last_device_provider.dart';
import 'package:omni_sniffer/shared/providers/accent_color_provider.dart';
import 'package:omni_sniffer/shared/providers/router.dart';
import 'package:omni_sniffer/shared/providers/shorebird_update_provider.dart';
import 'package:omni_sniffer/shared/services/macos_data_migration.dart';
import 'package:omni_sniffer/shared/theme.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything reads a preference or opens the database: on macOS both
  // roots moved when the sandbox came off, and this carries the old container's
  // contents forward. No-ops everywhere else and after the first run.
  await MacosDataMigration.run();
  if (!Platform.isWindows) {
    FlutterBluePlus.setLogLevel(LogLevel.warning);
    // Trigger the BT/Location permission prompt at app load instead of on
    // first Connect tap. Fire-and-forget — the app shouldn't wait for the
    // user's response.
    unawaited(_primeBlePermissions());
  }
  await Future.wait([
    AccentColorNotifier.preload(),
    LastDeviceNotifier.preload(),
  ]);
  runApp(
    ProviderScope(
      observers: [RiverpodDevToolsObserver()],
      child: OmniSnifferApp(),
    ),
  );
}

Future<void> _primeBlePermissions() async {
  // A 50 ms scan is enough for the OS to surface the permission prompt
  // (CBCentralManager init on iOS, ACCESS_FINE_LOCATION / BLUETOOTH_SCAN on
  // Android). Errors are swallowed: denial is fine, the user can grant later
  // from settings.
  try {
    await FlutterBluePlus.startScan(timeout: const Duration(milliseconds: 50));
  } catch (_) {}
  try {
    await FlutterBluePlus.stopScan();
  } catch (_) {}
}

class OmniSnifferApp extends ConsumerWidget {
  const OmniSnifferApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentColorProvider);
    // Construct + start the Shorebird update poller for the app lifetime.
    // No-ops in debug / non-Shorebird builds.
    ref.watch(shorebirdUpdateProvider);
    // Keeps a paired Apple Watch showing the same tiles as the session
    // screen. Inert on every platform but iOS.
    ref.watch(watchSyncProvider);
    return MaterialApp.router(
      title: "Your Launch Monitor",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(accent: accent),
      routerConfig: appRouter,
    );
  }
}
