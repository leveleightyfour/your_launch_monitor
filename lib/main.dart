import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omni_sniffer/shared/providers/accent_color_provider.dart';
import 'package:omni_sniffer/shared/providers/router.dart';
import 'package:omni_sniffer/shared/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    FlutterBluePlus.setLogLevel(LogLevel.warning);
    // Trigger the BT/Location permission prompt at app load instead of on
    // first Connect tap. Fire-and-forget — the app shouldn't wait for the
    // user's response.
    unawaited(_primeBlePermissions());
  }
  await AccentColorNotifier.preload();
  runApp(const ProviderScope(child: OmniSnifferApp()));
}

Future<void> _primeBlePermissions() async {
  // A 50 ms scan is enough for the OS to surface the permission prompt
  // (CBCentralManager init on iOS, ACCESS_FINE_LOCATION / BLUETOOTH_SCAN on
  // Android). Errors are swallowed: denial is fine, the user can grant later
  // from settings.
  try {
    await FlutterBluePlus.startScan(
      timeout: const Duration(milliseconds: 50),
    );
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
    return MaterialApp.router(
      title: "Your Launch Monitor",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(accent: accent),
      routerConfig: appRouter,
    );
  }
}
