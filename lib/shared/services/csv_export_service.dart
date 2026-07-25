/// Shared CSV export for shot data — used by the table tab, the shot-list
/// multi-select bar, and the session-tile menu.
///
/// Exports every field (not just visible table columns) in the user's display
/// units, writes to a temp file, and hands off to the platform share sheet.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/club.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_data.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/tag.dart';
import 'package:omni_sniffer/shared/providers/unit_prefs_provider.dart';

class CsvExportService {
  CsvExportService._();

  /// Serialize [shots] and open the platform share sheet.
  ///
  /// [context] anchors the iPad share popover (required on iPadOS — without
  /// a `sharePositionOrigin` the share sheet silently fails to present) and
  /// hosts the failure snackbar.
  ///
  /// [baseName] becomes the file name (sanitised, date-stamped):
  /// `range-session_2026-07-17.csv`.
  static Future<void> exportShots({
    required BuildContext context,
    required List<ShotData> shots,
    required List<Club> clubs,
    required List<Tag> tags,
    required UnitPrefs prefs,
    required String baseName,
  }) async {
    if (shots.isEmpty) return;

    // Capture the anchor rect before any async gap — the render object may
    // be gone by the time the file is written.
    final box = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.of(context).size;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height / 2),
            width: 1,
            height: 1,
          );

    try {
      final csv =
          buildCsv(shots: shots, clubs: clubs, tags: tags, prefs: prefs);

      final dir = await getTemporaryDirectory();
      final date = DateTime.now();
      final stamp = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final safe = baseName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final file = File(
          '${dir.path}/${safe.isEmpty ? 'shots' : safe}_$stamp.csv');
      await file.writeAsString(csv);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject:
              '${baseName.trim().isEmpty ? 'Shots' : baseName.trim()} — CSV export',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  /// Pure CSV serialisation — exposed for tests.
  static String buildCsv({
    required List<ShotData> shots,
    required List<Club> clubs,
    required List<Tag> tags,
    required UnitPrefs prefs,
  }) {
    final dist = prefs.distLabel;
    final spd = prefs.speedLabel;

    final headers = [
      'Shot',
      'Club',
      'Ball Speed ($spd)',
      'Club Speed ($spd)',
      'Smash Factor',
      'Spin Rate (rpm)',
      'Spin Axis (deg)',
      'Launch Angle (deg)',
      'Launch Direction (deg)',
      'Carry ($dist)',
      'Total ($dist)',
      'Offline ($dist)',
      'Apex ($dist)',
      'Run ($dist)',
      'Swing Path (deg)',
      'Face Angle (deg)',
      'Attack Angle (deg)',
      'Dynamic Loft (deg)',
      'Impact Horizontal (mm)',
      'Impact Vertical (mm)',
      'Tags',
    ];

    String clubName(String? id) {
      if (id == null) return '';
      return clubs.where((c) => c.id == id).firstOrNull?.shortName ?? id;
    }

    String tagNames(List<int> ids) {
      if (ids.isEmpty) return '';
      return ids
          .map((id) => tags.where((t) => t.id == id).firstOrNull?.name)
          .whereType<String>()
          .join('; ');
    }

    String n(double v, [int dp = 1]) => v.toStringAsFixed(dp);
    String opt(double? v, [int dp = 1]) => v == null ? '' : v.toStringAsFixed(dp);
    String optDist(double? v) => v == null ? '' : n(prefs.dist(v));

    final buf = StringBuffer()..writeln(headers.map(_escape).join(','));

    // Shots are stored newest-first; export oldest-first so the CSV reads
    // top-to-bottom in playing order.
    final ordered = shots.reversed.toList();
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      final row = [
        '${i + 1}',
        clubName(s.clubId),
        n(prefs.spd(s.ballSpeed)),
        n(prefs.spd(s.clubSpeed)),
        n(s.smashFactor, 2),
        n(s.spinRate, 0),
        n(s.spinAxis),
        n(s.launchAngle),
        n(s.launchDirection),
        n(prefs.dist(s.carry)),
        n(prefs.dist(s.totalDistance)),
        n(prefs.dist(s.lateralOffset)),
        optDist(s.apex),
        optDist(s.run),
        opt(s.swingPath),
        opt(s.faceAngle),
        opt(s.angleOfAttack),
        opt(s.dynamicLoft),
        opt(s.horizontalImpact),
        opt(s.verticalImpact),
        tagNames(s.tagIds),
      ];
      buf.writeln(row.map(_escape).join(','));
    }
    return buf.toString();
  }

  static String _escape(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
}
