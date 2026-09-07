import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/features/launch_monitor/application/shot_optimizer_providers.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_context.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

void main() {
  test(
    'background report preserves sources and groups without mixed averages',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const shot = ShotData(
        clubId: 'dr',
        ballSpeed: 140,
        clubSpeed: 100,
        spinRate: 2800,
        spinAxis: 0,
        launchAngle: 13,
        launchDirection: 0,
        context: ShotContext(
          ballSource: MeasurementSource.measured,
          clubSpeedSource: MeasurementSource.measured,
          intent: ShotIntent.stock,
        ),
      );
      final shots = [
        shot,
        shot.copyWith(
          context: shot.context.copyWith(
            intent: ShotIntent.partial,
            clubSpeedSource: MeasurementSource.estimated,
          ),
        ),
        shot.copyWith(context: const ShotContext()),
      ];
      final provider = optimizerReportProvider((
        shots: shots,
        clubs: Club.catalog,
      ));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final report = await container.read(provider.future);
      expect(report.analyses, hasLength(3));
      expect(report.analyses.last.assessed, isFalse);
      expect(report.summary!.assessedShots, 2);
      expect(report.summary!.groups, hasLength(2));
      expect(report.summary!.avgCarry, isNull);
      expect(report.summary!.groups.last.measuredSpeedCount, 0);
      expect(report.summary!.groups.last.avgSmash, isNull);
      expect(await container.read(provider.future), same(report));
    },
  );
}
