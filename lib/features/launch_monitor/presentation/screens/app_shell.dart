import 'package:flutter/material.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/session_list_screen.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/my_bag_screen.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/screens/profile_screen.dart';
import 'package:omni_sniffer/shared/theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = <Widget>[
    SessionListScreen(),
    MyBagScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Content — padded so it doesn't hide behind the pill nav
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPad + 72),
              child: IndexedStack(index: _index, children: _screens),
            ),
          ),
          // Floating pill nav
          Positioned(
            bottom: bottomPad + 16,
            left: 0,
            right: 0,
            child: Center(
              child: _PillNav(
                index: _index,
                onTap: (i) => setState(() => _index = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Floating pill navigation ──────────────────────────────────────────────────

class _PillNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _PillNav({required this.index, required this.onTap});

  static const _items = [
    (icon: Icons.bolt_rounded, label: 'Sessions'),
    (icon: Icons.sports_golf, label: 'My Bag'),
    (icon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_items.length, (i) {
          final item = _items[i];
          final active = i == index;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? context.accentSubtle : Colors.transparent,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: active ? context.accentBorder : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    color: active ? context.accent : AppColors.textDimmed,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? context.accent : AppColors.textDimmed,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
