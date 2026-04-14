import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_sniffer/features/launch_monitor/application/providers.dart';
import 'package:omni_sniffer/features/launch_monitor/application/sessions_notifier.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/launch_monitor_state.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/status_indicator.dart';
import 'package:omni_sniffer/shared/theme.dart';

class SessionListScreen extends ConsumerWidget {
  const SessionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(launchMonitorProvider.select((s) => s.status));
    final activeShots = ref.watch(launchMonitorProvider.select((s) => s.shots));
    final notifier = ref.read(launchMonitorProvider.notifier);
    final pastSessions = ref.watch(sessionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Sessions',
                    style: AppTextStyles.sans(size: 20, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _ConnectChip(
                    status: status,
                    onConnect: notifier.startScan,
                    onDisconnect: notifier.disconnect,
                  ),
                ],
              ),
            ),
            const Divider(height: 24, color: AppColors.border),
            // Start button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _startSession(context),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(
                    'New session',
                    style: AppTextStyles.sans(
                      size: 14,
                      weight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 24, color: AppColors.border),
            // Sessions label
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Sessions',
                style: AppTextStyles.sans(
                  size: 10,
                  weight: FontWeight.w600,
                  color: AppColors.textDimmed,
                ),
              ),
            ),
            // Combined list: active session first, then past sessions
            Expanded(
              child: (activeShots.isEmpty && pastSessions.isEmpty)
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border2),
                            ),
                            child: const Icon(
                              Icons.sports_golf,
                              size: 28,
                              color: AppColors.textDimmed,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No sessions yet',
                            style: AppTextStyles.sans(
                              size: 16,
                              weight: FontWeight.w400,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap "New Session" to start tracking',
                            style: AppTextStyles.sans(
                              size: 13,
                              color: AppColors.textDimmed,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount:
                          (activeShots.isNotEmpty ? 1 : 0) +
                          pastSessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (activeShots.isNotEmpty && i == 0) {
                          return _ActiveSessionTile(
                            shotCount: activeShots.length,
                            onTap: () => _startSession(context, resume: true),
                          );
                        }
                        final idx = activeShots.isNotEmpty ? i - 1 : i;
                        return _SessionTile(session: pastSessions[idx]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startSession(BuildContext context, {bool resume = false}) async {
    if (resume) {
      context.push('/session/new');
      return;
    }
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'New session',
          style: AppTextStyles.sans(size: 17, weight: FontWeight.w600),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: AppTextStyles.sans(size: 15),
          decoration: InputDecoration(
            hintText: 'Session name (optional)',
            hintStyle: AppTextStyles.sans(size: 15, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTextStyles.sans(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Start',
                style: AppTextStyles.sans(
                    weight: FontWeight.w600, color: Colors.black)),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    final name = nameCtrl.text.trim();
    context.push('/session/new', extra: name.isEmpty ? null : name);
  }
}

// ── Active session tile ───────────────────────────────────────────────────────

class _ActiveSessionTile extends StatelessWidget {
  final int shotCount;
  final VoidCallback onTap;

  const _ActiveSessionTile({required this.shotCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.accentGhost,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.accentMid, width: 1.5),
        ),
        child: Row(
          children: [
            // Live icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.accentFaint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.accentBorder),
              ),
              child: Center(
                child: Icon(Icons.bolt_rounded, size: 18, color: context.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Session in Progress',
                        style: AppTextStyles.sans(
                          size: 14,
                          weight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Live',
                          style: AppTextStyles.sans(
                            size: 9,
                            weight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$shotCount ${shotCount == 1 ? 'shot' : 'shots'} · Tap to resume',
                    style: AppTextStyles.sans(
                      size: 11,
                      color: context.accent,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: context.accent),
          ],
        ),
      ),
    );
  }
}

// ── Activity tile ─────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final Session session;

  const _SessionTile({required this.session});

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/session/${session.id}', extra: session),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border2),
            ),
            child: const Center(
              child: Icon(
                Icons.sports_golf,
                size: 18,
                color: AppColors.textDimmed,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: AppTextStyles.sans(
                    size: 14,
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.shotCount} ${session.shotCount == 1 ? 'shot' : 'shots'} · ${_formatDate(session.createdAt)}',
                  style: AppTextStyles.sans(
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textDimmed,
          ),
        ],
      ),
    ),
    );
  }
}

// ── BLE connect chip ──────────────────────────────────────────────────────────

class _ConnectChip extends StatelessWidget {
  final LaunchMonitorStatus status;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ConnectChip({
    required this.status,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = status == LaunchMonitorStatus.scanning ||
        status == LaunchMonitorStatus.connecting;
    final isConnected = status == LaunchMonitorStatus.connected;

    return GestureDetector(
      onTap: isLoading ? null : (isConnected ? onDisconnect : onConnect),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusIndicator(status: status),
            const SizedBox(width: 6),
            Text(
              isLoading
                  ? (status == LaunchMonitorStatus.scanning
                      ? 'Scanning…'
                      : 'Connecting…')
                  : isConnected
                      ? 'Connected'
                      : 'Connect',
              style: AppTextStyles.sans(
                size: 12,
                color: isConnected ? context.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
