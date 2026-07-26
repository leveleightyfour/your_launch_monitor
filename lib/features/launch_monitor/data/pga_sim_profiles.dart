/// PGA Tour launch-parameter profiles for the test-shot generator.
///
/// Means follow the published TrackMan PGA Tour averages (driver → PW);
/// clubs outside that table (high woods, hybrids, gap/lob wedges, putter)
/// are interpolated to sit on the same ladder. Standard deviations model
/// tour-level shot-to-shot variation, so a run of simulated shots produces
/// realistic dispersion ellipses rather than a point cloud.
///
/// Only *inputs* are specified (speeds, launch, spin) — carry/total/offline
/// come out of [ShotTrajectory]'s physics like they do for real shots.
library;

import 'dart:math' as math;

import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';

/// Mean launch parameters for one club.
class PgaClubProfile {
  final double clubMph;
  final double ballMph;
  final double launchDeg;
  final double spinRpm;
  final double aoaDeg;
  final double apexYd;
  final double runYd;

  const PgaClubProfile(
    this.clubMph,
    this.ballMph,
    this.launchDeg,
    this.spinRpm,
    this.aoaDeg,
    this.apexYd,
    this.runYd,
  );
}

/// TrackMan PGA Tour averages, keyed by our club ids. Non-table clubs are
/// interpolated between their neighbours on the loft ladder.
const Map<String, PgaClubProfile> pgaProfiles = {
  // Drivers / woods                club   ball  launch  spin   AoA  apex run
  'dr':  PgaClubProfile(113, 167, 10.9, 2686, -1.3, 32, 7),
  'mdr': PgaClubProfile(110, 162, 10.5, 3100, -1.5, 31, 7),
  '2w':  PgaClubProfile(108, 160,  9.0, 3400, -2.5, 30, 7),
  '3w':  PgaClubProfile(107, 158,  9.2, 3655, -2.9, 30, 6),
  '4w':  PgaClubProfile(105, 155,  9.3, 4000, -3.1, 30, 6),
  '5w':  PgaClubProfile(103, 152,  9.4, 4350, -3.3, 31, 6),
  '6w':  PgaClubProfile(101, 149,  9.9, 4550, -3.4, 30, 6),
  '7w':  PgaClubProfile(100, 147, 10.4, 4750, -3.5, 30, 5),
  '9w':  PgaClubProfile( 98, 143, 11.2, 5200, -3.6, 30, 5),
  '11w': PgaClubProfile( 96, 139, 12.0, 5600, -3.7, 29, 5),
  // Hybrids
  '1h':  PgaClubProfile(102, 149,  9.8, 4300, -3.2, 29, 6),
  '2h':  PgaClubProfile(101, 147, 10.0, 4380, -3.4, 29, 6),
  '3h':  PgaClubProfile(100, 146, 10.2, 4437, -3.5, 29, 6),
  '4h':  PgaClubProfile( 98, 143, 10.8, 4600, -3.5, 29, 5),
  '5h':  PgaClubProfile( 96, 139, 11.4, 4900, -3.6, 29, 5),
  '6h':  PgaClubProfile( 94, 134, 12.6, 5500, -3.9, 30, 5),
  '7h':  PgaClubProfile( 92, 128, 14.0, 6200, -4.1, 30, 5),
  '8h':  PgaClubProfile( 89, 122, 15.8, 7000, -4.3, 31, 5),
  '9h':  PgaClubProfile( 87, 116, 17.8, 7800, -4.5, 31, 5),
  // Irons
  '1i':  PgaClubProfile( 99, 144, 10.0, 4500, -3.0, 27, 7),
  '2i':  PgaClubProfile( 98, 143, 10.2, 4560, -3.0, 27, 7),
  '3i':  PgaClubProfile( 98, 142, 10.4, 4630, -3.1, 27, 7),
  '4i':  PgaClubProfile( 96, 137, 11.0, 4836, -3.4, 28, 6),
  '5i':  PgaClubProfile( 94, 132, 12.1, 5361, -3.7, 31, 6),
  '6i':  PgaClubProfile( 92, 127, 14.1, 6231, -4.1, 30, 5),
  '7i':  PgaClubProfile( 90, 120, 16.3, 7097, -4.3, 32, 5),
  '8i':  PgaClubProfile( 87, 115, 18.1, 7998, -4.5, 31, 5),
  '9i':  PgaClubProfile( 85, 109, 20.4, 8647, -4.7, 30, 4),
  // Wedges
  'pw':    PgaClubProfile(83, 102, 24.2,  9304, -5.0, 29, 4),
  'gw':    PgaClubProfile(80,  95, 26.3,  9800, -5.1, 27, 3),
  '50deg': PgaClubProfile(80,  95, 26.3,  9800, -5.1, 27, 3),
  '52deg': PgaClubProfile(79,  93, 27.0, 10000, -5.2, 27, 3),
  '54deg': PgaClubProfile(78,  90, 28.0, 10200, -5.2, 26, 2),
  'sw':    PgaClubProfile(78,  88, 28.6, 10400, -5.3, 26, 2),
  '56deg': PgaClubProfile(77,  87, 29.2, 10500, -5.3, 25, 2),
  '58deg': PgaClubProfile(76,  84, 30.2, 10700, -5.4, 24, 2),
  'lw':    PgaClubProfile(75,  82, 31.0, 10800, -5.5, 23, 2),
  '60deg': PgaClubProfile(75,  82, 31.0, 10800, -5.5, 23, 2),
  '62deg': PgaClubProfile(74,  79, 32.0, 10900, -5.6, 22, 1),
  '64deg': PgaClubProfile(73,  76, 33.0, 11000, -5.6, 21, 1),
  // Putter — a ~15 ft putt; the trajectory model treats it as mostly roll.
  'pt': PgaClubProfile(4, 6, 0.5, 150, 0.0, 0, 10),
};

/// One gaussian sample (Box-Muller) with the given mean and SD.
double _gauss(math.Random rng, double mean, double sd) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  return mean + z * sd;
}

/// Generate a tour-realistic [ShotData] for [clubId].
///
/// Unknown ids fall back to the 7-iron profile (mid-bag). SDs scale with the
/// club: longer clubs get wider directional dispersion and tighter spin
/// variation, matching how tour dispersion actually behaves.
ShotData generatePgaTourShot(String? clubId, math.Random rng) {
  final p = pgaProfiles[clubId] ?? pgaProfiles['7i']!;
  final isPutter = clubId == 'pt';
  final isLong = p.ballMph > 150; // driver/woods territory

  if (isPutter) {
    return ShotData(
      clubId: clubId,
      ballSpeed: _gauss(rng, p.ballMph, 0.8).clamp(2.0, 12.0),
      spinRate: _gauss(rng, p.spinRpm, 40).clamp(50.0, 400.0),
      spinAxis: _gauss(rng, 0, 1.0),
      launchDirection: _gauss(rng, 0, 1.2),
      launchAngle: _gauss(rng, p.launchDeg, 0.3).clamp(0.0, 2.0),
      clubSpeed: _gauss(rng, p.clubMph, 0.5).clamp(1.0, 8.0),
      apex: 0,
      run: _gauss(rng, p.runYd, 2.5).clamp(1.0, 25.0),
    );
  }

  final launchSd = p.launchDeg < 13 ? 0.9 : 1.3;
  final spinSd = (p.spinRpm * 0.06).clamp(200.0, 650.0);
  final dirSd = isLong ? 2.2 : 1.8;
  final axisSd = isLong ? 2.5 : 2.0;

  final path = _gauss(rng, 0, 1.6);
  final face = _gauss(rng, 0, 1.0);

  return ShotData(
    clubId: clubId,
    ballSpeed: _gauss(rng, p.ballMph, math.max(1.2, p.ballMph * 0.011)),
    spinRate: _gauss(rng, p.spinRpm, spinSd).clamp(500.0, 13000.0),
    spinAxis: _gauss(rng, 0, axisSd),
    launchDirection: _gauss(rng, 0, dirSd),
    launchAngle:
        _gauss(rng, p.launchDeg, launchSd).clamp(3.0, 45.0),
    clubSpeed: _gauss(rng, p.clubMph, 1.0),
    apex: _gauss(rng, p.apexYd, 2.5).clamp(8.0, 60.0),
    run: _gauss(rng, p.runYd, isLong ? 3.0 : 2.0).clamp(0.0, 40.0),
    swingPath: path,
    faceAngle: face,
    angleOfAttack: _gauss(rng, p.aoaDeg, 0.7),
    dynamicLoft:
        _gauss(rng, p.launchDeg + (p.launchDeg < 13 ? 3.5 : 2.0), 1.0),
    horizontalImpact: _gauss(rng, 0, 4.0),
    verticalImpact: _gauss(rng, 0, 3.0),
  );
}
