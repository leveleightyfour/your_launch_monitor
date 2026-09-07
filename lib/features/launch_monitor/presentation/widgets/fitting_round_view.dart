import 'package:flutter/material.dart';

import '../../../../shared/providers/unit_prefs_provider.dart';
import '../../../../shared/theme.dart';
import '../../domain/entities/fitting_comparison.dart';

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
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.subHeading()),
          Text(round.message, style: AppTextStyles.body()),
          Text(
            '${round.excluded} unverified or simulated shots excluded · ${round.switches} setup switches',
            style: AppTextStyles.caption(color: AppColors.textMuted),
          ),
          if (round.improvement != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CANDIDATE IMPROVEMENT',
                    style: AppTextStyles.statLabel(),
                  ),
                  Text(
                    '${dist(round.improvement!)} ± ${dist(round.margin!)}',
                    style: AppTextStyles.statValue(size: 24),
                  ),
                  Text(
                    'Approx. 95% sampling interval · simulated outcome',
                    style: AppTextStyles.statUnit(),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: AppTextStyles.label(),
              dataTextStyle: AppTextStyles.body(),
              headingRowColor: const WidgetStatePropertyAll(AppColors.card),
              columns: const [
                DataColumn(label: Text('Simulated outcome')),
                DataColumn(label: Text('A')),
                DataColumn(label: Text('B')),
              ],
              rows: [
                _row('Shots', (s) => '${s.count}'),
                _row('Mean carry', (s) => dist(s.carry)),
                _row('Carry SD', (s) => dist(s.carrySd)),
                _row(
                  'Mean absolute lateral miss',
                  (s) => dist(s.absoluteOffline),
                ),
                _row(
                  'Mean landing angle',
                  (s) => '${s.descent.toStringAsFixed(1)}°',
                ),
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
          ),
        ],
      ),
    );
  }

  DataRow _row(String title, String Function(FittingStats) value) => DataRow(
    cells: [
      DataCell(Text(title)),
      DataCell(Text(round.baseline == null ? '—' : value(round.baseline!))),
      DataCell(Text(round.candidate == null ? '—' : value(round.candidate!))),
    ],
  );
}
