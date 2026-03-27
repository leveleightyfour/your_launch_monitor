import 'package:omni_sniffer/features/launch_monitor/domain/entities/session.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

// ── Seed shots ────────────────────────────────────────────────────────────────
// Realistic values for a mid-handicap golfer (~12 hcp).
// launchDirection: negative = left, positive = right (dispersion key axis).

/// 25 driver shots — mild fade bias, ~250 yds avg carry, ±18 yd dispersion.
final List<ShotData> driverSeedShots = [
  _shot('dr', 158.2, 2540,  0.8,  2.4, 13.0, 106.4, apex: 35.2, run:  9.2, swingPath: -0.6, faceAngle:  1.8, aoa:  1.8, dynLoft: 14.1, hImp: -1.1, vImp:  2.0),
  _shot('dr', 152.3, 2780,  1.2,  1.8, 12.2, 103.4, apex: 32.0, run:  8.0, swingPath:  1.2, faceAngle:  0.8, aoa:  2.1, dynLoft: 13.8, hImp:  2.3, vImp:  1.4),
  _shot('dr', 145.6, 3020,  2.4, -1.2, 11.5,  99.1, apex: 29.5, run:  6.8, swingPath:  2.8, faceAngle:  2.1, aoa:  3.0, dynLoft: 12.9, hImp:  4.2, vImp: -0.8),
  _shot('dr', 161.4, 2610, -1.4,  2.1, 13.5, 108.8, apex: 36.8, run: 10.1, swingPath: -1.2, faceAngle: -0.4, aoa:  2.4, dynLoft: 14.6, hImp: -3.2, vImp:  3.1),
  _shot('dr', 154.9, 2720,  0.6, -0.3, 12.8, 104.8, apex: 33.4, run:  8.5, swingPath:  0.8, faceAngle:  0.5, aoa:  1.5, dynLoft: 13.4, hImp:  0.8, vImp:  0.6),
  _shot('dr', 149.2, 2890,  1.8,  1.4, 11.8, 101.0, apex: 30.2, run:  7.5, swingPath:  1.5, faceAngle:  1.4, aoa:  2.8, dynLoft: 13.0, hImp:  3.0, vImp: -1.5),
  _shot('dr', 163.8, 2490, -2.1, -0.8, 13.8, 110.4, apex: 38.0, run: 11.0, swingPath: -2.0, faceAngle: -1.2, aoa:  1.2, dynLoft: 15.0, hImp: -4.8, vImp:  2.8),
  _shot('dr', 156.5, 2650,  0.2,  1.0, 12.5, 105.9, apex: 34.1, run:  8.9, swingPath:  0.4, faceAngle:  0.9, aoa:  1.9, dynLoft: 13.7, hImp:  1.2, vImp:  1.8),
  _shot('dr', 147.4, 2960,  3.0, -1.8, 11.2, 100.2, apex: 28.8, run:  6.2, swingPath:  3.2, faceAngle:  2.8, aoa:  3.5, dynLoft: 12.5, hImp:  5.5, vImp: -2.2),
  _shot('dr', 159.7, 2580, -0.4,  1.6, 13.2, 107.6, apex: 36.2, run:  9.8, swingPath: -0.8, faceAngle:  0.0, aoa:  2.0, dynLoft: 14.3, hImp: -2.0, vImp:  2.5),
  _shot('dr', 153.6, 2700,  0.9,  0.5, 12.4, 104.0, apex: 32.8, run:  8.3, swingPath:  0.6, faceAngle:  0.7, aoa:  1.7, dynLoft: 13.5, hImp:  1.6, vImp:  0.9),
  _shot('dr', 160.8, 2555, -1.8,  3.2, 13.6, 108.2, apex: 37.4, run: 10.6, swingPath: -1.6, faceAngle: -0.2, aoa:  1.6, dynLoft: 14.8, hImp: -4.0, vImp:  3.4),
  _shot('dr', 144.2, 3100,  4.1, -2.6, 11.0,  97.8, apex: 27.6, run:  5.8, swingPath:  4.0, faceAngle:  3.4, aoa:  3.8, dynLoft: 12.2, hImp:  7.2, vImp: -2.8),
  _shot('dr', 157.0, 2630,  0.4,  1.2, 12.6, 106.0, apex: 34.6, run:  9.0, swingPath:  0.2, faceAngle:  0.8, aoa:  1.8, dynLoft: 13.9, hImp:  0.6, vImp:  1.5),
  _shot('dr', 150.4, 2840,  1.5, -0.6, 12.0, 102.2, apex: 31.0, run:  7.8, swingPath:  1.8, faceAngle:  1.0, aoa:  2.4, dynLoft: 13.2, hImp:  2.8, vImp: -0.4),
  _shot('dr', 165.2, 2460, -3.0, -1.0, 14.0, 111.2, apex: 38.8, run: 11.6, swingPath: -2.8, faceAngle: -1.8, aoa:  0.8, dynLoft: 15.4, hImp: -6.0, vImp:  3.0),
  _shot('dr', 155.8, 2680,  0.0,  2.0, 12.7, 105.4, apex: 33.8, run:  8.6, swingPath:  0.0, faceAngle:  1.0, aoa:  1.6, dynLoft: 13.6, hImp:  0.2, vImp:  2.2),
  _shot('dr', 148.8, 2910,  2.2,  0.8, 11.6, 100.8, apex: 29.8, run:  7.0, swingPath:  2.0, faceAngle:  1.8, aoa:  2.6, dynLoft: 12.8, hImp:  3.8, vImp: -0.6),
  _shot('dr', 162.4, 2520, -2.6,  1.4, 13.7, 109.6, apex: 37.6, run: 10.8, swingPath: -2.4, faceAngle: -1.0, aoa:  1.4, dynLoft: 14.9, hImp: -5.2, vImp:  2.6),
  _shot('dr', 151.0, 2760,  1.4, -0.2, 12.1, 102.6, apex: 31.6, run:  7.4, swingPath:  1.0, faceAngle:  1.2, aoa:  2.2, dynLoft: 13.1, hImp:  2.4, vImp: -0.2),
  _shot('dr', 157.8, 2600, -0.6,  1.8, 12.9, 106.8, apex: 35.0, run:  9.4, swingPath: -0.4, faceAngle:  0.4, aoa:  2.0, dynLoft: 14.0, hImp: -1.4, vImp:  2.0),
  _shot('dr', 146.0, 3000,  3.4, -2.0, 11.3,  98.6, apex: 28.2, run:  6.4, swingPath:  3.6, faceAngle:  2.6, aoa:  3.2, dynLoft: 12.6, hImp:  6.2, vImp: -1.8),
  _shot('dr', 160.0, 2570, -1.0,  2.6, 13.3, 107.8, apex: 36.6, run: 10.2, swingPath: -1.0, faceAngle: -0.2, aoa:  1.8, dynLoft: 14.5, hImp: -2.6, vImp:  2.8),
  _shot('dr', 153.2, 2730,  0.8,  0.2, 12.3, 103.8, apex: 32.4, run:  8.2, swingPath:  0.4, faceAngle:  0.6, aoa:  1.8, dynLoft: 13.3, hImp:  1.0, vImp:  0.8),
  _shot('dr', 158.6, 2560,  0.2,  1.4, 12.8, 107.0, apex: 35.4, run:  9.6, swingPath:  0.0, faceAngle:  0.6, aoa:  1.9, dynLoft: 14.2, hImp: -0.4, vImp:  1.6),
];

/// 25 seven-iron shots — descending attack, higher spin, mild pull bias.
final List<ShotData> sevenIronSeedShots = [
  _shot('7i', 116.2, 7120,  0.8,  1.2, 19.5,  80.4, apex: 28.0, run: 2.2, swingPath: -1.8, faceAngle: -0.6, aoa: -3.2, dynLoft: 21.0, hImp:  1.8, vImp:  0.4),
  _shot('7i', 120.8, 6840, -1.4,  0.6, 20.2,  83.1, apex: 30.2, run: 2.5, swingPath: -2.4, faceAngle: -1.2, aoa: -2.8, dynLoft: 22.1, hImp: -2.1, vImp:  1.2),
  _shot('7i', 112.4, 7480,  1.6, -0.8, 18.8,  78.2, apex: 26.5, run: 1.8, swingPath: -1.2, faceAngle:  0.4, aoa: -4.0, dynLoft: 20.2, hImp:  3.4, vImp: -1.0),
  _shot('7i', 118.6, 6980, -0.2,  1.4, 20.0,  81.8, apex: 29.1, run: 2.1, swingPath: -2.0, faceAngle: -0.8, aoa: -3.0, dynLoft: 21.5, hImp: -0.8, vImp:  0.8),
  _shot('7i', 122.1, 6700, -2.0, -0.4, 20.8,  84.5, apex: 31.4, run: 2.8, swingPath: -2.8, faceAngle: -1.8, aoa: -2.5, dynLoft: 22.8, hImp: -4.2, vImp:  1.5),
  _shot('7i', 114.0, 7350,  1.0,  0.2, 19.2,  79.0, apex: 27.2, run: 2.0, swingPath: -1.6, faceAngle: -0.2, aoa: -3.6, dynLoft: 20.8, hImp:  2.6, vImp: -0.4),
  _shot('7i', 119.4, 6900, -0.8,  1.8, 19.8,  82.4, apex: 29.6, run: 2.3, swingPath: -2.2, faceAngle: -1.0, aoa: -2.9, dynLoft: 21.8, hImp: -1.5, vImp:  1.0),
  _shot('7i', 115.8, 7200,  0.4, -0.2, 19.4,  80.1, apex: 27.8, run: 1.9, swingPath: -1.4, faceAngle:  0.2, aoa: -3.4, dynLoft: 21.2, hImp:  1.2, vImp: -0.6),
  _shot('7i', 117.6, 7060,  0.2,  1.0, 19.6,  81.0, apex: 28.4, run: 2.1, swingPath: -1.9, faceAngle: -0.5, aoa: -3.1, dynLoft: 21.3, hImp: -0.2, vImp:  0.6),
  _shot('7i', 121.2, 6770, -1.8,  0.2, 20.6,  83.8, apex: 30.8, run: 2.6, swingPath: -2.6, faceAngle: -1.6, aoa: -2.6, dynLoft: 22.5, hImp: -3.4, vImp:  1.3),
  _shot('7i', 113.2, 7420,  1.8, -0.6, 19.0,  78.6, apex: 26.8, run: 1.8, swingPath: -1.0, faceAngle:  0.6, aoa: -3.8, dynLoft: 20.4, hImp:  3.8, vImp: -0.8),
  _shot('7i', 119.8, 6940, -0.6,  1.6, 20.1,  82.0, apex: 29.4, run: 2.2, swingPath: -2.1, faceAngle: -0.9, aoa: -2.9, dynLoft: 21.6, hImp: -1.2, vImp:  0.9),
  _shot('7i', 116.8, 7080,  0.6,  0.8, 19.6,  80.6, apex: 28.2, run: 2.0, swingPath: -1.7, faceAngle: -0.3, aoa: -3.2, dynLoft: 21.1, hImp:  0.8, vImp:  0.5),
  _shot('7i', 123.4, 6620, -2.6, -0.6, 21.2,  85.4, apex: 32.2, run: 3.0, swingPath: -3.2, faceAngle: -2.2, aoa: -2.2, dynLoft: 23.4, hImp: -5.4, vImp:  1.8),
  _shot('7i', 110.8, 7680,  2.6, -1.4, 18.2,  76.6, apex: 24.8, run: 1.4, swingPath: -0.6, faceAngle:  1.4, aoa: -4.6, dynLoft: 19.4, hImp:  5.2, vImp: -1.4),
  _shot('7i', 118.0, 7020, -0.4,  1.2, 19.9,  81.4, apex: 29.0, run: 2.1, swingPath: -1.8, faceAngle: -0.6, aoa: -3.1, dynLoft: 21.4, hImp: -0.6, vImp:  0.7),
  _shot('7i', 115.0, 7280,  1.2,  0.0, 19.3,  79.4, apex: 27.4, run: 1.9, swingPath: -1.5, faceAngle:  0.0, aoa: -3.5, dynLoft: 21.0, hImp:  2.0, vImp: -0.5),
  _shot('7i', 120.2, 6870, -1.0,  1.4, 20.3,  83.0, apex: 30.4, run: 2.4, swingPath: -2.2, faceAngle: -1.0, aoa: -2.8, dynLoft: 22.2, hImp: -2.6, vImp:  1.1),
  _shot('7i', 114.6, 7310,  1.4, -0.4, 19.1,  79.2, apex: 27.0, run: 1.8, swingPath: -1.3, faceAngle:  0.3, aoa: -3.7, dynLoft: 20.6, hImp:  3.0, vImp: -0.7),
  _shot('7i', 117.2, 7090,  0.0,  1.0, 19.7,  80.8, apex: 28.6, run: 2.1, swingPath: -1.9, faceAngle: -0.4, aoa: -3.0, dynLoft: 21.3, hImp:  0.0, vImp:  0.6),
  _shot('7i', 121.8, 6730, -2.2,  0.0, 21.0,  84.2, apex: 31.8, run: 2.7, swingPath: -3.0, faceAngle: -1.9, aoa: -2.4, dynLoft: 23.0, hImp: -4.6, vImp:  1.4),
  _shot('7i', 113.8, 7390,  1.6, -0.8, 19.0,  78.8, apex: 26.6, run: 1.8, swingPath: -1.2, faceAngle:  0.5, aoa: -3.8, dynLoft: 20.5, hImp:  3.2, vImp: -0.9),
  _shot('7i', 118.4, 6960, -0.6,  1.6, 19.9,  81.6, apex: 29.2, run: 2.2, swingPath: -2.0, faceAngle: -0.8, aoa: -3.0, dynLoft: 21.6, hImp: -1.0, vImp:  0.8),
  _shot('7i', 116.4, 7110,  0.6,  0.6, 19.5,  80.2, apex: 28.0, run: 2.0, swingPath: -1.8, faceAngle: -0.2, aoa: -3.3, dynLoft: 21.1, hImp:  1.0, vImp:  0.4),
  _shot('7i', 119.0, 6920, -0.8,  1.4, 20.0,  82.2, apex: 29.4, run: 2.2, swingPath: -2.1, faceAngle: -0.9, aoa: -2.9, dynLoft: 21.7, hImp: -1.4, vImp:  1.0),
];

/// 20 mini driver shots.
final List<ShotData> miniDriverSeedShots = [
  _shot('mdr', 151.4, 2880,  0.4,  1.0, 13.4, 101.8, apex: 33.4, run: 8.2, swingPath:  0.6, faceAngle:  0.6, aoa:  1.4, dynLoft: 14.6, hImp:  1.0, vImp:  1.2),
  _shot('mdr', 155.8, 2660, -0.8,  0.6, 14.2, 104.6, apex: 36.0, run: 9.4, swingPath: -0.4, faceAngle:  0.0, aoa:  1.0, dynLoft: 15.4, hImp: -1.6, vImp:  2.0),
  _shot('mdr', 148.2, 3100,  1.6, -0.8, 12.8,  99.2, apex: 31.0, run: 7.2, swingPath:  1.4, faceAngle:  1.4, aoa:  2.0, dynLoft: 14.0, hImp:  3.6, vImp: -0.8),
  _shot('mdr', 153.0, 2780, -0.4,  1.4, 13.8, 102.8, apex: 34.2, run: 8.8, swingPath:  0.2, faceAngle:  0.4, aoa:  1.2, dynLoft: 15.0, hImp: -0.4, vImp:  1.4),
  _shot('mdr', 157.2, 2580, -1.8, -0.4, 14.6, 105.8, apex: 37.2, run:10.0, swingPath: -1.2, faceAngle: -0.8, aoa:  0.8, dynLoft: 15.8, hImp: -3.2, vImp:  2.4),
  _shot('mdr', 149.8, 2980,  0.8,  0.8, 13.2, 100.6, apex: 32.2, run: 7.8, swingPath:  0.4, faceAngle:  0.8, aoa:  1.6, dynLoft: 14.4, hImp:  1.8, vImp:  0.4),
  _shot('mdr', 152.2, 2830,  0.2,  1.2, 13.6, 102.4, apex: 33.8, run: 8.4, swingPath:  0.0, faceAngle:  0.6, aoa:  1.4, dynLoft: 14.8, hImp:  0.4, vImp:  1.2),
  _shot('mdr', 158.4, 2600, -2.2, -0.6, 14.8, 106.4, apex: 37.8, run:10.6, swingPath: -1.6, faceAngle: -1.2, aoa:  0.6, dynLoft: 16.2, hImp: -4.2, vImp:  2.6),
  _shot('mdr', 147.0, 3200,  2.4, -1.2, 12.4,  98.0, apex: 30.2, run: 6.8, swingPath:  2.0, faceAngle:  1.8, aoa:  2.4, dynLoft: 13.6, hImp:  5.0, vImp: -1.2),
  _shot('mdr', 154.6, 2720, -0.6,  1.8, 14.0, 103.8, apex: 35.2, run: 9.0, swingPath: -0.2, faceAngle:  0.2, aoa:  1.2, dynLoft: 15.2, hImp: -1.0, vImp:  1.6),
  _shot('mdr', 150.6, 2920,  1.0,  0.4, 13.0, 101.2, apex: 32.6, run: 7.6, swingPath:  0.8, faceAngle:  0.8, aoa:  1.8, dynLoft: 14.2, hImp:  1.6, vImp:  0.6),
  _shot('mdr', 156.0, 2640, -1.2,  0.2, 14.4, 105.0, apex: 36.6, run: 9.8, swingPath: -0.8, faceAngle: -0.4, aoa:  0.9, dynLoft: 15.6, hImp: -2.4, vImp:  2.2),
  _shot('mdr', 146.4, 3140,  2.0, -1.0, 12.6,  97.6, apex: 30.8, run: 7.0, swingPath:  1.6, faceAngle:  1.6, aoa:  2.2, dynLoft: 13.8, hImp:  4.2, vImp: -1.0),
  _shot('mdr', 153.8, 2760, -0.2,  1.4, 13.9, 103.2, apex: 34.8, run: 8.8, swingPath:  0.0, faceAngle:  0.4, aoa:  1.3, dynLoft: 15.1, hImp: -0.2, vImp:  1.5),
  _shot('mdr', 159.6, 2540, -2.8, -0.8, 15.0, 107.2, apex: 38.4, run:11.0, swingPath: -2.0, faceAngle: -1.6, aoa:  0.4, dynLoft: 16.4, hImp: -5.6, vImp:  2.8),
  _shot('mdr', 148.8, 3040,  1.4, -0.6, 12.9,  99.8, apex: 31.4, run: 7.4, swingPath:  1.2, faceAngle:  1.2, aoa:  1.8, dynLoft: 14.0, hImp:  2.8, vImp: -0.6),
  _shot('mdr', 155.2, 2700, -0.4,  1.6, 14.2, 104.2, apex: 35.6, run: 9.2, swingPath: -0.4, faceAngle:  0.2, aoa:  1.1, dynLoft: 15.3, hImp: -0.8, vImp:  1.8),
  _shot('mdr', 150.0, 2960,  0.6,  0.6, 13.2, 100.8, apex: 32.4, run: 7.8, swingPath:  0.4, faceAngle:  0.6, aoa:  1.6, dynLoft: 14.3, hImp:  1.2, vImp:  0.6),
  _shot('mdr', 157.4, 2620, -1.6, -0.2, 14.5, 106.0, apex: 37.4, run:10.2, swingPath: -1.0, faceAngle: -1.0, aoa:  0.8, dynLoft: 16.0, hImp: -3.6, vImp:  2.4),
  _shot('mdr', 152.8, 2800,  0.4,  1.0, 13.7, 102.6, apex: 33.6, run: 8.4, swingPath:  0.2, faceAngle:  0.5, aoa:  1.3, dynLoft: 14.9, hImp:  0.6, vImp:  1.2),
];

/// 20 three-wood shots.
final List<ShotData> threeWoodSeedShots = [
  _shot('3w', 146.2, 3380,  0.4,  1.0, 14.8,  98.8, apex: 30.5, run: 7.2, swingPath:  0.8, faceAngle:  0.4, aoa:  0.8, dynLoft: 16.2, hImp:  1.4, vImp:  0.9),
  _shot('3w', 150.4, 3140, -1.2,  0.2, 15.6, 101.4, apex: 33.0, run: 8.4, swingPath: -0.4, faceAngle: -0.2, aoa:  0.4, dynLoft: 17.1, hImp: -1.8, vImp:  1.6),
  _shot('3w', 143.8, 3560,  1.8, -0.8, 14.2,  96.5, apex: 28.8, run: 6.6, swingPath:  1.4, faceAngle:  1.2, aoa:  1.2, dynLoft: 15.8, hImp:  3.2, vImp: -0.6),
  _shot('3w', 148.1, 3260, -0.6,  1.4, 15.2,  99.8, apex: 31.4, run: 7.8, swingPath:  0.2, faceAngle:  0.6, aoa:  0.6, dynLoft: 16.8, hImp: -0.4, vImp:  1.2),
  _shot('3w', 152.0, 3080, -2.0, -0.4, 16.0, 102.6, apex: 34.2, run: 9.0, swingPath: -1.2, faceAngle: -0.8, aoa:  0.2, dynLoft: 17.5, hImp: -3.6, vImp:  2.0),
  _shot('3w', 145.0, 3440,  1.0,  0.6, 14.6,  97.8, apex: 29.6, run: 7.0, swingPath:  0.6, faceAngle:  0.8, aoa:  1.0, dynLoft: 16.0, hImp:  2.0, vImp:  0.4),
  _shot('3w', 147.4, 3320,  0.2,  1.2, 14.9,  99.2, apex: 30.8, run: 7.4, swingPath:  0.4, faceAngle:  0.4, aoa:  0.8, dynLoft: 16.4, hImp:  0.6, vImp:  1.0),
  _shot('3w', 153.2, 3020, -2.6, -0.6, 16.4, 103.4, apex: 35.0, run: 9.6, swingPath: -1.6, faceAngle: -1.2, aoa: -0.2, dynLoft: 18.0, hImp: -4.8, vImp:  2.2),
  _shot('3w', 141.6, 3680,  2.6, -1.2, 13.8,  95.2, apex: 27.4, run: 6.0, swingPath:  2.2, faceAngle:  1.8, aoa:  1.6, dynLoft: 15.2, hImp:  4.8, vImp: -1.0),
  _shot('3w', 149.2, 3200, -0.8,  1.8, 15.4, 100.4, apex: 32.2, run: 8.2, swingPath:  0.0, faceAngle:  0.2, aoa:  0.5, dynLoft: 17.0, hImp: -1.2, vImp:  1.4),
  _shot('3w', 144.6, 3480,  1.2, -0.2, 14.4,  97.2, apex: 29.2, run: 6.8, swingPath:  1.0, faceAngle:  1.0, aoa:  1.1, dynLoft: 15.9, hImp:  2.4, vImp: -0.2),
  _shot('3w', 150.8, 3100, -1.4,  0.6, 15.8, 101.8, apex: 33.6, run: 8.8, swingPath: -0.6, faceAngle: -0.4, aoa:  0.3, dynLoft: 17.3, hImp: -2.6, vImp:  1.8),
  _shot('3w', 146.8, 3360,  0.6,  0.8, 15.0,  98.6, apex: 30.4, run: 7.2, swingPath:  0.6, faceAngle:  0.6, aoa:  0.8, dynLoft: 16.3, hImp:  1.0, vImp:  0.8),
  _shot('3w', 154.4, 2980, -3.2, -0.8, 16.6, 104.2, apex: 35.8, run:10.2, swingPath: -2.2, faceAngle: -1.6, aoa: -0.4, dynLoft: 18.2, hImp: -6.0, vImp:  2.4),
  _shot('3w', 140.4, 3760,  3.2, -1.6, 13.6,  94.4, apex: 26.8, run: 5.6, swingPath:  2.8, faceAngle:  2.4, aoa:  2.0, dynLoft: 14.8, hImp:  6.0, vImp: -1.4),
  _shot('3w', 148.6, 3240, -0.4,  1.4, 15.3, 100.0, apex: 31.8, run: 8.0, swingPath:  0.2, faceAngle:  0.4, aoa:  0.6, dynLoft: 16.9, hImp: -0.6, vImp:  1.2),
  _shot('3w', 145.8, 3400,  0.8, -0.2, 14.7,  98.0, apex: 30.0, run: 7.0, swingPath:  0.8, faceAngle:  0.6, aoa:  0.9, dynLoft: 16.1, hImp:  1.6, vImp:  0.2),
  _shot('3w', 151.6, 3060, -1.8, -0.2, 15.9, 102.2, apex: 33.8, run: 8.6, swingPath: -0.8, faceAngle: -0.6, aoa:  0.2, dynLoft: 17.4, hImp: -3.2, vImp:  2.0),
  _shot('3w', 143.2, 3600,  2.0, -1.0, 14.0,  96.0, apex: 28.0, run: 6.4, swingPath:  1.6, faceAngle:  1.4, aoa:  1.4, dynLoft: 15.5, hImp:  3.8, vImp: -0.8),
  _shot('3w', 149.8, 3180, -0.2,  1.2, 15.4, 100.6, apex: 32.6, run: 8.2, swingPath:  0.0, faceAngle:  0.2, aoa:  0.6, dynLoft: 17.1, hImp: -0.4, vImp:  1.4),
];

/// 18 five-wood shots.
final List<ShotData> fiveWoodSeedShots = [
  _shot('5w', 140.4, 3820,  0.6,  1.2, 16.8,  94.2, apex: 31.8, run: 5.8, swingPath:  0.4, faceAngle:  0.6, aoa:  0.4, dynLoft: 18.4, hImp:  1.2, vImp:  0.8),
  _shot('5w', 144.8, 3580, -1.0,  0.4, 17.4,  97.0, apex: 34.0, run: 6.6, swingPath: -0.2, faceAngle:  0.0, aoa:  0.2, dynLoft: 19.2, hImp: -1.6, vImp:  1.4),
  _shot('5w', 137.2, 4060,  1.6, -0.6, 16.2,  91.6, apex: 29.4, run: 5.2, swingPath:  1.2, faceAngle:  1.0, aoa:  0.8, dynLoft: 17.8, hImp:  2.8, vImp: -0.4),
  _shot('5w', 142.0, 3720, -0.4,  1.0, 17.0,  95.4, apex: 32.6, run: 6.2, swingPath:  0.0, faceAngle:  0.4, aoa:  0.4, dynLoft: 18.8, hImp: -0.2, vImp:  1.0),
  _shot('5w', 146.2, 3460, -1.8, -0.2, 17.8,  98.2, apex: 35.2, run: 7.2, swingPath: -1.0, faceAngle: -0.6, aoa:  0.0, dynLoft: 19.8, hImp: -3.0, vImp:  1.8),
  _shot('5w', 138.8, 3940,  0.8,  0.8, 16.6,  93.0, apex: 30.6, run: 5.6, swingPath:  0.6, faceAngle:  0.8, aoa:  0.6, dynLoft: 18.2, hImp:  1.8, vImp:  0.2),
  _shot('5w', 141.6, 3760,  0.2,  1.0, 16.9,  94.8, apex: 32.0, run: 6.0, swingPath:  0.2, faceAngle:  0.6, aoa:  0.4, dynLoft: 18.6, hImp:  0.4, vImp:  0.8),
  _shot('5w', 147.4, 3400, -2.4, -0.4, 18.2,  99.0, apex: 35.8, run: 7.8, swingPath: -1.4, faceAngle: -1.0, aoa: -0.2, dynLoft: 20.2, hImp: -4.2, vImp:  2.0),
  _shot('5w', 136.0, 4160,  2.2, -1.0, 15.8,  90.8, apex: 28.2, run: 4.8, swingPath:  1.8, faceAngle:  1.4, aoa:  1.0, dynLoft: 17.4, hImp:  4.0, vImp: -0.8),
  _shot('5w', 143.2, 3660, -0.6,  1.4, 17.2,  96.2, apex: 33.4, run: 6.6, swingPath: -0.2, faceAngle:  0.2, aoa:  0.3, dynLoft: 19.0, hImp: -0.8, vImp:  1.2),
  _shot('5w', 139.6, 3880,  1.0,  0.2, 16.4,  93.6, apex: 30.8, run: 5.6, swingPath:  0.8, faceAngle:  0.6, aoa:  0.6, dynLoft: 18.0, hImp:  1.8, vImp:  0.0),
  _shot('5w', 145.0, 3520, -1.4,  0.6, 17.6,  97.6, apex: 34.6, run: 7.0, swingPath: -0.6, faceAngle: -0.2, aoa:  0.1, dynLoft: 19.5, hImp: -2.4, vImp:  1.6),
  _shot('5w', 140.0, 3800,  0.4,  0.8, 16.7,  94.0, apex: 31.4, run: 5.8, swingPath:  0.4, faceAngle:  0.6, aoa:  0.5, dynLoft: 18.3, hImp:  0.8, vImp:  0.6),
  _shot('5w', 148.6, 3340, -3.0, -0.6, 18.6,  99.8, apex: 36.4, run: 8.2, swingPath: -1.8, faceAngle: -1.4, aoa: -0.4, dynLoft: 20.6, hImp: -5.2, vImp:  2.2),
  _shot('5w', 135.0, 4240,  2.8, -1.4, 15.6,  90.0, apex: 27.6, run: 4.6, swingPath:  2.2, faceAngle:  2.0, aoa:  1.2, dynLoft: 17.2, hImp:  5.2, vImp: -1.2),
  _shot('5w', 142.8, 3680, -0.2,  1.2, 17.1,  95.8, apex: 33.0, run: 6.4, swingPath:  0.0, faceAngle:  0.4, aoa:  0.4, dynLoft: 18.9, hImp: -0.2, vImp:  1.0),
  _shot('5w', 138.2, 3960,  1.2, -0.2, 16.3,  92.4, apex: 29.8, run: 5.4, swingPath:  1.0, faceAngle:  0.8, aoa:  0.7, dynLoft: 17.9, hImp:  2.2, vImp: -0.2),
  _shot('5w', 144.4, 3600, -1.0,  0.8, 17.5,  97.2, apex: 34.2, run: 6.8, swingPath: -0.4, faceAngle: -0.2, aoa:  0.2, dynLoft: 19.3, hImp: -1.8, vImp:  1.4),
];

/// 18 hybrid (3h) shots.
final List<ShotData> hybridSeedShots = [
  _shot('3h', 132.4, 4620,  0.4,  0.8, 17.6,  88.8, apex: 29.2, run: 4.2, swingPath: -0.6, faceAngle:  0.2, aoa: -1.0, dynLoft: 19.8, hImp:  0.8, vImp:  0.6),
  _shot('3h', 136.8, 4380, -1.2,  0.4, 18.4,  91.4, apex: 31.6, run: 5.0, swingPath: -1.4, faceAngle: -0.6, aoa: -0.6, dynLoft: 20.8, hImp: -1.8, vImp:  1.2),
  _shot('3h', 128.6, 4900,  1.4, -0.6, 16.8,  86.2, apex: 27.0, run: 3.6, swingPath: -0.2, faceAngle:  0.8, aoa: -1.4, dynLoft: 18.8, hImp:  2.4, vImp: -0.8),
  _shot('3h', 134.0, 4500, -0.2,  1.2, 17.8,  89.8, apex: 30.2, run: 4.6, swingPath: -0.8, faceAngle: -0.4, aoa: -0.8, dynLoft: 20.2, hImp: -0.6, vImp:  0.8),
  _shot('3h', 138.2, 4260, -2.0, -0.4, 19.0,  92.6, apex: 33.0, run: 5.8, swingPath: -1.8, faceAngle: -1.2, aoa: -0.4, dynLoft: 21.4, hImp: -3.4, vImp:  1.6),
  _shot('3h', 130.4, 4760,  0.8,  0.6, 17.2,  87.4, apex: 28.2, run: 4.0, swingPath: -0.4, faceAngle:  0.4, aoa: -1.2, dynLoft: 19.4, hImp:  1.4, vImp:  0.2),
  _shot('3h', 133.2, 4560,  0.2,  1.0, 17.6,  89.2, apex: 29.8, run: 4.4, swingPath: -0.6, faceAngle:  0.0, aoa: -0.9, dynLoft: 20.0, hImp:  0.2, vImp:  0.6),
  _shot('3h', 139.4, 4200, -2.6, -0.6, 19.4,  93.4, apex: 33.6, run: 6.2, swingPath: -2.2, faceAngle: -1.6, aoa: -0.2, dynLoft: 21.8, hImp: -4.8, vImp:  1.8),
  _shot('3h', 127.0, 5060,  2.0, -1.0, 16.4,  85.0, apex: 26.0, run: 3.2, swingPath:  0.2, faceAngle:  1.2, aoa: -1.8, dynLoft: 18.2, hImp:  3.6, vImp: -1.0),
  _shot('3h', 135.4, 4440, -0.6,  1.4, 18.0,  90.4, apex: 31.0, run: 5.0, swingPath: -1.0, faceAngle: -0.2, aoa: -0.7, dynLoft: 20.4, hImp: -1.0, vImp:  1.0),
  _shot('3h', 131.2, 4700,  1.0,  0.2, 17.0,  88.0, apex: 28.6, run: 4.2, swingPath: -0.4, faceAngle:  0.6, aoa: -1.2, dynLoft: 19.6, hImp:  1.6, vImp: -0.2),
  _shot('3h', 137.0, 4320, -1.6,  0.2, 18.6,  91.8, apex: 32.4, run: 5.4, swingPath: -1.6, faceAngle: -0.8, aoa: -0.5, dynLoft: 21.0, hImp: -2.8, vImp:  1.4),
  _shot('3h', 132.8, 4580,  0.4,  0.8, 17.4,  89.0, apex: 29.4, run: 4.4, swingPath: -0.6, faceAngle:  0.2, aoa: -1.0, dynLoft: 19.9, hImp:  0.6, vImp:  0.6),
  _shot('3h', 140.0, 4160, -3.0, -0.8, 19.6,  94.0, apex: 34.0, run: 6.4, swingPath: -2.6, faceAngle: -1.8, aoa:  0.0, dynLoft: 22.0, hImp: -5.4, vImp:  2.0),
  _shot('3h', 126.2, 5120,  2.4, -1.2, 16.2,  84.4, apex: 25.4, run: 3.0, swingPath:  0.4, faceAngle:  1.6, aoa: -2.0, dynLoft: 18.0, hImp:  4.4, vImp: -1.2),
  _shot('3h', 134.6, 4480, -0.4,  1.2, 17.9,  90.0, apex: 30.6, run: 4.8, swingPath: -0.8, faceAngle: -0.2, aoa: -0.8, dynLoft: 20.3, hImp: -0.8, vImp:  0.9),
  _shot('3h', 129.8, 4820,  1.2, -0.4, 16.8,  87.0, apex: 27.6, run: 3.8, swingPath: -0.2, faceAngle:  0.8, aoa: -1.3, dynLoft: 19.1, hImp:  2.0, vImp: -0.6),
  _shot('3h', 136.2, 4360, -1.0,  1.0, 18.3,  91.0, apex: 32.0, run: 5.2, swingPath: -1.2, faceAngle: -0.6, aoa: -0.6, dynLoft: 20.7, hImp: -1.6, vImp:  1.2),
];

/// 20 four-iron shots.
final List<ShotData> fourIronSeedShots = [
  _shot('4i', 128.2, 5080,  0.6,  1.0, 18.4,  86.8, apex: 28.6, run: 3.8, swingPath: -0.8, faceAngle:  0.4, aoa: -1.8, dynLoft: 20.6, hImp:  1.2, vImp:  0.6),
  _shot('4i', 132.4, 4820, -1.4,  0.4, 19.2,  89.4, apex: 31.0, run: 4.4, swingPath: -1.6, faceAngle: -0.6, aoa: -1.4, dynLoft: 21.6, hImp: -2.0, vImp:  1.2),
  _shot('4i', 124.8, 5360,  1.8, -0.6, 17.8,  84.2, apex: 26.4, run: 3.2, swingPath: -0.4, faceAngle:  1.0, aoa: -2.2, dynLoft: 19.8, hImp:  3.0, vImp: -0.8),
  _shot('4i', 130.0, 4960, -0.2,  1.2, 18.8,  87.8, apex: 29.4, run: 4.0, swingPath: -1.0, faceAngle: -0.2, aoa: -1.6, dynLoft: 21.0, hImp: -0.8, vImp:  0.8),
  _shot('4i', 134.2, 4700, -2.2, -0.2, 19.8,  90.6, apex: 32.2, run: 4.8, swingPath: -2.0, faceAngle: -1.4, aoa: -1.0, dynLoft: 22.2, hImp: -4.0, vImp:  1.6),
  _shot('4i', 126.6, 5200,  0.8,  0.8, 18.2,  85.4, apex: 27.4, run: 3.4, swingPath: -0.6, faceAngle:  0.6, aoa: -2.0, dynLoft: 20.2, hImp:  2.0, vImp:  0.2),
  _shot('4i', 129.4, 5020,  0.4,  1.0, 18.6,  87.2, apex: 29.0, run: 4.0, swingPath: -0.8, faceAngle:  0.2, aoa: -1.7, dynLoft: 20.8, hImp:  0.6, vImp:  0.6),
  _shot('4i', 135.4, 4640, -2.8, -0.4, 20.2,  91.4, apex: 32.8, run: 5.2, swingPath: -2.4, faceAngle: -1.8, aoa: -0.8, dynLoft: 22.6, hImp: -5.2, vImp:  1.8),
  _shot('4i', 123.6, 5460,  2.4, -1.0, 17.4,  83.4, apex: 25.6, run: 2.8, swingPath:  0.0, faceAngle:  1.4, aoa: -2.6, dynLoft: 19.4, hImp:  4.4, vImp: -1.2),
  _shot('4i', 131.2, 4900, -0.6,  1.4, 19.0,  88.4, apex: 30.2, run: 4.2, swingPath: -1.2, faceAngle: -0.4, aoa: -1.5, dynLoft: 21.2, hImp: -1.4, vImp:  1.0),
  _shot('4i', 127.4, 5140,  1.0,  0.2, 18.0,  85.8, apex: 27.8, run: 3.4, swingPath: -0.6, faceAngle:  0.4, aoa: -2.0, dynLoft: 20.4, hImp:  1.6, vImp: -0.2),
  _shot('4i', 133.0, 4760, -1.8,  0.0, 19.6,  90.0, apex: 31.6, run: 4.6, swingPath: -1.8, faceAngle: -1.0, aoa: -1.2, dynLoft: 21.8, hImp: -3.2, vImp:  1.4),
  _shot('4i', 128.8, 5060,  0.6,  0.8, 18.4,  86.6, apex: 28.4, run: 3.8, swingPath: -0.8, faceAngle:  0.2, aoa: -1.8, dynLoft: 20.7, hImp:  1.0, vImp:  0.6),
  _shot('4i', 136.6, 4580, -3.4, -0.6, 20.6,  92.2, apex: 33.4, run: 5.6, swingPath: -2.8, faceAngle: -2.2, aoa: -0.6, dynLoft: 23.0, hImp: -6.2, vImp:  2.0),
  _shot('4i', 122.4, 5560,  3.0, -1.4, 17.0,  82.4, apex: 24.8, run: 2.4, swingPath:  0.4, faceAngle:  1.8, aoa: -3.0, dynLoft: 19.0, hImp:  5.6, vImp: -1.4),
  _shot('4i', 130.8, 4940, -0.4,  1.2, 18.9,  88.0, apex: 29.8, run: 4.2, swingPath: -1.0, faceAngle: -0.2, aoa: -1.6, dynLoft: 21.1, hImp: -1.0, vImp:  0.9),
  _shot('4i', 126.0, 5260,  1.4, -0.4, 17.8,  84.8, apex: 27.0, run: 3.2, swingPath: -0.4, faceAngle:  0.8, aoa: -2.1, dynLoft: 20.0, hImp:  2.6, vImp: -0.5),
  _shot('4i', 132.8, 4800, -1.2,  0.6, 19.4,  89.8, apex: 31.4, run: 4.6, swingPath: -1.4, faceAngle: -0.8, aoa: -1.3, dynLoft: 21.7, hImp: -2.2, vImp:  1.2),
  _shot('4i', 127.8, 5100,  0.8,  0.4, 18.2,  86.0, apex: 28.0, run: 3.6, swingPath: -0.6, faceAngle:  0.4, aoa: -1.9, dynLoft: 20.5, hImp:  1.4, vImp:  0.2),
  _shot('4i', 134.8, 4660, -2.4, -0.2, 20.0,  91.0, apex: 32.6, run: 5.0, swingPath: -2.2, faceAngle: -1.6, aoa: -0.9, dynLoft: 22.4, hImp: -4.6, vImp:  1.7),
];

/// 20 eight-iron shots.
final List<ShotData> eightIronSeedShots = [
  _shot('8i', 109.4, 7680,  0.6,  1.0, 21.8,  75.8, apex: 26.2, run: 1.6, swingPath: -2.0, faceAngle: -0.4, aoa: -4.0, dynLoft: 23.8, hImp:  1.4, vImp:  0.4),
  _shot('8i', 113.8, 7400, -1.2,  0.6, 22.6,  78.4, apex: 28.4, run: 1.8, swingPath: -2.6, faceAngle: -1.0, aoa: -3.6, dynLoft: 24.8, hImp: -1.8, vImp:  1.0),
  _shot('8i', 106.2, 7980,  1.4, -0.6, 21.2,  73.6, apex: 24.2, run: 1.2, swingPath: -1.6, faceAngle:  0.6, aoa: -4.6, dynLoft: 22.8, hImp:  2.8, vImp: -0.8),
  _shot('8i', 111.6, 7540, -0.2,  1.2, 22.2,  77.2, apex: 27.2, run: 1.6, swingPath: -2.2, faceAngle: -0.6, aoa: -3.8, dynLoft: 24.2, hImp: -0.6, vImp:  0.8),
  _shot('8i', 115.0, 7280, -1.8, -0.4, 23.0,  79.8, apex: 29.6, run: 2.0, swingPath: -2.8, faceAngle: -1.6, aoa: -3.2, dynLoft: 25.4, hImp: -3.6, vImp:  1.4),
  _shot('8i', 108.0, 7820,  0.8,  0.2, 21.4,  74.8, apex: 25.0, run: 1.4, swingPath: -1.8, faceAngle:  0.0, aoa: -4.2, dynLoft: 23.4, hImp:  1.8, vImp: -0.4),
  _shot('8i', 110.8, 7600,  0.2,  0.8, 22.0,  76.6, apex: 26.8, run: 1.6, swingPath: -2.0, faceAngle: -0.4, aoa: -3.9, dynLoft: 24.0, hImp:  0.2, vImp:  0.6),
  _shot('8i', 116.2, 7200, -2.4, -0.6, 23.4,  80.6, apex: 30.4, run: 2.2, swingPath: -3.2, faceAngle: -2.0, aoa: -2.8, dynLoft: 26.0, hImp: -4.8, vImp:  1.6),
  _shot('8i', 105.0, 8100,  2.0, -1.0, 20.8,  72.8, apex: 23.4, run: 1.0, swingPath: -1.2, faceAngle:  1.0, aoa: -5.0, dynLoft: 22.2, hImp:  3.8, vImp: -1.0),
  _shot('8i', 112.4, 7480, -0.6,  1.4, 22.4,  77.8, apex: 27.8, run: 1.8, swingPath: -2.4, faceAngle: -0.8, aoa: -3.7, dynLoft: 24.5, hImp: -1.2, vImp:  1.0),
  _shot('8i', 108.8, 7740,  1.0, -0.2, 21.6,  75.2, apex: 25.6, run: 1.4, swingPath: -1.8, faceAngle:  0.2, aoa: -4.1, dynLoft: 23.5, hImp:  2.0, vImp: -0.2),
  _shot('8i', 114.2, 7340, -1.4,  0.8, 22.8,  79.0, apex: 29.0, run: 1.9, swingPath: -2.6, faceAngle: -1.2, aoa: -3.4, dynLoft: 25.1, hImp: -2.6, vImp:  1.2),
  _shot('8i', 110.2, 7660,  0.4,  0.6, 21.9,  76.2, apex: 26.4, run: 1.6, swingPath: -2.0, faceAngle: -0.2, aoa: -3.9, dynLoft: 23.9, hImp:  0.6, vImp:  0.5),
  _shot('8i', 117.4, 7140, -3.0, -0.8, 23.8,  81.4, apex: 31.2, run: 2.4, swingPath: -3.6, faceAngle: -2.4, aoa: -2.6, dynLoft: 26.4, hImp: -5.8, vImp:  1.8),
  _shot('8i', 104.0, 8200,  2.6, -1.2, 20.4,  72.0, apex: 22.6, run: 0.8, swingPath: -0.8, faceAngle:  1.4, aoa: -5.4, dynLoft: 21.8, hImp:  5.0, vImp: -1.2),
  _shot('8i', 111.2, 7510, -0.4,  1.0, 22.1,  76.8, apex: 27.0, run: 1.6, swingPath: -2.1, faceAngle: -0.5, aoa: -3.8, dynLoft: 24.1, hImp: -0.8, vImp:  0.7),
  _shot('8i', 107.4, 7900,  1.2, -0.4, 21.0,  74.2, apex: 24.6, run: 1.2, swingPath: -1.6, faceAngle:  0.4, aoa: -4.4, dynLoft: 22.6, hImp:  2.2, vImp: -0.6),
  _shot('8i', 113.0, 7420, -1.0,  1.2, 22.5,  78.2, apex: 28.2, run: 1.8, swingPath: -2.4, faceAngle: -0.8, aoa: -3.6, dynLoft: 24.7, hImp: -1.6, vImp:  1.0),
  _shot('8i', 109.0, 7700,  0.6,  0.4, 21.7,  75.6, apex: 25.8, run: 1.5, swingPath: -1.9, faceAngle: -0.2, aoa: -4.0, dynLoft: 23.7, hImp:  1.0, vImp:  0.3),
  _shot('8i', 115.6, 7240, -2.0, -0.2, 23.2,  80.2, apex: 30.0, run: 2.0, swingPath: -3.0, faceAngle: -1.8, aoa: -3.0, dynLoft: 25.7, hImp: -4.0, vImp:  1.5),
];

/// 20 nine-iron shots.
final List<ShotData> nineIronSeedShots = [
  _shot('9i', 105.2, 8260,  0.4,  1.0, 24.2,  72.4, apex: 25.6, run: 1.2, swingPath: -2.2, faceAngle: -0.2, aoa: -4.8, dynLoft: 26.4, hImp:  1.0, vImp:  0.4),
  _shot('9i', 109.4, 7980, -1.0,  0.4, 25.0,  75.0, apex: 27.6, run: 1.4, swingPath: -2.8, faceAngle: -0.8, aoa: -4.2, dynLoft: 27.4, hImp: -1.6, vImp:  1.0),
  _shot('9i', 102.0, 8560,  1.2, -0.4, 23.4,  70.2, apex: 23.8, run: 0.8, swingPath: -1.8, faceAngle:  0.4, aoa: -5.4, dynLoft: 25.4, hImp:  2.4, vImp: -0.6),
  _shot('9i', 107.4, 8120, -0.2,  1.2, 24.6,  73.6, apex: 26.4, run: 1.2, swingPath: -2.4, faceAngle: -0.4, aoa: -4.4, dynLoft: 26.8, hImp: -0.4, vImp:  0.6),
  _shot('9i', 111.0, 7840, -1.6, -0.2, 25.6,  76.4, apex: 28.8, run: 1.6, swingPath: -3.0, faceAngle: -1.4, aoa: -3.8, dynLoft: 28.0, hImp: -3.2, vImp:  1.2),
  _shot('9i', 103.8, 8400,  0.6,  0.8, 23.8,  71.4, apex: 24.6, run: 1.0, swingPath: -2.0, faceAngle:  0.2, aoa: -5.0, dynLoft: 25.8, hImp:  1.4, vImp: -0.2),
  _shot('9i', 106.4, 8200,  0.2,  1.0, 24.4,  73.0, apex: 26.0, run: 1.2, swingPath: -2.2, faceAngle: -0.2, aoa: -4.6, dynLoft: 26.6, hImp:  0.2, vImp:  0.5),
  _shot('9i', 112.2, 7780, -2.0, -0.4, 26.0,  77.2, apex: 29.4, run: 1.8, swingPath: -3.4, faceAngle: -1.8, aoa: -3.6, dynLoft: 28.4, hImp: -4.0, vImp:  1.4),
  _shot('9i', 100.8, 8700,  1.6, -0.6, 23.0,  69.4, apex: 23.0, run: 0.6, swingPath: -1.4, faceAngle:  0.8, aoa: -5.8, dynLoft: 25.0, hImp:  3.2, vImp: -0.8),
  _shot('9i', 108.2, 8060, -0.4,  1.4, 24.8,  74.2, apex: 27.2, run: 1.4, swingPath: -2.6, faceAngle: -0.6, aoa: -4.3, dynLoft: 27.1, hImp: -0.8, vImp:  0.8),
  _shot('9i', 104.6, 8320,  0.8,  0.4, 23.6,  71.8, apex: 24.8, run: 1.0, swingPath: -2.0, faceAngle:  0.2, aoa: -5.0, dynLoft: 25.6, hImp:  1.6, vImp: -0.2),
  _shot('9i', 110.2, 7900, -1.2,  0.6, 25.4,  75.8, apex: 28.2, run: 1.6, swingPath: -2.8, faceAngle: -1.2, aoa: -4.0, dynLoft: 27.7, hImp: -2.4, vImp:  1.1),
  _shot('9i', 105.8, 8180,  0.4,  0.8, 24.2,  72.6, apex: 25.8, run: 1.2, swingPath: -2.2, faceAngle: -0.2, aoa: -4.7, dynLoft: 26.5, hImp:  0.6, vImp:  0.4),
  _shot('9i', 113.4, 7720, -2.4, -0.6, 26.4,  78.0, apex: 30.0, run: 2.0, swingPath: -3.6, faceAngle: -2.0, aoa: -3.4, dynLoft: 28.8, hImp: -4.8, vImp:  1.6),
  _shot('9i', 100.0, 8820,  2.0, -0.8, 22.8,  68.8, apex: 22.4, run: 0.6, swingPath: -1.2, faceAngle:  1.0, aoa: -6.0, dynLoft: 24.8, hImp:  4.0, vImp: -1.0),
  _shot('9i', 107.8, 8080, -0.2,  1.2, 24.6,  73.8, apex: 26.8, run: 1.4, swingPath: -2.4, faceAngle: -0.4, aoa: -4.4, dynLoft: 26.9, hImp: -0.4, vImp:  0.7),
  _shot('9i', 103.2, 8480,  1.0, -0.2, 23.2,  70.8, apex: 24.2, run: 0.8, swingPath: -1.8, faceAngle:  0.4, aoa: -5.2, dynLoft: 25.2, hImp:  2.0, vImp: -0.4),
  _shot('9i', 109.8, 7960, -0.8,  1.0, 25.2,  75.4, apex: 28.0, run: 1.5, swingPath: -2.8, faceAngle: -1.0, aoa: -4.1, dynLoft: 27.5, hImp: -1.6, vImp:  0.9),
  _shot('9i', 105.4, 8240,  0.4,  0.6, 24.2,  72.4, apex: 25.6, run: 1.1, swingPath: -2.2, faceAngle: -0.1, aoa: -4.8, dynLoft: 26.4, hImp:  0.8, vImp:  0.4),
  _shot('9i', 111.6, 7820, -1.8, -0.2, 25.8,  76.8, apex: 29.2, run: 1.7, swingPath: -3.2, faceAngle: -1.6, aoa: -3.7, dynLoft: 28.2, hImp: -3.6, vImp:  1.3),
];

/// 20 pitching wedge shots.
final List<ShotData> pwSeedShots = [
  _shot('pw', 100.4, 8980,  0.4,  0.8, 27.4,  69.2, apex: 24.8, run: 0.8, swingPath: -2.4, faceAngle: -0.2, aoa: -5.6, dynLoft: 29.8, hImp:  0.8, vImp:  0.4),
  _shot('pw', 104.2, 8680, -0.8,  0.4, 28.2,  71.8, apex: 26.4, run: 1.0, swingPath: -3.0, faceAngle: -0.6, aoa: -5.0, dynLoft: 30.8, hImp: -1.4, vImp:  0.8),
  _shot('pw',  97.4, 9320,  1.2, -0.4, 26.8,  67.0, apex: 23.0, run: 0.6, swingPath: -2.0, faceAngle:  0.4, aoa: -6.2, dynLoft: 28.8, hImp:  2.0, vImp: -0.6),
  _shot('pw', 102.0, 8840, -0.2,  1.0, 27.8,  70.4, apex: 25.6, run: 0.8, swingPath: -2.6, faceAngle: -0.4, aoa: -5.4, dynLoft: 30.2, hImp: -0.2, vImp:  0.6),
  _shot('pw', 105.8, 8520, -1.4, -0.2, 28.8,  73.0, apex: 27.6, run: 1.2, swingPath: -3.4, faceAngle: -1.0, aoa: -4.6, dynLoft: 31.4, hImp: -2.8, vImp:  1.0),
  _shot('pw',  99.0, 9100,  0.6,  0.6, 27.2,  68.2, apex: 24.0, run: 0.6, swingPath: -2.2, faceAngle:  0.2, aoa: -5.8, dynLoft: 29.4, hImp:  1.2, vImp: -0.2),
  _shot('pw', 101.2, 8910,  0.2,  0.8, 27.6,  69.8, apex: 25.2, run: 0.8, swingPath: -2.4, faceAngle: -0.2, aoa: -5.4, dynLoft: 30.0, hImp:  0.2, vImp:  0.5),
  _shot('pw', 106.8, 8440, -1.8, -0.4, 29.2,  73.8, apex: 28.2, run: 1.4, swingPath: -3.6, faceAngle: -1.4, aoa: -4.4, dynLoft: 31.8, hImp: -3.6, vImp:  1.2),
  _shot('pw',  96.2, 9460,  1.6, -0.6, 26.4,  66.2, apex: 22.2, run: 0.4, swingPath: -1.6, faceAngle:  0.8, aoa: -6.6, dynLoft: 28.4, hImp:  3.0, vImp: -0.8),
  _shot('pw', 103.0, 8760, -0.4,  1.2, 28.0,  71.0, apex: 26.0, run: 1.0, swingPath: -2.8, faceAngle: -0.6, aoa: -5.2, dynLoft: 30.4, hImp: -0.6, vImp:  0.8),
  _shot('pw', 100.8, 8950,  0.4,  0.6, 27.4,  69.4, apex: 24.6, run: 0.8, swingPath: -2.4, faceAngle: -0.1, aoa: -5.6, dynLoft: 29.9, hImp:  0.6, vImp:  0.4),
  _shot('pw', 107.6, 8380, -2.2, -0.6, 29.6,  74.6, apex: 28.8, run: 1.6, swingPath: -3.8, faceAngle: -1.8, aoa: -4.2, dynLoft: 32.2, hImp: -4.4, vImp:  1.4),
  _shot('pw',  95.0, 9600,  2.0, -0.8, 26.0,  65.4, apex: 21.6, run: 0.4, swingPath: -1.4, faceAngle:  1.0, aoa: -7.0, dynLoft: 28.0, hImp:  3.8, vImp: -1.0),
  _shot('pw', 102.6, 8800, -0.2,  1.0, 27.8,  70.8, apex: 25.8, run: 0.9, swingPath: -2.6, faceAngle: -0.4, aoa: -5.3, dynLoft: 30.3, hImp: -0.4, vImp:  0.7),
  _shot('pw',  98.2, 9180,  0.8, -0.2, 27.0,  67.6, apex: 23.4, run: 0.6, swingPath: -2.0, faceAngle:  0.2, aoa: -6.0, dynLoft: 29.1, hImp:  1.6, vImp: -0.3),
  _shot('pw', 104.8, 8600, -1.0,  0.6, 28.4,  72.4, apex: 27.0, run: 1.1, swingPath: -3.0, faceAngle: -0.8, aoa: -4.8, dynLoft: 31.0, hImp: -2.0, vImp:  0.9),
  _shot('pw', 100.0, 9020,  0.4,  0.8, 27.4,  69.0, apex: 24.8, run: 0.7, swingPath: -2.4, faceAngle: -0.2, aoa: -5.6, dynLoft: 29.8, hImp:  0.8, vImp:  0.4),
  _shot('pw', 108.4, 8320, -2.6, -0.8, 30.0,  75.4, apex: 29.4, run: 1.8, swingPath: -4.0, faceAngle: -2.0, aoa: -4.0, dynLoft: 32.6, hImp: -5.2, vImp:  1.6),
  _shot('pw',  94.0, 9740,  2.4, -1.0, 25.6,  64.6, apex: 21.0, run: 0.2, swingPath: -1.2, faceAngle:  1.2, aoa: -7.4, dynLoft: 27.6, hImp:  4.6, vImp: -1.2),
  _shot('pw', 101.6, 8870, -0.2,  0.8, 27.6,  70.0, apex: 25.2, run: 0.8, swingPath: -2.5, faceAngle: -0.3, aoa: -5.4, dynLoft: 30.1, hImp: -0.2, vImp:  0.6),
];

/// 18 sand wedge shots.
final List<ShotData> swSeedShots = [
  _shot('sw',  88.4, 10240,  0.4,  0.6, 32.8,  61.2, apex: 22.4, run: 0.4, swingPath: -2.8, faceAngle:  0.0, aoa: -7.2, dynLoft: 35.4, hImp:  0.6, vImp:  0.4),
  _shot('sw',  92.0,  9960, -0.8,  0.4, 33.6,  63.8, apex: 23.8, run: 0.6, swingPath: -3.4, faceAngle: -0.4, aoa: -6.6, dynLoft: 36.4, hImp: -1.2, vImp:  0.8),
  _shot('sw',  85.6, 10560,  1.0, -0.4, 32.2,  59.0, apex: 21.2, run: 0.4, swingPath: -2.2, faceAngle:  0.6, aoa: -7.8, dynLoft: 34.6, hImp:  1.8, vImp: -0.6),
  _shot('sw',  90.2, 10100, -0.2,  0.8, 33.2,  62.4, apex: 23.0, run: 0.4, swingPath: -3.0, faceAngle: -0.2, aoa: -6.8, dynLoft: 35.8, hImp: -0.4, vImp:  0.6),
  _shot('sw',  93.8,  9780, -1.2, -0.2, 34.4,  65.0, apex: 24.8, run: 0.8, swingPath: -3.8, faceAngle: -0.8, aoa: -6.2, dynLoft: 37.0, hImp: -2.4, vImp:  1.0),
  _shot('sw',  87.0, 10380,  0.6,  0.6, 32.6,  60.2, apex: 21.8, run: 0.4, swingPath: -2.6, faceAngle:  0.4, aoa: -7.4, dynLoft: 35.0, hImp:  1.0, vImp: -0.2),
  _shot('sw',  89.4, 10180,  0.2,  0.6, 33.0,  61.8, apex: 22.6, run: 0.4, swingPath: -2.8, faceAngle: -0.1, aoa: -7.0, dynLoft: 35.6, hImp:  0.2, vImp:  0.5),
  _shot('sw',  94.8,  9680, -1.6, -0.4, 34.8,  65.8, apex: 25.4, run: 0.9, swingPath: -4.0, faceAngle: -1.2, aoa: -5.8, dynLoft: 37.4, hImp: -3.2, vImp:  1.2),
  _shot('sw',  84.4, 10720,  1.4, -0.6, 31.8,  58.2, apex: 20.6, run: 0.2, swingPath: -1.8, faceAngle:  0.8, aoa: -8.2, dynLoft: 34.2, hImp:  2.6, vImp: -0.8),
  _shot('sw',  91.0, 10040, -0.4,  1.0, 33.4,  63.0, apex: 23.4, run: 0.6, swingPath: -3.2, faceAngle: -0.3, aoa: -6.7, dynLoft: 36.1, hImp: -0.8, vImp:  0.7),
  _shot('sw',  88.0, 10300,  0.6,  0.4, 32.6,  60.8, apex: 22.2, run: 0.4, swingPath: -2.6, faceAngle:  0.2, aoa: -7.2, dynLoft: 35.2, hImp:  1.0, vImp:  0.2),
  _shot('sw',  95.6,  9600, -2.0, -0.6, 35.2,  66.4, apex: 26.0, run: 1.0, swingPath: -4.4, faceAngle: -1.6, aoa: -5.6, dynLoft: 37.8, hImp: -4.0, vImp:  1.4),
  _shot('sw',  83.4, 10880,  1.8, -0.8, 31.4,  57.4, apex: 20.0, run: 0.2, swingPath: -1.6, faceAngle:  1.0, aoa: -8.6, dynLoft: 33.8, hImp:  3.4, vImp: -1.0),
  _shot('sw',  91.6,  9980, -0.2,  0.8, 33.6,  63.4, apex: 23.6, run: 0.5, swingPath: -3.1, faceAngle: -0.2, aoa: -6.6, dynLoft: 36.2, hImp: -0.6, vImp:  0.8),
  _shot('sw',  86.2, 10480,  0.8, -0.2, 32.2,  59.6, apex: 21.4, run: 0.3, swingPath: -2.4, faceAngle:  0.5, aoa: -7.6, dynLoft: 34.7, hImp:  1.4, vImp: -0.4),
  _shot('sw',  92.8,  9860, -0.8,  0.4, 34.0,  64.2, apex: 24.2, run: 0.7, swingPath: -3.4, faceAngle: -0.6, aoa: -6.4, dynLoft: 36.7, hImp: -1.6, vImp:  0.9),
  _shot('sw',  89.8, 10120,  0.4,  0.6, 33.1,  62.0, apex: 22.8, run: 0.4, swingPath: -2.9, faceAngle: -0.1, aoa: -6.9, dynLoft: 35.7, hImp:  0.4, vImp:  0.5),
  _shot('sw',  96.4,  9520, -2.4, -0.8, 35.6,  67.0, apex: 26.6, run: 1.1, swingPath: -4.6, faceAngle: -2.0, aoa: -5.4, dynLoft: 38.2, hImp: -4.8, vImp:  1.6),
];

/// Pre-seeded past sessions for the session list.
final List<Session> seedSessions = [
  Session(
    id: 'session_001',
    name: 'Range Session',
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
    shots: [
      ...driverSeedShots,
      ...threeWoodSeedShots,
      ...sevenIronSeedShots,
      ...pwSeedShots,
    ],
  ),
  Session(
    id: 'session_002',
    name: 'Driver & Fairway',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
    shots: [
      ...driverSeedShots.take(15),
      ...miniDriverSeedShots.take(12),
      ...threeWoodSeedShots.take(12),
    ],
  ),
  Session(
    id: 'session_003',
    name: 'Iron Work',
    createdAt: DateTime.now().subtract(const Duration(days: 7)),
    shots: [
      ...fourIronSeedShots,
      ...sevenIronSeedShots,
      ...eightIronSeedShots,
      ...nineIronSeedShots,
    ],
  ),
  Session(
    id: 'session_004',
    name: 'Wedge Practice',
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
    shots: [...pwSeedShots, ...swSeedShots],
  ),
];

/// Active session — 20 shots per club so dispersion painter can be debugged.
final List<ShotData> activeSeedShots = [
  ...driverSeedShots,
  ...miniDriverSeedShots,
  ...threeWoodSeedShots.take(12),
  ...fiveWoodSeedShots.take(12),
  ...hybridSeedShots.take(12),
  ...fourIronSeedShots.take(15),
  ...sevenIronSeedShots,
  ...eightIronSeedShots.take(15),
  ...nineIronSeedShots.take(15),
  ...pwSeedShots,
  ...swSeedShots.take(12),
];

// ── Helper ────────────────────────────────────────────────────────────────────

ShotData _shot(
  String clubId,
  double ballSpeed,
  double spinRate,
  double spinAxis,
  double launchDirection,
  double launchAngle,
  double clubSpeed, {
  double? apex,
  double? run,
  double? swingPath,
  double? faceAngle,
  double? aoa,
  double? dynLoft,
  double? hImp,
  double? vImp,
}) {
  return ShotData(
    clubId: clubId,
    ballSpeed: ballSpeed,
    spinRate: spinRate,
    spinAxis: spinAxis,
    launchDirection: launchDirection,
    launchAngle: launchAngle,
    clubSpeed: clubSpeed,
    apex: apex,
    run: run,
    swingPath: swingPath,
    faceAngle: faceAngle,
    angleOfAttack: aoa,
    dynamicLoft: dynLoft,
    horizontalImpact: hImp,
    verticalImpact: vImp,
  );
}
