// Test vectors ported from squaregolf-connector
// (internal/core/parse_notifications_test.go).
//
// These verify that the Dart parser produces byte-for-byte identical results
// to the Go reference for every captured frame.

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/constants.dart';
import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/notifications.dart';

void main() {
  group('parseSensorData', () {
    test('insufficient data throws', () {
      expect(() => parseSensorData(['00', '01', '02']),
          throwsA(isA<ParseException>()));
    });

    test('ball ready and not detected', () {
      final r = parseSensorData([
        '00', '01', '02', '01', '00',
        '01', '00', '00', '00',
        '02', '00', '00', '00',
        '03', '00', '00', '00',
      ]);
      expect(r.ballReady, isTrue);
      expect(r.ballDetected, isFalse);
      expect(r.positionX, 1);
      expect(r.positionY, 2);
      expect(r.positionZ, 3);
    });

    test('ball ready (value 2) and detected', () {
      final r = parseSensorData([
        '00', '01', '02', '02', '01',
        '0A', '00', '00', '00',
        '14', '00', '00', '00',
        '1E', '00', '00', '00',
      ]);
      expect(r.ballReady, isTrue);
      expect(r.ballDetected, isTrue);
      expect(r.positionX, 10);
      expect(r.positionY, 20);
      expect(r.positionZ, 30);
    });

    test('ball not ready, all FF positions = -1', () {
      final r = parseSensorData([
        '00', '01', '02', '00', '00',
        'FF', 'FF', 'FF', 'FF',
        'FF', 'FF', 'FF', 'FF',
        'FF', 'FF', 'FF', 'FF',
      ]);
      expect(r.ballReady, isFalse);
      expect(r.ballDetected, isFalse);
      expect(r.positionX, -1);
      expect(r.positionY, -1);
      expect(r.positionZ, -1);
    });

    test('invalid hex for position X falls back to 0', () {
      final r = parseSensorData([
        '00', '01', '02', '01', '00',
        'ZZ', '00', '00', '00',
        '02', '00', '00', '00',
        '03', '00', '00', '00',
      ]);
      expect(r.positionX, 0);
      expect(r.positionY, 2);
      expect(r.positionZ, 3);
    });
  });

  group('parseShotBallMetrics', () {
    test('insufficient data throws', () {
      expect(() => parseShotBallMetrics(['00', '01', '02']),
          throwsA(isA<ParseException>()));
    });

    test('valid ball metrics', () {
      final r = parseShotBallMetrics([
        '11', '02', '37',
        '64', '00', // speed: 100 -> 1.00 m/s
        'C8', '00', // vertical: 200 -> 2.00°
        '2C', '01', // horizontal: 300 -> 3.00°
        'E8', '03', // total spin: 1000 rpm
        'F4', '01', // spin axis: 500 -> 5.00°
        'D0', '07', // backspin: 2000 rpm
        'B8', '0B', // sidespin: 3000 rpm
      ]);
      expect(r.ballSpeedMps, 1.0);
      expect(r.verticalAngle, 2.0);
      expect(r.horizontalAngle, 3.0);
      expect(r.totalSpinRpm, 1000);
      expect(r.spinAxis, 5.0);
      expect(r.backspinRpm, 2000);
      expect(r.sidespinRpm, 3000);
      expect(r.isBallSpeedValid, isTrue);
      expect(r.isTotalSpinValid, isTrue);
      expect(r.isSpinAxisValid, isTrue);
      expect(r.isBackspinValid, isTrue);
      expect(r.isSidespinValid, isTrue);
      expect(r.validityBitmask, '37');
    });

    test('negative values flip total spin sign when backspin is negative', () {
      final r = parseShotBallMetrics([
        '11', '02', '37',
        '9C', 'FF', // speed: -100 -> -1.00 m/s
        '38', 'FF', // vertical: -200
        'D4', 'FE', // horizontal: -300
        '18', 'FC', // total: -1000
        '0C', 'FE', // axis: -500
        '30', 'F8', // backspin: -2000
        '48', 'F4', // sidespin: -3000
      ]);
      expect(r.ballSpeedMps, -1.0);
      expect(r.verticalAngle, -2.0);
      expect(r.horizontalAngle, -3.0);
      // backspin is negative -> total spin is negated: -(-1000) = 1000
      expect(r.totalSpinRpm, 1000);
      expect(r.spinAxis, -5.0);
      expect(r.backspinRpm, -2000);
      expect(r.sidespinRpm, -3000);
    });

    test('invalid hex for ball speed marks invalid, leaves rest', () {
      final r = parseShotBallMetrics([
        '11', '02', '37',
        'ZZ', '00',
        'C8', '00',
        '2C', '01',
        'E8', '03',
        'F4', '01',
        'D0', '07',
        'B8', '0B',
      ]);
      expect(r.ballSpeedMps, 0);
      expect(r.isBallSpeedValid, isFalse);
      expect(r.verticalAngle, 2.0);
      expect(r.horizontalAngle, 3.0);
      expect(r.totalSpinRpm, 1000);
      expect(r.isTotalSpinValid, isTrue);
    });

    test('invalid backspin → decomposed from total spin × cos(axis)', () {
      final r = parseShotBallMetrics([
        '11', '02', '37',
        '64', '00',
        'C8', '00',
        '2C', '01',
        'E8', '03', // total: 1000
        'F4', '01', // axis: 5.00
        'ZZ', '07', // invalid backspin
        'B8', '0B', // sidespin: 3000
      ]);
      expect(r.isBackspinValid, isFalse);
      expect(r.backspinRpm, 996); // 1000 * cos(5°) truncated
      expect(r.sidespinRpm, 3000);
    });

    test('invalid sidespin → decomposed from total spin × sin(axis)', () {
      final r = parseShotBallMetrics([
        '11', '02', '37',
        '64', '00',
        'C8', '00',
        '2C', '01',
        'E8', '03',
        'F4', '01',
        'D0', '07', // backspin: 2000
        'ZZ', '0B', // invalid sidespin
      ]);
      expect(r.isSidespinValid, isFalse);
      expect(r.sidespinRpm, 87); // 1000 * sin(5°) truncated
    });

    test('sentinel sidespin (0x8000) normalises to zero and invalid', () {
      final r = parseShotBallMetrics([
        '11', '02', '37',
        '64', '00',
        'C8', '00',
        '2C', '01',
        'E8', '03',
        'F4', '01',
        'D0', '07',
        '00', '80', // sentinel -32768
      ]);
      expect(r.isSidespinValid, isFalse);
      expect(r.sidespinRpm, 87); // decomposed
    });

    test('short putt round-trip', () {
      final r = parseShotBallMetrics([
        '11', '02', '13',
        '6B', '00', // speed: 107 -> 1.07
        '00', '00',
        '42', '00', // horizontal: 0.66
        '4B', '00', // total spin: 75
        '00', '00',
        '00', '00',
        '00', '00',
      ]);
      expect(r.ballSpeedMps, 1.07);
      expect(r.verticalAngle, 0);
      expect(r.horizontalAngle, 0.66);
      expect(r.totalSpinRpm, 75);
      expect(r.validityBitmask, '13');
    });
  });

  group('parseShotClubMetrics (Home)', () {
    test('insufficient data throws', () {
      expect(() => parseShotClubMetrics(['00', '01', '02']),
          throwsA(isA<ParseException>()));
    });

    test('valid club metrics', () {
      final r = parseShotClubMetrics([
        '00', '01', '02',
        '64', '00', // path: 1.00
        'C8', '00', // face: 2.00
        '2C', '01', // attack: 3.00
        '90', '01', // loft: 4.00
      ]);
      expect(r.pathAngle, 1.0);
      expect(r.faceAngle, 2.0);
      expect(r.attackAngle, 3.0);
      expect(r.dynamicLoftAngle, 4.0);
      expect(r.isPathAngleValid, isTrue);
      expect(r.isFaceAngleValid, isTrue);
      expect(r.isAttackAngleValid, isTrue);
      expect(r.isDynamicLoftValid, isTrue);
    });

    test('negative values', () {
      final r = parseShotClubMetrics([
        '00', '01', '02',
        '9C', 'FF',
        '38', 'FF',
        'D4', 'FE',
        '70', 'FE',
      ]);
      expect(r.pathAngle, -1.0);
      expect(r.faceAngle, -2.0);
      expect(r.attackAngle, -3.0);
      expect(r.dynamicLoftAngle, -4.0);
    });

    test('sentinel path normalises to zero and invalid', () {
      final r = parseShotClubMetrics([
        '00', '01', '02',
        '00', '80', // sentinel
        'C8', '00',
        '2C', '01',
        '90', '01',
      ]);
      expect(r.pathAngle, 0);
      expect(r.isPathAngleValid, isFalse);
      expect(r.faceAngle, 2.0);
      expect(r.isFaceAngleValid, isTrue);
    });
  });

  group('parseOmniShotClubMetrics', () {
    test('insufficient data throws', () {
      expect(
          () => parseOmniShotClubMetrics(
              ['11', '07', 'ff', '00', '01', '00', '02']),
          throwsA(isA<ParseException>()));
    });

    test('all fields valid with bitmask 0xFF', () {
      final r = parseOmniShotClubMetrics([
        '11', '07', 'ff',
        'd8', 'fe', // path = -296 -> -2.96
        '90', '01', // face = 400 -> 4.00
        '38', 'ff', // attack = -200 -> -2.00
        'd0', '07', // loft = 2000 -> 20.00
        '64', '00', // impactH = 100 -> 1.00
        'c8', 'ff', // impactV = -56 -> -0.56
        'b8', '0b', // clubSpeed = 3000 -> 30.00
        '82', '00', // smash = 130 -> 1.30
      ]);
      expect(r.pathAngle, closeTo(-2.96, 1e-9));
      expect(r.faceAngle, 4.00);
      expect(r.attackAngle, -2.00);
      expect(r.dynamicLoftAngle, 20.00);
      expect(r.impactHorizontal, 1.00);
      expect(r.impactVertical, closeTo(-0.56, 1e-9));
      expect(r.clubSpeed, 30.00);
      expect(r.smashFactor, 1.30);
      expect(r.isPathAngleValid, isTrue);
      expect(r.isFaceAngleValid, isTrue);
      expect(r.isAttackAngleValid, isTrue);
      expect(r.isDynamicLoftValid, isTrue);
      expect(r.isImpactHorizontalValid, isTrue);
      expect(r.isImpactVerticalValid, isTrue);
      expect(r.isClubSpeedValid, isTrue);
      expect(r.isSmashFactorValid, isTrue);
    });

    test('partial bitmask 0x0F: first 4 valid, last 4 invalid', () {
      final r = parseOmniShotClubMetrics([
        '11', '07', '0f',
        'd8', 'fe', '90', '01', '38', 'ff', 'd0', '07',
        '64', '00', 'c8', 'ff', 'b8', '0b', '82', '00',
      ]);
      expect(r.isPathAngleValid, isTrue);
      expect(r.isFaceAngleValid, isTrue);
      expect(r.isAttackAngleValid, isTrue);
      expect(r.isDynamicLoftValid, isTrue);
      expect(r.isImpactHorizontalValid, isFalse);
      expect(r.isImpactVerticalValid, isFalse);
      expect(r.isClubSpeedValid, isFalse);
      expect(r.isSmashFactorValid, isFalse);
      // Values are still parsed:
      expect(r.impactHorizontal, 1.00);
      expect(r.clubSpeed, 30.00);
    });

    test('sentinel value overrides bitmask', () {
      final r = parseOmniShotClubMetrics([
        '11', '07', 'ff',
        '00', '80', // path = sentinel
        '90', '01', '38', 'ff', 'd0', '07',
        '64', '00', 'c8', 'ff', 'b8', '0b', '82', '00',
      ]);
      expect(r.pathAngle, 0);
      expect(r.isPathAngleValid, isFalse);
      expect(r.faceAngle, 4.00);
      expect(r.isFaceAngleValid, isTrue);
    });
  });

  group('applyOmniBallValidityBitmask', () {
    BallMetrics fakeMetrics({
      required String bitmask,
      bool ballSpeed = true,
      bool totalSpin = true,
      bool spinAxis = true,
      bool backspin = true,
      bool sidespin = true,
    }) =>
        BallMetrics(
          rawData: const [],
          ballSpeedMps: 0,
          verticalAngle: 0,
          horizontalAngle: 0,
          totalSpinRpm: 0,
          spinAxis: 0,
          backspinRpm: 0,
          sidespinRpm: 0,
          isBallSpeedValid: ballSpeed,
          isTotalSpinValid: totalSpin,
          isSpinAxisValid: spinAxis,
          isBackspinValid: backspin,
          isSidespinValid: sidespin,
          validityBitmask: bitmask,
        );

    test('empty bitmask leaves flags untouched', () {
      final r = applyOmniBallValidityBitmask(fakeMetrics(bitmask: ''));
      expect(r.isBallSpeedValid, isTrue);
      expect(r.isTotalSpinValid, isTrue);
    });

    test('bitmask 0x37 keeps speed/spin/axis/backspin/sidespin valid', () {
      // 0x37 = 0011 0111 → bits 0,1,2,4,5 set (matches validity bit layout)
      final r = applyOmniBallValidityBitmask(fakeMetrics(bitmask: '37'));
      expect(r.isBallSpeedValid, isTrue);
      expect(r.isTotalSpinValid, isTrue);
      expect(r.isSpinAxisValid, isTrue);
      expect(r.isBackspinValid, isTrue);
      expect(r.isSidespinValid, isTrue);
    });

    test('bitmask 0x00 invalidates everything', () {
      final r = applyOmniBallValidityBitmask(fakeMetrics(bitmask: '00'));
      expect(r.isBallSpeedValid, isFalse);
      expect(r.isTotalSpinValid, isFalse);
      expect(r.isSpinAxisValid, isFalse);
      expect(r.isBackspinValid, isFalse);
      expect(r.isSidespinValid, isFalse);
    });
  });

  group('parseAlignmentData', () {
    test('insufficient data throws', () {
      expect(() => parseAlignmentData(['00', '01', '02']),
          throwsA(isA<ParseException>()));
    });

    test('zero angle is aligned', () {
      final r = parseAlignmentData(
          ['11', '04', '00', '00', '00', '00', '00']);
      expect(r.aimAngle, 0);
      expect(r.isAligned, isTrue);
    });

    test('1.5° right is aligned (within ±2° threshold)', () {
      // 150 = 0x96 0x00
      final r = parseAlignmentData(
          ['11', '04', '00', '00', '00', '96', '00']);
      expect(r.aimAngle, 1.5);
      expect(r.isAligned, isTrue);
    });

    test('5° right is not aligned', () {
      // 500 = 0xF4 0x01
      final r = parseAlignmentData(
          ['11', '04', '00', '00', '00', 'F4', '01']);
      expect(r.aimAngle, 5.0);
      expect(r.isAligned, isFalse);
    });

    test('-3° (left) is not aligned', () {
      // -300 = 0xD4 0xFE
      final r = parseAlignmentData(
          ['11', '04', '00', '00', '00', 'D4', 'FE']);
      expect(r.aimAngle, -3.0);
      expect(r.isAligned, isFalse);
    });
  });

  group('detectDeviceType', () {
    test('empty data → home', () {
      expect(detectDeviceType(''), SquareGolfDeviceType.home);
    });

    test('non-matching → home', () {
      expect(detectDeviceType('aabbccddee'), SquareGolfDeviceType.home);
    });

    test('contains Omni identifier → omni', () {
      expect(detectDeviceType('some3033303041data'),
          SquareGolfDeviceType.omni);
    });

    test('exact Omni identifier → omni', () {
      expect(
          detectDeviceType(omniManufacturerDataHex), SquareGolfDeviceType.omni);
    });
  });

  group('classify', () {
    test('11 02 → ballMetrics', () {
      expect(classify(['11', '02', '00']), NotificationKind.ballMetrics);
    });
    test('11 07 → clubMetrics', () {
      expect(classify(['11', '07', '00']), NotificationKind.clubMetrics);
    });
    test('11 04 → alignment', () {
      expect(classify(['11', '04']), NotificationKind.alignment);
    });
    test('91 → battery', () {
      expect(classify(['91', '64']), NotificationKind.battery);
    });
    test('unknown header', () {
      expect(classify(['ff', '00']), NotificationKind.unknown);
    });
  });
}
