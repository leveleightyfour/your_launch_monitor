/// A named, saved hole — and the portable document it travels as.
///
/// The share format is a self-describing JSON envelope: a magic key naming
/// the document type, a format version, and the complete [HoleSetup]
/// (analytic numbers, painted grid, pin). Everything a hole is fits in a
/// few hundred characters thanks to the grid's run-length encoding, so a
/// hole can be pasted through any messenger today and opened as a file by
/// a future release without changing the format.
library;

import 'dart:convert';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/hole_setup.dart';

class SavedHole {
  final String name;
  final DateTime savedAt;
  final HoleSetup hole;

  const SavedHole({
    required this.name,
    required this.savedAt,
    required this.hole,
  });

  /// The envelope's magic key: this document is a Your Launch Monitor hole.
  static const magicKey = 'ylmHole';

  /// Bumped only when the envelope itself changes shape. [HoleSetup] and
  /// [HoleGrid] read their own json defensively, so new fields there do not
  /// need a new version here.
  static const formatVersion = 1;

  Map<String, dynamic> toJson() => {
    magicKey: formatVersion,
    'name': name,
    'savedAt': savedAt.toIso8601String(),
    'hole': hole.toJson(),
  };

  factory SavedHole.fromJson(Map<String, dynamic> json) => SavedHole(
    name: (json['name'] as String? ?? '').trim(),
    savedAt:
        DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
    hole: HoleSetup.fromJson(
      (json['hole'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );

  /// The document as share-ready text.
  String encodeShareText() => jsonEncode(toJson());

  /// Parses shared text back into a hole, or null when the text is not a
  /// hole document. Only the envelope is strict — the magic key must be
  /// present and the version readable; the hole inside is read with the
  /// same defensive parsing every stored hole gets.
  static SavedHole? tryDecode(String text) {
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded[magicKey];
      if (version is! num) return null;
      final hole = SavedHole.fromJson(decoded);
      if (hole.name.isEmpty) return null;
      return hole;
    } catch (_) {
      return null;
    }
  }

  /// A name not already taken, counting up: `Road Hole`, `Road Hole (2)`…
  static String uniqueName(String base, Iterable<String> taken) {
    final trimmed = base.trim().isEmpty ? 'Hole' : base.trim();
    final names = taken.toSet();
    if (!names.contains(trimmed)) return trimmed;
    var n = 2;
    while (names.contains('$trimmed ($n)')) {
      n++;
    }
    return '$trimmed ($n)';
  }
}
