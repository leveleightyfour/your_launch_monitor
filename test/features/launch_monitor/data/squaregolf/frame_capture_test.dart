import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/frame_capture.dart';

List<String> _frame(String hex) => hex.split(' ');

/// A real-shaped ball frame: `11 02`, validity mask, then seven fields.
const _ballFrame17 =
    '11 02 3f 5c 1a 44 04 12 00 6a 0a 90 01 5e 0a 20 00';

void main() {
  setUp(FrameCapture.clear);

  group('recording', () {
    test('keeps frames verbatim, with their true length', () {
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      expect(FrameCapture.count, 1);
      expect(FrameCapture.report(), contains('11 02 3f 5c'));
      expect(FrameCapture.report(), contains('len= 17'));
    });

    test('rolls at the cap rather than growing without bound', () {
      for (var i = 0; i < 400; i++) {
        FrameCapture.record('status', _frame('11 03 00'));
      }

      expect(FrameCapture.count, 256);
    });

    test('clear empties it', () {
      FrameCapture.record('status', _frame('11 03 00'));
      FrameCapture.clear();

      expect(FrameCapture.count, 0);
      expect(FrameCapture.report(), contains('connect to the monitor'));
    });
  });

  group('spotting what we do not decode', () {
    test('a ball frame longer than the parser reads is flagged', () {
      // Four bytes of tail the 17-byte parser never touches. If the device
      // sends apex, this is one of the two places it can be.
      FrameCapture.record(
          'ballMetrics', _frame('$_ballFrame17 84 03 11 00'));

      expect(FrameCapture.undecoded, hasLength(1));
      expect(FrameCapture.undecoded.single.length, 21);
      expect(FrameCapture.report(), contains('1 frame(s) carrying data'));
    });

    test('an exactly-17-byte ball frame is not flagged', () {
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      expect(FrameCapture.undecoded, isEmpty);
      expect(FrameCapture.report(),
          contains('does not transmit apex'));
    });

    test('an unclassified frame kind is flagged whatever its length', () {
      // 11 05 and anything from 11 08 up are unaccounted for in `classify`.
      FrameCapture.record('unknown', _frame('11 05 aa bb'));

      expect(FrameCapture.undecoded, hasLength(1));
      expect(FrameCapture.report(), contains('unknown len=4'));
    });

    test('ordinary decoded frames are left out of the summary', () {
      FrameCapture.record('sensor', _frame('11 01 00 01 01'));
      FrameCapture.record('status', _frame('11 03 04'));
      FrameCapture.record('clubMetrics', _frame('11 07 00 01 02 03'));

      expect(FrameCapture.undecoded, isEmpty);
      // ...but they are still in the full listing, since timing matters.
      final report = FrameCapture.report();
      expect(report, contains('sensor'));
      expect(report, contains('clubMetrics'));
    });
  });

  group('the undecoded tail', () {
    test('a 23-byte ball frame yields three values, scaled and converted', () {
      // Three int16s past byte 16: 0x0bb8=3000, 0x5dc0=24000, 0x0898=2200 →
      // 30.00 m, 240.00 m, 22.00 m at the frame's ×100 scale.
      FrameCapture.record('ballMetrics',
          _frame('$_ballFrame17 b8 0b c0 5d 98 08'));

      final report = FrameCapture.report();
      expect(report, contains('3 value(s) past'));
      expect(report, contains('30.00m'));
      expect(report, contains('240.00m'));
      expect(report, contains('raw=3000'));
      // ...and the yard equivalent, since that is what the device displays.
      expect(report, contains('262.5y'));
    });

    test('a 17-byte frame has no tail and says nothing about one', () {
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      expect(FrameCapture.report(), isNot(contains('value(s) past')));
    });

    test('a trailing odd byte is not read as half a value', () {
      FrameCapture.record('ballMetrics', _frame('$_ballFrame17 b8 0b ff'));

      expect(FrameCapture.report(), contains('1 value(s) past'));
    });

    test('negative values sign-extend', () {
      // 0xffec = -20 → a roll-back, which a spinning wedge genuinely does.
      FrameCapture.record('ballMetrics', _frame('$_ballFrame17 ec ff'));

      expect(FrameCapture.report(), contains('raw=-20'));
    });
  });

  group('unmapped validity bits', () {
    // Byte 2 is the mask. 0x3f sets every bit the parsers actually use
    // (0x01|0x02|0x04|0x10|0x20 = 0x37) plus 0x08, which nothing reads.
    test('a spare bit set is reported as a field we do not read', () {
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      expect(FrameCapture.spareValidityBitsSeen, contains('bit3'));
      expect(FrameCapture.report(), contains('no parser reads'));
      expect(FrameCapture.report(), contains('should run to 23'));
    });

    test('a mask using only mapped bits reports nothing', () {
      // 0x37 = speed|totalSpin|axis|backspin|sidespin, all accounted for.
      FrameCapture.record('ballMetrics',
          _frame('11 02 37 5c 1a 44 04 12 00 6a 0a 90 01 5e 0a 20 00'));

      expect(FrameCapture.spareValidityBitsSeen, isEmpty);
      expect(FrameCapture.report(), isNot(contains('no parser reads')));
    });

    test('all three spare bits are distinguished', () {
      FrameCapture.record('ballMetrics',
          _frame('11 02 c8 5c 1a 44 04 12 00 6a 0a 90 01 5e 0a 20 00'));

      // 0xc8 = 0x80 | 0x40 | 0x08
      expect(FrameCapture.spareValidityBitsSeen,
          containsAll(<String>['bit3', 'bit6', 'bit7']));
    });

    test('club frames are not scanned for ball bits', () {
      FrameCapture.record('clubMetrics',
          _frame('11 07 ff 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f'));

      expect(FrameCapture.spareValidityBitsSeen, isEmpty);
    });
  });

  group('the GATT map', () {
    tearDown(() => FrameCapture.recordGatt(const []));

    test('a second notify characteristic is called out', () {
      // The one we listen on, plus one we do not. If the device publishes
      // flight data anywhere else, this is what shows it.
      FrameCapture.recordGatt(
        const [
          '86602102-6b7e-439a-bdd1-489a3213e9bb  [notify]',
          '86602104-6b7e-439a-bdd1-489a3213e9bb  [read,notify]',
        ],
        notifying: const ['86602104-6b7e-439a-bdd1-489a3213e9bb  [read,notify]'],
      );
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      final report = FrameCapture.report();
      expect(report, contains('--- characteristics ---'));
      expect(report, contains('1 characteristic(s) can notify'));
      expect(report, contains('86602104'));
    });

    test('nothing is claimed when only the known characteristic notifies', () {
      FrameCapture.recordGatt(
        const ['86602102-6b7e-439a-bdd1-489a3213e9bb  [notify]'],
      );
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      expect(FrameCapture.report(), isNot(contains('can notify')));
    });

    test('the section is omitted entirely before discovery runs', () {
      FrameCapture.record('status', _frame('11 03 00'));

      expect(FrameCapture.report(), isNot(contains('characteristics ---')));
    });
  });

  group('the report is self-describing', () {
    test('carries the device identity so a capture stands alone', () {
      FrameCapture.deviceType = 'omni';
      FrameCapture.osVersion = '1.7';
      FrameCapture.record('ballMetrics', _frame(_ballFrame17));

      final report = FrameCapture.report();
      expect(report, contains('device: omni'));
      expect(report, contains('os: 1.7'));
      expect(report, contains('frames: 1'));
    });

    test('says so when the version is not known yet', () {
      FrameCapture.deviceType = 'unknown';
      FrameCapture.osVersion = '';
      FrameCapture.record('status', _frame('11 03 00'));

      expect(FrameCapture.report(), contains('os: unknown'));
    });
  });
}
