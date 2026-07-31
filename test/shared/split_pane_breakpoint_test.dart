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
Future<bool> _supports(
  WidgetTester tester,
  Size size, {
  double? availableWidth,
}) async {
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
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('a wide window gets the third pane without being ultra-wide', (
      tester,
    ) async {
      expect(await _supports(tester, const Size(1600, 1000)), isTrue);
    });

    testWidgets('a window dragged narrow folds back to two panes', (
      tester,
    ) async {
      expect(await _supports(tester, const Size(1000, 800)), isFalse);
    });
  });
}
