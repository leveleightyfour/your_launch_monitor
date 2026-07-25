import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/log.dart';
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/notifications.dart';

List<String> _frame(String hex) => hex.split(' ');

/// A Home-length ball frame: `11 02`, mask, then the seven known fields.
const _ball17 = '11 02 37 5c 1a 44 04 12 00 6a 0a 90 01 5e 0a 20 00';

void main() {
  group('lmTailSummary', () {
    test('says nothing when there is no tail', () {
      expect(lmTailSummary(const []), '');
    });

    test('shows each value raw, in metres and in yards', () {
      // 3000 → 30.00 m → 32.8 y
      expect(lmTailSummary(const [3000]), ' TAIL[3000(30.00m/32.8y)]');
    });

    test('renders a full three-value tail in one line', () {
      final s = lmTailSummary(const [3000, 24000, 2200]);

      expect(s, contains('3000(30.00m/32.8y)'));
      expect(s, contains('24000(240.00m/262.5y)'));
      expect(s, contains('2200(22.00m/24.1y)'));
    });

    test('negatives survive — a wedge can spin back', () {
      expect(lmTailSummary(const [-250]), contains('-250(-2.50m/-2.7y)'));
    });
  });

  group('parseShotBallMetrics tail', () {
    test('a Home-length frame has no tail', () {
      expect(parseShotBallMetrics(_frame(_ball17)).tailInt16, isEmpty);
    });

    test('three trailing int16s are read little-endian and signed', () {
      // b8 0b = 3000, c0 5d = 24000, 98 08 = 2200
      final b = parseShotBallMetrics(_frame('$_ball17 b8 0b c0 5d 98 08'));

      expect(b.tailInt16, [3000, 24000, 2200]);
    });

    test('a dangling odd byte is not read as half a value', () {
      final b = parseShotBallMetrics(_frame('$_ball17 b8 0b ff'));

      expect(b.tailInt16, [3000]);
    });

    test('the known fields are untouched by the presence of a tail', () {
      final short = parseShotBallMetrics(_frame(_ball17));
      final long = parseShotBallMetrics(_frame('$_ball17 b8 0b c0 5d 98 08'));

      expect(long.ballSpeedMps, short.ballSpeedMps);
      expect(long.verticalAngle, short.verticalAngle);
      expect(long.horizontalAngle, short.horizontalAngle);
      expect(long.totalSpinRpm, short.totalSpinRpm);
      expect(long.spinAxis, short.spinAxis);
      expect(long.backspinRpm, short.backspinRpm);
      expect(long.sidespinRpm, short.sidespinRpm);
    });

    test('the tail survives the Omni validity bitmask pass', () {
      final b = applyOmniBallValidityBitmask(
        parseShotBallMetrics(_frame('$_ball17 b8 0b c0 5d 98 08')),
      );

      expect(b.tailInt16, [3000, 24000, 2200]);
    });
  });

  group('logging gate', () {
    tearDown(() => lmLoggingEnabled = false);

    test('can be switched on for a build that would otherwise stay silent', () {
      lmLoggingEnabled = false;
      expect(lmLoggingEnabled, isFalse);

      lmLoggingEnabled = true;
      expect(lmLoggingEnabled, isTrue);
    });
  });
}
