import 'package:flutter/material.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/shared/theme.dart';
import 'package:omni_sniffer/shared/app_icons.dart';

// The end-of-session flow — finish confirm, summary sheet and the active-club
// picker — shared by both session screens so classic and rethink close a
// bucket through exactly the same doors.

// ── Step 1: confirm dialog ─────────────────────────────────────────────────────

/// Two-stage finish dialog. Stage one offers the save path, a leave-and-
/// resume-later path, and abandonment; choosing "Abandon Session" swaps to
/// an explicit red confirm naming exactly what is destroyed, so one stray
/// tap can never delete a session.
class FinishConfirmDialog extends StatefulWidget {
  final int shotCount;
  final VoidCallback onFinish;
  final VoidCallback onLeave;
  final VoidCallback onAbandon;
  final VoidCallback onNevermind;

  const FinishConfirmDialog({
    super.key,
    required this.shotCount,
    required this.onFinish,
    required this.onLeave,
    required this.onAbandon,
    required this.onNevermind,
  });

  @override
  State<FinishConfirmDialog> createState() => _FinishConfirmDialogState();
}

class _FinishConfirmDialogState extends State<FinishConfirmDialog> {
  bool _confirmingAbandon = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.shotCount;
    final shotsWord = count == 1 ? 'shot' : 'shots';
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _confirmingAbandon
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Abandon Session?',
                    style: AppTextStyles.sans(
                      size: 17,
                      weight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This deletes all $count $shotsWord. '
                    'It cannot be undone.',
                    style: AppTextStyles.sans(
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.errorBackground,
                        foregroundColor: AppColors.errorText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppColors.errorText),
                        ),
                      ),
                      onPressed: widget.onAbandon,
                      child: Text(
                        'Delete $count $shotsWord',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: AppColors.errorText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.onNevermind,
                      child: Text(
                        'Keep Session',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Finish Session?',
                    style: AppTextStyles.sans(
                      size: 17,
                      weight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$count $shotsWord recorded. Leaving keeps the session '
                    'active so you can return to it from the home screen.',
                    style: AppTextStyles.sans(
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.onFinish,
                      child: Text(
                        'Continue to Summary',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.border2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.onLeave,
                      child: Text(
                        'Leave for Now',
                        style: AppTextStyles.sans(
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: AppColors.border2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () =>
                          setState(() => _confirmingAbandon = true),
                      child: Text(
                        'Abandon Session',
                        style: AppTextStyles.sans(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onNevermind,
                    child: Text(
                      'Nevermind',
                      style: AppTextStyles.sans(color: AppColors.textDimmed),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Step 2: session summary sheet ─────────────────────────────────────────────

class SessionSummarySheet extends StatelessWidget {
  final List<ShotData> allShots;
  final List<Club> clubs;
  final String? initialName;
  final ValueChanged<String> onSave;

  const SessionSummarySheet({
    super.key,
    required this.allShots,
    required this.clubs,
    this.initialName,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final sessionName = initialName ?? 'Session - $dateStr';

    final clubCounts = <String, int>{};
    for (final s in allShots) {
      if (s.clubId != null) {
        clubCounts[s.clubId!] = (clubCounts[s.clubId!] ?? 0) + 1;
      }
    }
    final clubsUsed = clubs.where((c) => clubCounts.containsKey(c.id)).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session Summary',
                    style: AppTextStyles.sans(
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${allShots.length}',
                                style: AppTextStyles.mono(size: 28),
                              ),
                              Text(
                                'shots',
                                style: AppTextStyles.sans(
                                  size: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${clubsUsed.length}',
                                style: AppTextStyles.mono(size: 28),
                              ),
                              Text(
                                'clubs',
                                style: AppTextStyles.sans(
                                  size: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (clubsUsed.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Clubs Used',
                      style: AppTextStyles.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...clubsUsed.map(
                      (club) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: club.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              club.shortName,
                              style: AppTextStyles.sans(size: 13),
                            ),
                            const Spacer(),
                            Text(
                              '${clubCounts[club.id]} '
                              '${(clubCounts[club.id] ?? 0) == 1 ? 'shot' : 'shots'}',
                              style: AppTextStyles.sans(
                                size: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => onSave(sessionName),
                      child: Text(
                        'Save & Finish',
                        style: AppTextStyles.sans(
                          size: 15,
                          weight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Club picker sheet ──────────────────────────────────────────────────────────

/// Sort key for the active-club picker.
///
/// Groups (driver → mini → woods → hybrids → irons → wedges → putter), then
/// sorts within each group by the leading number / loft so 3w comes before
/// 5w, 4i before 7i, and 52° before 60°.
int _clubSortKey(Club c) {
  const int dr = 0;
  const int mini = 100;
  const int wood = 200;
  const int hybrid = 300;
  const int iron = 400;
  const int wedge = 500;
  const int putter = 999;

  if (c.id == 'dr') return dr;
  if (c.id == 'mdr') return mini;

  // Pull a numeric sub-key from the id (e.g. "3w" → 3, "52deg" → 52, "7i" → 7).
  final m = RegExp(r'(\d+)').firstMatch(c.id);
  final n = m == null ? 99 : int.tryParse(m.group(1)!) ?? 99;

  return switch (c.type) {
    ClubType.wood => wood + n,
    ClubType.miniDriver => mini,
    ClubType.hybrid => hybrid + n,
    ClubType.iron => iron + n,
    ClubType.wedge => wedge + _wedgeSubKey(c.id, n),
    ClubType.putter => putter,
  };
}

/// Named wedges (PW/GW/SW/LW) get fixed slots before any degree-marked wedges
/// so the picker reads pw → gw → sw → lw → 50° → 52° … in the wedge group.
int _wedgeSubKey(String id, int extractedNumber) {
  switch (id.toLowerCase()) {
    case 'pw':
      return 1;
    case 'gw':
      return 2;
    case 'sw':
      return 3;
    case 'lw':
      return 4;
    default:
      return 100 + extractedNumber;
  }
}

class ClubPickerSheet extends StatelessWidget {
  final List<Club> clubs;
  final Club? selected;
  final ValueChanged<Club> onSelect;

  const ClubPickerSheet({
    super.key,
    required this.clubs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...clubs]
      ..sort((a, b) => _clubSortKey(a).compareTo(_clubSortKey(b)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Active Club',
            style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: sorted.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final club = sorted[i];
              final isSelected = club.id == selected?.id;
              return ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: club.color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  club.shortName,
                  style: AppTextStyles.sans(
                    size: 14,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? context.accent : Colors.white,
                  ),
                ),
                subtitle: club.manufacturer != null || club.model != null
                    ? Text(
                        [
                          if (club.manufacturer != null) club.manufacturer!,
                          if (club.model != null) club.model!,
                        ].join(' · '),
                        style: AppTextStyles.sans(
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                      )
                    : null,
                trailing: isSelected
                    ? Icon(AppIcons.check, color: context.accent, size: 18)
                    : null,
                tileColor: Colors.transparent,
                onTap: () => onSelect(club),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
