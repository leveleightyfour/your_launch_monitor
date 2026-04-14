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
  }
  await AccentColorNotifier.preload();
  runApp(const ProviderScope(child: OmniSnifferApp()));
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
