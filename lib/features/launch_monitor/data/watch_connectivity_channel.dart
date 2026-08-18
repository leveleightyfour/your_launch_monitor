import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:omni_sniffer/features/launch_monitor/domain/entities/watch_tile_payload.dart';

/// How the paired Apple Watch is currently reachable.
///
/// Every field comes straight from `WCSession` on the iOS side. They are
/// deliberately kept separate rather than collapsed into one enum: "no watch
/// paired" and "watch paired but our app isn't installed on it" need
/// different words in the UI, and only [reachable] decides whether an update
/// lands immediately or waits for the watch to wake.
@immutable
class WatchLinkState {
  /// False on every platform but iOS, and on iPads / iPhones where
  /// WatchConnectivity itself is unavailable.
  final bool supported;

  /// The `WCSession` finished activating.
  final bool activated;

  /// A watch is paired with this iPhone.
  final bool paired;

  /// Our watch app is installed on that watch.
  final bool appInstalled;

  /// The watch is awake and in range: messages arrive now rather than at the
  /// system's convenience.
  final bool reachable;

  const WatchLinkState({
    this.supported = false,
    this.activated = false,
    this.paired = false,
    this.appInstalled = false,
    this.reachable = false,
  });

  static const unsupported = WatchLinkState();

  factory WatchLinkState.fromMap(Map<Object?, Object?> map) => WatchLinkState(
    supported: map['supported'] == true,
    activated: map['activated'] == true,
    paired: map['paired'] == true,
    appInstalled: map['appInstalled'] == true,
    reachable: map['reachable'] == true,
  );

  /// Whether it is worth building a payload at all.
  bool get shouldSync => supported && activated && paired && appInstalled;

  @override
  bool operator ==(Object other) =>
      other is WatchLinkState &&
      other.supported == supported &&
      other.activated == activated &&
      other.paired == paired &&
      other.appInstalled == appInstalled &&
      other.reachable == reachable;

  @override
  int get hashCode =>
      Object.hash(supported, activated, paired, appInstalled, reachable);

  @override
  String toString() =>
      'WatchLinkState(supported: $supported, activated: $activated, '
      'paired: $paired, installed: $appInstalled, reachable: $reachable)';
}

/// The iOS end of the watch link: a thin wrapper over the
/// `omni_sniffer/watch` method channel that `WatchBridge.swift` answers.
///
/// Nothing here knows what a tile is — it ships a map and reports what
/// WatchConnectivity said about it. On every platform other than iOS the
/// whole class is inert, so callers need no platform checks of their own.
class WatchConnectivityChannel {
  WatchConnectivityChannel({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    if (isSupported) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static const channelName = 'omni_sniffer/watch';

  final MethodChannel _channel;

  /// The watch asked for a fresh payload — it just launched, came back into
  /// range, or the golfer pulled to refresh.
  VoidCallback? onSyncRequested;

  /// Reachability changed underneath us.
  ValueChanged<WatchLinkState>? onStateChanged;

  /// The watch asked the phone to *do* something — tag the shot on screen,
  /// so far. The returned map is handed straight back to the watch as the
  /// reply to its message, so it must be property-list safe.
  Future<Map<String, Object>> Function(WatchCommand command)? onCommand;

  static bool get isSupported => !kIsWeb && Platform.isIOS;

  /// Ships [payload] to the watch. Returns the link state as it was at the
  /// moment of sending, or [WatchLinkState.unsupported] off iOS.
  Future<WatchLinkState> send(WatchTilePayload payload) =>
      _invoke('sync', payload.toMap());

  /// Asks iOS for the current link state without sending anything.
  Future<WatchLinkState> refresh() => _invoke('linkState', null);

  Future<WatchLinkState> _invoke(String method, Object? arguments) async {
    if (!isSupported) return WatchLinkState.unsupported;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
      if (result == null) return WatchLinkState.unsupported;
      return WatchLinkState.fromMap(result);
    } on PlatformException catch (e) {
      // A watch that went away mid-send is ordinary, not exceptional: the
      // next payload will find it again.
      debugPrint('watch: $method failed — ${e.message}');
      return WatchLinkState.unsupported;
    } on MissingPluginException {
      // An older native binary under a code push: no watch bridge compiled
      // in. Stay quiet and inert.
      return WatchLinkState.unsupported;
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'requestSync':
        onSyncRequested?.call();
      case 'linkStateChanged':
        final args = call.arguments;
        if (args is Map<Object?, Object?>) {
          onStateChanged?.call(WatchLinkState.fromMap(args));
        }
      case 'command':
        final command = WatchCommand.parse(call.arguments);
        if (command == null) {
          return WatchCommand.failure('That command was malformed.');
        }
        final handler = onCommand;
        if (handler == null) {
          return WatchCommand.failure('The phone is not ready for that yet.');
        }
        return handler(command);
    }
    return null;
  }

  void dispose() {
    onSyncRequested = null;
    onStateChanged = null;
    onCommand = null;
    if (isSupported) {
      _channel.setMethodCallHandler(null);
    }
  }
}


/// Something the watch asked the phone to do.
///
/// Commands are deliberately a closed set with a named action rather than
/// anything the watch can dream up: the wrist is a remote control for the
/// phone's session, not a second author of it.
@immutable
class WatchCommand {
  /// What to do. `toggleTag` is the only action so far.
  final String action;

  /// Database id of the shot the command applies to.
  final int shotId;

  /// Tag being toggled, for `toggleTag`.
  final int tagId;

  /// Whether the tag should end up on (true) or off (false).
  final bool on;

  const WatchCommand({
    required this.action,
    required this.shotId,
    required this.tagId,
    required this.on,
  });

  /// Reads a command off the wire, or null if it isn't one. Everything here
  /// arrives from another device, so nothing is assumed about its shape.
  static WatchCommand? parse(Object? raw) {
    if (raw is! Map) return null;
    final action = raw['command'];
    if (action is! String || action.isEmpty) return null;
    final shotId = raw['shotId'];
    final tagId = raw['tagId'];
    return WatchCommand(
      action: action,
      shotId: shotId is int ? shotId : 0,
      tagId: tagId is int ? tagId : 0,
      on: raw['on'] == true,
    );
  }

  /// The reply shape the watch expects: an outcome it can show.
  static Map<String, Object> success() => const {'ok': true};

  static Map<String, Object> failure(String reason) => {
    'ok': false,
    'reason': reason,
  };
}
