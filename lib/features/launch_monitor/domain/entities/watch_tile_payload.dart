/// What the Apple Watch shows: the session screen's tiles, already formatted.
///
/// The watch renders strings, never numbers — every value here has been
/// through the same formatter the phone's tiles use, in the golfer's chosen
/// units, so the two screens can't disagree about what a shot carried. The
/// watch app therefore needs no knowledge of [TileMetric], unit preferences
/// or the flight model.
///
/// Everything crosses to native as a plain map of property-list types
/// (String / int / double / bool / List / Map). WatchConnectivity refuses
/// anything else, and nulls in particular, so absent values are omitted
/// entirely rather than sent as null.
library;

/// One tile: label above, big value in the middle, unit and average below.
class WatchTile {
  /// Stable identity — the `TileMetric` enum name. Lets the watch animate a
  /// value change rather than a whole-grid replacement.
  final String id;

  /// Small-caps heading, e.g. `CARRY`.
  final String label;

  /// The number, e.g. `265.4`. `--` when the metric is unavailable.
  final String value;

  /// Direction letter trailing the number — `R`, `L`, `T`, `H` — drawn at
  /// half size beside it, matching the phone.
  final String suffix;

  /// Unit line under the value, e.g. `yds`. Empty for unitless metrics.
  final String unit;

  /// The session average, pre-formatted, e.g. `258.1`. Empty when there is
  /// nothing to average yet.
  final String average;

  /// Signed distance from that average, e.g. `±7.3`. Empty when unknown.
  final String delta;

  /// Second value for the two-part impact-location tile (vertical position).
  /// Empty for every other metric.
  final String secondaryLabel;
  final String secondaryValue;

  const WatchTile({
    required this.id,
    required this.label,
    required this.value,
    this.suffix = '',
    this.unit = '',
    this.average = '',
    this.delta = '',
    this.secondaryLabel = '',
    this.secondaryValue = '',
  });

  /// True for the impact-location tile, the one metric that travels as two
  /// stacked readouts rather than a single number.
  bool get hasSecondary => secondaryValue.isNotEmpty;

  Map<String, Object> toMap() => {
    'id': id,
    'label': label,
    'value': value,
    'suffix': suffix,
    'unit': unit,
    'average': average,
    'delta': delta,
    'secondaryLabel': secondaryLabel,
    'secondaryValue': secondaryValue,
  };
}

/// One of the golfer's tags, as the watch needs it: something to show and
/// something to send back when they tap it.
class WatchTag {
  final int id;
  final String name;

  /// `#RRGGBB`, so the watch can draw the same dot the phone does.
  final String color;

  const WatchTag({required this.id, required this.name, required this.color});

  Map<String, Object> toMap() => {'id': id, 'name': name, 'color': color};
}

/// Device connection as the watch understands it. Mirrors
/// `LaunchMonitorStatus`, kept as its own type so the watch protocol doesn't
/// move every time the BLE layer gains a state.
enum WatchConnection { disconnected, scanning, connecting, connected }

/// A complete watch screen. Immutable; the sync layer sends a fresh one on
/// every change.
class WatchTilePayload {
  final WatchConnection connection;

  /// The tiles, in the order the golfer arranged them on the phone.
  final List<WatchTile> tiles;

  /// Shots in the session, and which one the tiles are showing (1-based).
  /// [shotIndex] is 0 when there is no shot yet.
  final int shotCount;
  final int shotIndex;

  /// Club the shot was hit with, e.g. `7i`. Empty when unknown.
  final String club;

  /// The user's accent colour as `#RRGGBB`, so the watch tints with whatever
  /// they picked on the phone.
  final String accent;

  /// Device battery percentage, or null when the device hasn't reported one.
  final int? battery;

  /// Whether the Omni currently sees a ball in a hittable position.
  final bool ballReady;

  /// Every tag the golfer has, so the watch can offer the same list the
  /// phone's tag picker does.
  final List<WatchTag> tags;

  /// The tags already on the shot being shown.
  final List<int> shotTags;

  /// Database id of that shot — the handle the watch sends back when it
  /// tags something. Zero when there is no shot, or when the shot hasn't
  /// been persisted yet and so cannot be tagged from the wrist.
  final int shotId;

  /// Milliseconds since epoch — lets the watch show how stale the data is
  /// after the phone goes out of range.
  final int sentAtMs;

  const WatchTilePayload({
    required this.connection,
    required this.tiles,
    required this.shotCount,
    required this.shotIndex,
    required this.club,
    required this.accent,
    required this.ballReady,
    required this.sentAtMs,
    this.tags = const [],
    this.shotTags = const [],
    this.shotId = 0,
    this.battery,
  });

  Map<String, Object> toMap() => {
    'connection': connection.name,
    'tiles': [for (final t in tiles) t.toMap()],
    'shotCount': shotCount,
    'shotIndex': shotIndex,
    'club': club,
    'accent': accent,
    'ballReady': ballReady,
    'sentAtMs': sentAtMs,
    'tags': [for (final t in tags) t.toMap()],
    'shotTags': shotTags,
    'shotId': shotId,
    if (battery != null) 'battery': battery!,
  };

  /// Everything except the timestamp, as a comparable string. Two payloads
  /// with the same signature look identical on the watch, so re-sending one
  /// would only cost battery.
  String get signature {
    final b = StringBuffer()
      ..write(connection.name)
      ..write('|$shotCount|$shotIndex|$club|$accent|$battery|$ballReady')
      ..write('|$shotId|${shotTags.join(',')}')
      ..write('|${tags.map((t) => '${t.id}:${t.name}:${t.color}').join(',')}');
    for (final t in tiles) {
      b.write(
        '|${t.id};${t.value};${t.suffix};${t.unit};'
        '${t.average};${t.delta};${t.secondaryValue}',
      );
    }
    return b.toString();
  }
}
