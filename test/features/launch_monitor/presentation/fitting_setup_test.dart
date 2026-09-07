import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/fitting_setup_dialog.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('comparison validates and retains inputs at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => FittingSetupDialog(
                      clubs: Club.catalog,
                      prefs: const UnitPrefs(),
                      draftKey: (id: 'stable', clubId: 'dr', unitScale: 1),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Check the highlighted fields to continue.'),
        findsOneWidget,
      );
      final conditions = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key == const ValueKey('conditions'),
      );
      await tester.ensureVisible(conditions);
      await tester.enterText(conditions, 'Same ball, tee and room');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Baseline setup'), findsOneWidget);
      await tester.tap(find.text('Previous step'));
      await tester.pumpAndSettle();
      expect(find.text('Same ball, tee and room'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
