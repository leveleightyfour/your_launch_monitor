import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/app_shell.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/my_bag_screen.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/session_detail_screen.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/session_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const AppShell(),
      routes: [
        GoRoute(
          path: 'session/new',
          builder: (_, state) =>
              SessionScreen(initialName: state.extra as String?),
        ),
        GoRoute(
          path: 'session/:id',
          builder: (_, state) =>
              SessionDetailScreen(session: state.extra as Session),
        ),
        GoRoute(
          path: 'bag/add-clubs',
          pageBuilder: (_, __) => const MaterialPage(
            child: AddClubsScreen(),
            fullscreenDialog: true,
          ),
        ),
      ],
    ),
  ],
);
