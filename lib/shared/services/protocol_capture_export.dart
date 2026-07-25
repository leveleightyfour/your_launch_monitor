/// Shares the raw launch-monitor frame capture.
///
/// Used to settle whether the device transmits metrics we do not decode —
/// apex above all. See [FrameCapture] for what is recorded and why.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omni_sniffer/features/launch_monitor/data/squaregolf/frame_capture.dart';

class ProtocolCaptureExport {
  ProtocolCaptureExport._();

  static Future<void> share(BuildContext context) async {
    // Anchor the iPad popover before the first async gap, same as the CSV
    // export — without an origin the share sheet silently fails to present.
    final box = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.of(context).size;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height / 2),
            width: 1,
            height: 1,
          );

    if (FrameCapture.count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No frames captured yet — connect to the monitor and hit a shot.',
          ),
        ),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/protocol-capture_$stamp.txt');
      await file.writeAsString(FrameCapture.report());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'Square Golf protocol capture',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture export failed: $e')),
        );
      }
    }
  }
}
