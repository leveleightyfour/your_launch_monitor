import 'package:flutter/material.dart';

import '../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../shared/theme.dart';
import '../../../../shared/widgets/app_controls.dart';
import '../../domain/entities/fitting_comparison.dart';

/// One round of a comparison: the verdict, the candidate's modelled gain in
/// the metric readout trio, and the A/B figures in a hairline table.
class FittingRoundView extends StatelessWidget {
  final String title;
  final FittingRound round;
  final UnitPrefs prefs;
  const FittingRoundView({
    super.key,
    required this.title,
    required this.round,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    String dist(double x) =>
        '${prefs.dist(x).toStringAsFixed(1)} ${prefs.distLabel}';
    final improvement = round.improvement;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionLabel(
            title,
            trailing:
                '${round.switches} ${round.switches == 1 ? 'switch' : 'switches'}',
          ),
          const SizedBox(height: 8),
          Text(
            round.message,
            style: AppTextStyles.sans(size: 13).copyWith(height: 1.45),
          ),
          const SizedBox(height: 2),
          Text(
            '${round.excluded} unverified or simulated shots excluded',
            style: AppTextStyles.sans(size: 11, color: AppColors.textDimmed),
          ),
          if (improvement != null) ...[
            const SizedBox(height: 14),
            const AppSectionLabel('Candidate improvement'),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${improvement >= 0 ? '+' : ''}${prefs.dist(improvement).toStringAsFixed(1)}',
                  style: AppTextStyles.statValue(size: 24),
                ),
                const SizedBox(width: 3),
                Text(prefs.distLabel, style: AppTextStyles.statUnit()),
                if (round.margin != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '± ${dist(round.margin!)}',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Approx. 95% sampling interval · simulated outcome',
              style: AppTextStyles.statUnit(),
            ),
          ],
          const SizedBox(height: 12),
          AppFiguresTable(
            columns: const ['Simulated outcome', 'A', 'B'],
            rows: [
              _row('Shots', (s) => '${s.count}'),
              _row('Mean carry', (s) => dist(s.carry)),
              _row('Carry SD', (s) => dist(s.carrySd)),
              _row('Mean absolute lateral miss', (s) => dist(s.absoluteOffline)),
              _row('Mean landing angle', (s) => '${s.descent.toStringAsFixed(1)}°'),
              _row(
                'Mean landing speed',
                (s) =>
                    '${prefs.spd(s.landingSpeed * 2.236936).toStringAsFixed(1)} ${prefs.speedLabel}',
              ),
              _row(
                'Mean landing spin',
                (s) => '${s.landingSpin.toStringAsFixed(0)} rpm',
              ),
              _row(
                'Meet chosen landing angle',
                (s) => '${(s.stoppingFraction * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _row(String title, String Function(FittingStats) value) => [
    title,
    round.baseline == null ? '—' : value(round.baseline!),
    round.candidate == null ? '—' : value(round.candidate!),
  ];
}
