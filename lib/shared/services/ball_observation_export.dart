/// Shares the ball-position log.
///
/// The log answers a question no documentation can: where this monitor actually
/// calls a ball ready. See [BallObservationLog] for why that cannot be read off
/// the manual.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omni_sniffer/features/launch_monitor/data/ball_observation_log.dart';

class BallObservationExport {
  BallObservationExport._();

  static Future<void> share(BuildContext context, BallObservationLog log) async {
    // Anchor the iPad popover before the first async gap, same as the other
    // exports — without an origin the share sheet silently fails to present.
    final box = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.of(context).size;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height / 2),
            width: 1,
            height: 1,
          );

    if (log.frameCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing logged yet — connect, arm detection and put a ball down.',
          ),
        ),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/ball-positions_$stamp.txt');
      await file.writeAsString(log.report());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'Ball position log',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ball position export failed: $e')),
        );
      }
    }
  }
}
