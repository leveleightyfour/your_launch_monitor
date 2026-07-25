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
