import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_sniffer/shared/providers/router.dart';
import 'package:omni_sniffer/shared/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    FlutterBluePlus.setLogLevel(LogLevel.warning);
  }
  runApp(const OmniSnifferApp());
}

class OmniSnifferApp extends StatelessWidget {
  const OmniSnifferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: "Your Launch Monitor",
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        routerConfig: appRouter,
      ),
    );
  }
}
