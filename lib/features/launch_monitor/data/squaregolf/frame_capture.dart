/// A rolling record of raw notification frames from the launch monitor.
///
/// This exists to answer questions the decoded structs cannot. The `11 02`
/// ball frame is parsed as 17 bytes of launch data — speed, angles, spin — and
/// nothing in this app or in the `squaregolf-connector` reference it was
/// ported from decodes apex, carry or flight time. The Omni clearly computes
/// them (it has an on-device display, a green-speed setting and a
/// carry-adjustment command), so the open question is whether it also puts
/// them on the wire.
///
/// Two things would answer it, and both are visible here and nowhere else:
///   * a `11 02` frame longer than the 17 bytes the parser consumes, whose
///     tail is being silently ignored, or
///   * a frame kind we never classify — `11 05`, or anything from `11 08` up —
///     arriving in the moments after a shot.
///
/// So this keeps the last [_limit] frames verbatim, with their true byte
/// length, and can hand them over as text. Unlike [lmLog] it is *not* gated on
/// debug mode: the capture that matters comes from a real range session on a
/// real build, which is exactly where `dart:developer` logging is unavailable.
/// It is a bounded in-memory ring — no file I/O, no network, nothing leaves
/// the device unless the user explicitly shares it.
library;

import 'dart:collection';

/// One raw frame, exactly as it arrived.
class CapturedFrame {
  final DateTime at;

  /// The [NotificationKind] name this frame classified as, including
  /// `unknown` — the interesting case.
  final String kind;

  /// Byte count. For a `11 02` frame anything above 17 is undecoded tail.
  final int length;

  /// Space-separated lower-case hex.
  final String hex;

  const CapturedFrame({
    required this.at,
    required this.kind,
    required this.length,
    required this.hex,
  });
}

class FrameCapture {
  FrameCapture._();

  /// Enough to cover a shot and the config chatter either side of it, small
  /// enough that the buffer never matters for memory.
  static const _limit = 256;

  static final Queue<CapturedFrame> _frames = Queue<CapturedFrame>();

  /// Set once the device type is known, so a capture is self-describing.
  static String deviceType = 'unknown';
  static String osVersion = '';

  /// The device's GATT map, one entry per characteristic: uuid and the
  /// properties it advertises.
  ///
  /// We subscribe to exactly one characteristic, [notificationCharUuid]. If
  /// the Omni publishes its flight numbers on a second notify characteristic,
  /// no implementation would ever have seen them — so the map is worth as much
  /// as the frames.
  static final List<String> gatt = [];

  /// Characteristics that can notify but that we never subscribe to.
  static final List<String> unsubscribedNotify = [];

  static void recordGatt(List<String> entries, {List<String> notifying = const []}) {
    gatt
      ..clear()
      ..addAll(entries);
    unsubscribedNotify
      ..clear()
      ..addAll(notifying);
  }

  static void record(String kind, List<String> bytes) {
    _frames.addLast(CapturedFrame(
      at: DateTime.now(),
      kind: kind,
      length: bytes.length,
      hex: bytes.map((b) => b.toLowerCase()).join(' '),
    ));
    while (_frames.length > _limit) {
      _frames.removeFirst();
    }
  }

  static int get count => _frames.length;

  static void clear() => _frames.clear();

  /// Frames whose tail the parser never reads, or whose kind it never
  /// recognises. If apex is on the wire, it is in one of these.
  static List<CapturedFrame> get undecoded => [
        for (final f in _frames)
          if (f.kind == 'unknown' || (f.kind == 'ballMetrics' && f.length > 17))
            f,
      ];

  /// The capture as shareable text, newest last.
  static String report() {
    final buf = StringBuffer()
      ..writeln('Square Golf protocol capture')
      ..writeln('device: $deviceType')
      ..writeln('os: ${osVersion.isEmpty ? "unknown" : osVersion}')
      ..writeln('frames: ${_frames.length} (cap $_limit)')
      ..writeln();

    final odd = undecoded;
    if (odd.isEmpty) {
      buf
        ..writeln('No undecoded frames seen: every ball frame was exactly the')
        ..writeln('17 bytes the parser consumes, and every frame classified.')
        ..writeln('On this evidence the device does not transmit apex.')
        ..writeln();
    } else {
      buf.writeln('${odd.length} frame(s) carrying data we do not decode:');
      for (final f in odd) {
        buf.writeln('  ${f.kind} len=${f.length}  ${f.hex}');
      }
      buf.writeln();
    }

    if (gatt.isNotEmpty) {
      buf.writeln('--- characteristics ---');
      for (final g in gatt) {
        buf.writeln('  $g');
      }
      if (unsubscribedNotify.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('${unsubscribedNotify.length} characteristic(s) can notify '
              'but are never subscribed to:');
        for (final u in unsubscribedNotify) {
          buf.writeln('  $u');
        }
      }
      buf.writeln();
    }

    buf.writeln('--- all frames ---');
    if (_frames.isEmpty) {
      buf.writeln('(none — connect to the monitor and hit a shot)');
    } else {
      final start = _frames.first.at;
      for (final f in _frames) {
        final ms = f.at.difference(start).inMilliseconds;
        buf.writeln('+${ms.toString().padLeft(6)}ms  '
            '${f.kind.padRight(12)} len=${f.length.toString().padLeft(3)}  '
            '${f.hex}');
      }
    }
    return buf.toString();
  }
}
