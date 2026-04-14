import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ── Preset swatches ───────────────────────────────────────────────────────────

class AppAccentSwatch {
  final String label;
  final Color color;

  const AppAccentSwatch(this.label, this.color);
}

const appAccentSwatches = [
  AppAccentSwatch('Teal',        Color(0xFF2DD4B0)),
  AppAccentSwatch('Blue',        Color(0xFF3B82F6)),
  AppAccentSwatch('Purple',      Color(0xFFA855F7)),
  AppAccentSwatch('Rose',        Color(0xFFF43F5E)),
  AppAccentSwatch('Amber',       Color(0xFFF59E0B)),
  AppAccentSwatch('Green',       Color(0xFF22C55E)),
  AppAccentSwatch('Sky',         Color(0xFF38BDF8)),
  AppAccentSwatch('Indigo',      Color(0xFF6366F1)),
  AppAccentSwatch('Pink',        Color(0xFFEC4899)),
  AppAccentSwatch('Orange',      Color(0xFFF97316)),
  AppAccentSwatch('Lime',        Color(0xFF84CC16)),
  AppAccentSwatch('Cyan',        Color(0xFF06B6D4)),
  AppAccentSwatch('Violet',      Color(0xFF8B5CF6)),
  AppAccentSwatch('Red',         Color(0xFFEF4444)),
  AppAccentSwatch('Emerald',     Color(0xFF10B981)),
  AppAccentSwatch('Yellow',      Color(0xFFEAB308)),
];

// ── Provider ──────────────────────────────────────────────────────────────────

final accentColorProvider =
    NotifierProvider<AccentColorNotifier, Color>(AccentColorNotifier.new);

class AccentColorNotifier extends Notifier<Color> {
  static const _fileName = 'accent_color.txt';

  /// Call this before [runApp] to eliminate the teal flash on startup.
  static Color? _preloaded;

  static Future<void> preload() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) {
        final hex = (await file.readAsString()).trim();
        final value = int.tryParse(hex, radix: 16);
        if (value != null) _preloaded = Color(value);
      }
    } catch (_) {}
  }

  @override
  Color build() => _preloaded ?? appAccentSwatches.first.color;

  Future<void> setAccent(Color color) async {
    state = color;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(color.toARGB32().toRadixString(16));
    } catch (_) {}
  }
}
