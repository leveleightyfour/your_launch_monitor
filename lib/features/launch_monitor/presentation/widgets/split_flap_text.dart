import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated text that cycles between values with a vintage split-flap board
/// effect — digits roll through 0-9 with a left-to-right stagger, other
/// characters flip at the midpoint. Used by the tiles, dispersion stats, and
/// any other surface that wants to draw the eye to a freshly-updated metric.
class SplitFlapText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration duration;

  const SplitFlapText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 550),
  });

  @override
  State<SplitFlapText> createState() => _SplitFlapTextState();
}

class _SplitFlapTextState extends State<SplitFlapText>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  String _from = '';

  @override
  void initState() {
    super.initState();
    _from = widget.text;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didUpdateWidget(SplitFlapText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _from = old.text;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _char(int index, double t) {
    final to = widget.text;
    final from = _from;
    final toChar = index < to.length ? to[index] : ' ';
    final fromChar = index < from.length ? from[index] : ' ';

    if (toChar == fromChar) return toChar;

    final offset = (index * 0.06).clamp(0.0, 0.45);
    final localT = ((t - offset) / 0.7).clamp(0.0, 1.0);

    if (localT >= 1.0) return toChar;
    if (localT <= 0.0) return fromChar;

    final isNumeric =
        RegExp(r'\d').hasMatch(toChar) || RegExp(r'\d').hasMatch(fromChar);
    if (isNumeric) {
      if (localT > 0.85) return toChar;
      return ((localT * 10).floor() % 10).toString();
    }

    return localT < 0.5 ? fromChar : toChar;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final len = math.max(widget.text.length, _from.length);
        final buf = StringBuffer();
        for (var i = 0; i < len; i++) {
          buf.write(_char(i, t));
        }
        return Text(buf.toString(), style: widget.style);
      },
    );
  }
}
