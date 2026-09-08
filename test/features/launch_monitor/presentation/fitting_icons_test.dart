import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_context.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/fitting_panel.dart';
import 'package:omni_sniffer/features/launch_monitor/presentation/widgets/fitting_setup_dialog.dart';
import 'package:omni_sniffer/shared/app_icons.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// A Shorebird patch ships Dart only, so a Material glyph that a framework
/// widget draws by default (the dropdown arrow, the expansion chevron, the
/// chip delete icon) is missing from the release's tree-shaken icon font and
/// renders as a blank box on patched devices. The fitting UI is newer than the
/// current release, so every icon it draws has to come from [AppIcons].
final Finder materialGlyph = find.byWidgetPredicate(
  (w) => w is Icon && w.icon?.fontFamily == 'MaterialIcons',
  description: 'Icon drawn from the MaterialIcons font',
);

Widget host(Widget body) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.dark().copyWith(splashFactory: NoSplash.splashFactory),
    home: Scaffold(body: body),
  ),
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('expansion tiles draw a Lucide chevron, collapsed and expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SingleChildScrollView(
          child: Column(
            children: [
              FittingEquipmentDetails(
                baseline: EquipmentSetup(
                  name: 'A',
                  head: 'Head A',
                  shaft: 'Stiff',
                  loft: '9',
                  length: '45',
                ),
                candidate: EquipmentSetup(
                  name: 'B',
                  head: 'Head B',
                  shaft: 'X',
                  loft: '10.5',
                  length: '45.5',
                ),
              ),
              FittingEvidenceNote(),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(AppIcons.chevronDown), findsNWidgets(2));
    expect(materialGlyph, findsNothing);

    await tester.tap(find.text('TESTED EQUIPMENT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Head A'), findsOneWidget);
    expect(find.byIcon(AppIcons.chevronDown), findsNWidgets(2));
    expect(materialGlyph, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup dialog draws no Material glyph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        Builder(
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
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CLUB', findRichText: true), findsOneWidget);
    expect(find.text('Stock / full swing'), findsOneWidget);
    expect(materialGlyph, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
