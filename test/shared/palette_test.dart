/// The app draws club colours and the user's accent colour side by side —
/// a club's dispersion ellipse next to accent-coloured markers, a flight trace
/// under an accent-coloured landing ring, filter chips against a selected
/// chip. If a club colour lands on an accent, or on another club in the same
/// bag, the view stops being readable.
///
/// These invariants are measured, not eyeballed. Distances are CIE76 ΔE in
/// L*a*b*: ~2.3 is a just-noticeable difference, ~10 reads as a different
/// colour, and the floors below are set well above that.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/shared/providers/accent_color_provider.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/terrain.dart';
import 'package:omni_sniffer/shared/theme.dart';

/// No club may be confusable with any accent the user can pick.
const _accentFloor = 20.0;

/// No two clubs in the default bag may be confusable with each other.
const _bagFloor = 15.0;

/// Across the whole catalog, where a player might combine anything.
const _catalogFloor = 12.0;

/// Every colour has to read against the app's near-black background.
const _backgroundFloor = 30.0;

(double, double, double) _lab(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  final r = channel(c.r * 255);
  final g = channel(c.g * 255);
  final b = channel(c.b * 255);

  final x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;

  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3) as double : 7.787 * t + 16 / 116;

  final fx = f(x), fy = f(y), fz = f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double _deltaE(Color a, Color b) {
  final (l1, a1, b1) = _lab(a);
  final (l2, a2, b2) = _lab(b);
  final dl = l1 - l2, da = a1 - a2, db = b1 - b2;
  return math.sqrt(dl * dl + da * da + db * db);
}

/// WCAG relative luminance — how bright the surface actually is, which is the
/// axis the mown bands live or die on.
double _relLuminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

String _hex(Color c) =>
    '#${((c.a * 255).round() << 24 | (c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void main() {
  final catalog = Club.catalog;
  final accents = appAccentSwatches.map((s) => s.color).toList();

  test('the catalog has no duplicate ids', () {
    final ids = catalog.map((c) => c.id).toList();

    expect(ids.toSet().length, ids.length);
  });

  test('no club shares a colour with another club', () {
    final byColour = <int, List<String>>{};
    for (final club in catalog) {
      byColour.putIfAbsent(club.color.toARGB32(), () => []).add(club.id);
    }
    final shared = byColour.entries.where((e) => e.value.length > 1);

    expect(
      shared,
      isEmpty,
      reason: 'colours shared by several clubs: '
          '${shared.map((e) => '${e.value} all ${e.key.toRadixString(16)}').join('; ')}',
    );
  });

  test('no club is confusable with any accent the user can pick', () {
    final worst = <String>[];
    var closest = double.infinity;
    for (final club in catalog) {
      for (var i = 0; i < accents.length; i++) {
        final d = _deltaE(club.color, accents[i]);
        closest = math.min(closest, d);
        if (d < _accentFloor) {
          worst.add('${club.id} ${_hex(club.color)} vs accent '
              '${appAccentSwatches[i].label} ${_hex(accents[i])} — ΔE ${d.toStringAsFixed(1)}');
        }
      }
    }

    expect(worst, isEmpty, reason: worst.join('\n'));
    expect(closest, greaterThanOrEqualTo(_accentFloor));
  });

  test('clubs in the default bag are all distinguishable', () {
    final bag = Club.defaults;
    final worst = <String>[];
    for (var i = 0; i < bag.length; i++) {
      for (var j = i + 1; j < bag.length; j++) {
        final d = _deltaE(bag[i].color, bag[j].color);
        if (d < _bagFloor) {
          worst.add('${bag[i].id} ${_hex(bag[i].color)} vs '
              '${bag[j].id} ${_hex(bag[j].color)} — ΔE ${d.toStringAsFixed(1)}');
        }
      }
    }

    expect(worst, isEmpty, reason: worst.join('\n'));
  });

  test('any two clubs in the catalog are distinguishable', () {
    final worst = <String>[];
    for (var i = 0; i < catalog.length; i++) {
      for (var j = i + 1; j < catalog.length; j++) {
        final d = _deltaE(catalog[i].color, catalog[j].color);
        if (d < _catalogFloor) {
          worst.add('${catalog[i].id} vs ${catalog[j].id} — '
              'ΔE ${d.toStringAsFixed(1)}');
        }
      }
    }

    expect(worst, isEmpty, reason: worst.join('\n'));
  });

  test('the default bag agrees with the catalog on every colour', () {
    for (final club in Club.defaults) {
      final inCatalog = catalog.firstWhere((c) => c.id == club.id);

      expect(
        club.color.toARGB32(),
        inCatalog.color.toARGB32(),
        reason: '${club.id} differs between Club.defaults and Club.catalog',
      );
    }
  });

  test('every club and accent reads against the background', () {
    for (final club in catalog) {
      expect(
        _deltaE(club.color, AppColors.background),
        greaterThan(_backgroundFloor),
        reason: '${club.id} ${_hex(club.color)} is too dark to see',
      );
    }
    for (final swatch in appAccentSwatches) {
      expect(
        _deltaE(swatch.color, AppColors.background),
        greaterThan(_backgroundFloor),
        reason: 'accent ${swatch.label} is too dark to see',
      );
    }
  });

  test('course surfaces stay distinct from each other', () {
    // Fairway, its mown band, rough and green all abut in the 3D view.
    const surfaces = {
      'fairway': AppColors.turfFairway,
      'stripe': AppColors.turfFairwayStripe,
      'rough': AppColors.turfRough,
      'green': AppColors.turfGreen,
      'ground': AppColors.turfGround,
    };
    // The mown band is meant to be a whisper; everything else must separate.
    final names = surfaces.keys.toList();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final pair = {names[i], names[j]};
        final floor = pair.containsAll({'fairway', 'stripe'}) ? 1.5 : 3.0;
        expect(
          _deltaE(surfaces[names[i]]!, surfaces[names[j]]!),
          greaterThan(floor),
          reason: '${names[i]} and ${names[j]} are the same tone',
        );
      }
    }
  });

  test('turf is bright enough for the mowing to actually read', () {
    // The bands were always in a believable ratio — 1.39x against a photoreal
    // reference's 1.45x — but sat so dark that the ratio bought an absolute
    // separation of 0.005 of white, which is invisible. Brightness is what
    // makes a mown surface legible, so it is the brightness that is pinned.
    final fairway = _relLuminance(AppColors.turfFairway);
    final stripe = _relLuminance(AppColors.turfFairwayStripe);

    expect(fairway, greaterThan(0.035),
        reason: 'fairway is too dark for the bands to separate');
    expect(stripe - fairway, greaterThan(0.012),
        reason: 'mown bands differ by $stripe vs $fairway — invisible');
    // ...and still a whisper, not a stripe of paint.
    expect(stripe / fairway, lessThan(1.8));
  });

  test('the green reads as a target against the fairway around it', () {
    final green = _relLuminance(AppColors.turfGreen);
    final fairway = _relLuminance(AppColors.turfFairway);
    final collar = _relLuminance(AppColors.turfGreenCollar);

    // A tighter cut is lighter, and the collar lighter again — the ordering is
    // what makes the shape read as a green rather than a painted patch.
    expect(green, greaterThan(fairway));
    expect(collar, greaterThan(green));
    expect(_deltaE(AppColors.turfGreen, AppColors.turfFairway),
        greaterThan(8.0));
    expect(_deltaE(AppColors.turfGreenCollar, AppColors.turfGreen),
        greaterThan(6.0));
  });

  test('brighter turf does not let the shot get lost in it', () {
    // The reference trace is *darker* than its fairway and still dominates,
    // because it wins on chroma and hue rather than luminance. That is the
    // property worth holding: every accent stays far from every surface.
    const surfaces = {
      'fairway': AppColors.turfFairway,
      'stripe': AppColors.turfFairwayStripe,
      'rough': AppColors.turfRough,
      'green': AppColors.turfGreen,
      'collar': AppColors.turfGreenCollar,
    };
    for (var i = 0; i < accents.length; i++) {
      for (final entry in surfaces.entries) {
        expect(
          _deltaE(accents[i], entry.value),
          greaterThan(30.0),
          reason: 'accent $i disappears against ${entry.key}',
        );
      }
    }
  });

  test('every terrain is distinguishable on the builder plan', () {
    // The 3D view is a scene: rough, trees and out of bounds all sit near
    // black there and are told apart by where they are. A plan is a map —
    // colour is the only thing separating two cells — so the plan palette is
    // held to a much higher floor than the scene palette. Rendering the
    // builder is what showed this: at scene colours those three were one
    // indistinguishable smear.
    final worst = <String>[];
    for (var i = 0; i < Terrain.values.length; i++) {
      for (var j = i + 1; j < Terrain.values.length; j++) {
        final a = Terrain.values[i];
        final b = Terrain.values[j];
        final d = _deltaE(a.planColor, b.planColor);
        if (d < 12.0) {
          worst.add('${a.name} ${_hex(a.planColor)} vs '
              '${b.name} ${_hex(b.planColor)} — ΔE ${d.toStringAsFixed(1)}');
        }
      }
    }

    expect(worst, isEmpty, reason: worst.join('\n'));
  });

  test('the plan reads brighter than the scene it describes', () {
    // A map is looked at in a lit room with a fingertip over it; the scene is
    // looked at as a scene. The three that were unreadable are the check.
    for (final t in [Terrain.rough, Terrain.trees, Terrain.outOfBounds]) {
      expect(
        _relLuminance(t.planColor),
        greaterThan(_relLuminance(t.surfaceColor) * 0.9),
        reason: '${t.name} is no clearer on the plan than in the scene',
      );
    }
  });
}
