import 'package:flutter/material.dart';

import '../../../../shared/theme.dart';
import '../../domain/entities/shot_context.dart';

/// One tested setup: its A/B tag in the accent badge the optimizer uses for
/// recommendation priority, then name and spec lines. The sheet's equipment
/// section and the setup dialog's review step share it so a setup reads the
/// same on both.
class FittingSetupRow extends StatelessWidget {
  final String tag;
  final String name;
  final List<String> details;

  const FittingSetupRow({
    super.key,
    required this.tag,
    required this.name,
    required this.details,
  });

  FittingSetupRow.fromSetup(EquipmentSetup setup, {super.key, required this.tag})
    : name = setup.name,
      details = [
        [setup.head, setup.shaft].where((s) => s.isNotEmpty).join(' · '),
        [
          if (setup.loft.isNotEmpty) 'Loft ${setup.loft}',
          if (setup.length.isNotEmpty) 'Length ${setup.length}',
        ].join(' · '),
        setup.notes,
      ].where((s) => s.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.accentSubtle,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tag,
            style: AppTextStyles.sans(
              size: 12,
              weight: FontWeight.w700,
              color: context.accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  name.isEmpty ? '—' : name,
                  style: AppTextStyles.sans(size: 13, weight: FontWeight.w600),
                ),
              ),
              for (final line in details)
                Text(
                  line,
                  style: AppTextStyles.sans(
                    size: 12,
                    color: AppColors.textMuted,
                  ).copyWith(height: 1.4),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
