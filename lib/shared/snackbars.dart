import 'dart:async';

import 'package:flutter/material.dart';

import 'package:omni_sniffer/shared/theme.dart';

/// Shows a snackbar that reliably clears itself.
///
/// Replaces whatever bar is showing rather than queueing behind it, and
/// closes itself with its own timer: the framework skips the built-in
/// auto-hide whenever assistive navigation is active on the device, which
/// reads as a bar that never leaves. Ours are transient by design, so the
/// timer always runs.
void showTransientSnackBar(
  BuildContext context, {
  required String message,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      backgroundColor: AppColors.card,
      duration: duration,
      content: Text(message, style: AppTextStyles.sans(size: 13)),
      action: action,
    ),
  );
  var open = true;
  controller.closed.whenComplete(() => open = false);
  // Slight grace so the framework's own timer wins when it does run.
  Timer(duration + const Duration(milliseconds: 200), () {
    if (open) controller.close();
  });
}
