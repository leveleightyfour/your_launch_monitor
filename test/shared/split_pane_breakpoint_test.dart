/// The split view's third pane is a desktop / ultra-wide affordance: it took
/// the width the fixed optimizer rail used to occupy, so it must not leak onto
/// a phone or a tablet in portrait, and it must fold away again the moment a
/// desktop window is dragged too narrow to divide three ways.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/shared/theme.dart';

/// Evaluates [supportsThirdSplitPane] under a pretend screen of [size], with
/// the split given the full width unless [availableWidth] says otherwise.
///
/// [platform] is applied only for the duration of the call: the test binding
/// verifies foundation debug variables are back to null before group-level
/// tearDowns run, so a setUp/tearDown pair can never hold the override.
Future<bool> _supports(
  WidgetTester tester,
  Size size, {
  double? availableWidth,
  TargetPlatform? platform,
}) async {
  if (platform != null) debugDefaultTargetPlatformOverride = platform;
  try {
    late bool result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            result = supportsThirdSplitPane(
              context,
              availableWidth ?? size.width,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  // Tests run as Android unless overridden, so these cover the ultra-wide
  // path on a non-desktop platform.
  group('non-desktop', () {
    testWidgets('ultra-wide display gets the third pane', (tester) async {
      expect(await _supports(tester, const Size(2560, 1080)), isTrue);
    });

    testWidgets('phone in landscape does not', (tester) async {
      // ~19.5:9 — wide enough in ratio, but shortestSide rules it out.
      expect(await _supports(tester, const Size(2340, 540)), isFalse);
    });

    testWidgets('tablet that is merely wide does not', (tester) async {
      // 16:10 iPad-class landscape: plenty of pixels, not ultra-wide.
      expect(await _supports(tester, const Size(1366, 1024)), isFalse);
    });

    testWidgets('a narrow ultra-wide still gets three panes', (tester) async {
      // Ultra-wide is three equal panes unconditionally — the aspect ratio
      // already proves the window is long, so the pinned shot list eating
      // into the split's width does not demote it back to two.
      expect(
        await _supports(
          tester,
          const Size(1140, 600),
          availableWidth: 860,
        ),
        isTrue,
      );
    });
  });

  group('desktop', () {
    testWidgets('a wide window gets the third pane without being ultra-wide', (
      tester,
    ) async {
      expect(
        await _supports(
          tester,
          const Size(1600, 1000),
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
    });

    testWidgets('a window dragged narrow folds back to two panes', (
      tester,
    ) async {
      expect(
        await _supports(
          tester,
          const Size(1000, 800),
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
    });
  });

  group('resolveSplitLayout on desktop', () {
    testWidgets('auto: ultra-wide keeps the three-pane strip', (tester) async {
      expect(
        await _resolve(tester, const Size(2560, 1080)),
        SplitLayoutMode.three,
      );
    });

    testWidgets('auto: a wide desktop keeps the strip', (tester) async {
      expect(
        await _resolve(tester, const Size(1920, 1080)),
        SplitLayoutMode.three,
      );
    });

    testWidgets(
      'auto: a 14" laptop fullscreen trades a cramped strip for the grid',
      (tester) async {
        // Three panes at ~500pt each are legal but squashed; two rows of
        // two ~750×390 panes are not.
        expect(
          await _resolve(
            tester,
            const Size(1512, 916),
            availableHeight: 780,
          ),
          SplitLayoutMode.grid,
        );
      },
    );

    testWidgets('auto: a window too short to stack folds to two', (
      tester,
    ) async {
      expect(
        await _resolve(tester, const Size(1400, 500)),
        SplitLayoutMode.two,
      );
    });

    testWidgets('auto: a small window folds to two', (tester) async {
      expect(
        await _resolve(tester, const Size(1000, 600)),
        SplitLayoutMode.two,
      );
    });

    testWidgets('explicit three folds to two when illegal', (tester) async {
      expect(
        await _resolve(
          tester,
          const Size(1000, 800),
          choice: SplitLayoutMode.three,
        ),
        SplitLayoutMode.two,
      );
    });

    testWidgets('explicit grid is honoured down to the legal floor', (
      tester,
    ) async {
      expect(
        await _resolve(
          tester,
          const Size(900, 700),
          choice: SplitLayoutMode.grid,
        ),
        SplitLayoutMode.grid,
      );
    });

    testWidgets('explicit grid folds to two when too short', (tester) async {
      expect(
        await _resolve(
          tester,
          const Size(800, 500),
          choice: SplitLayoutMode.grid,
        ),
        SplitLayoutMode.two,
      );
    });
  });
}

/// Evaluates [resolveSplitLayout] under a pretend screen of [size], with the
/// split given the full size unless the available overrides say otherwise.
/// Runs as macOS; see [_supports] for why the override is scoped this way.
Future<SplitLayoutMode> _resolve(
  WidgetTester tester,
  Size size, {
  SplitLayoutMode choice = SplitLayoutMode.auto,
  double? availableWidth,
  double? availableHeight,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    late SplitLayoutMode result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            result = resolveSplitLayout(
              choice,
              context,
              availableWidth ?? size.width,
              availableHeight ?? size.height,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
