import Flutter
import Foundation
import WatchConnectivity

/// The iPhone half of the Apple Watch link.
///
/// Dart formats a whole watch screen — the session tiles, already in the
/// golfer's units — and hands it over the `omni_sniffer/watch` channel as a
/// property-list dictionary. This class does nothing to it but choose how it
/// travels:
///
/// * `updateApplicationContext` always, because it is *state*, not events:
///   the system keeps only the newest one, delivers it even while the watch
///   app is asleep, and hands it over the moment the app next launches.
/// * `sendMessage` as well when the watch is reachable, because context
///   delivery is at the system's discretion and a golfer standing over the
///   ball should see the shot land on their wrist immediately.
///
/// The watch can also ask for the current screen (on launch, or when it comes
/// back into range). That arrives as a message here, is answered straight
/// away from the last payload, and is forwarded to Dart so a genuinely fresh
/// one follows.
final class WatchBridge: NSObject {
  static let channelName = "omni_sniffer/watch"

  private var channel: FlutterMethodChannel?

  /// The last screen Dart built. Written from the channel and read again when
  /// a watch appears, so it is only ever touched on the main queue —
  /// delegate callbacks hop there first.
  private var latestPayload: [String: Any]?

  private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

  /// Wires up the channel and activates the session. Safe to call on a
  /// device with no watch: every path below degrades to "unsupported".
  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    guard let session = session else { return }
    session.delegate = self
    session.activate()
  }

  // MARK: - Dart -> iOS

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "linkState":
      result(linkState())

    case "sync":
      guard let payload = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "watch", message: "sync expects a dictionary payload", details: nil))
        return
      }
      latestPayload = payload
      deliver(payload)
      result(linkState())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func deliver(_ payload: [String: Any]) {
    // Each guard says why it stopped. A payload that silently goes nowhere is
    // indistinguishable from one the watch ignored, and the difference is the
    // whole diagnosis.
    guard let session = session, session.activationState == .activated else {
      NSLog("watch: not delivered — session not activated")
      return
    }
    guard session.isPaired else {
      NSLog("watch: not delivered — no watch paired with this iPhone")
      return
    }
    guard session.isWatchAppInstalled else {
      NSLog("watch: not delivered — the watch app is not installed")
      return
    }

    do {
      try session.updateApplicationContext(payload)
    } catch {
      // Thrown when the payload isn't property-list encodable, or the
      // session went down between the check and the call. The next shot
      // brings another payload, so this is a log, not a failure.
      NSLog("watch: updateApplicationContext failed — \(error.localizedDescription)")
    }

    if session.isReachable {
      session.sendMessage(payload, replyHandler: nil) { error in
        NSLog("watch: sendMessage failed — \(error.localizedDescription)")
      }
    }
  }

  private func linkState() -> [String: Any] {
    guard let session = session else {
      return [
        "supported": false, "activated": false, "paired": false,
        "appInstalled": false, "reachable": false,
      ]
    }
    return [
      "supported": true,
      "activated": session.activationState == .activated,
      "paired": session.isPaired,
      "appInstalled": session.isWatchAppInstalled,
      "reachable": session.isReachable,
    ]
  }

  /// Delegate callbacks arrive off the main thread; channel calls must not.
  private func notifyDart(_ method: String, _ arguments: Any?) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(method, arguments: arguments)
    }
  }

  /// Re-sends the last screen, from the main queue, where `latestPayload`
  /// lives.
  private func deliverLatest() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let payload = self.latestPayload else { return }
      self.deliver(payload)
    }
  }

  private func publishLinkState() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.channel?.invokeMethod("linkStateChanged", arguments: self.linkState())
    }
  }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {
  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error = error {
      NSLog("watch: activation failed — \(error.localizedDescription)")
    }
    publishLinkState()
    // A watch that was installed while the session was activating still has
    // nothing; hand it whatever the phone last built.
    deliverLatest()
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
    publishLinkState()
  }

  /// The golfer switched to a different watch. Re-activating rebinds the
  /// session to the new one — without this the link silently dies.
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    publishLinkState()
    deliverLatest()
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    publishLinkState()
  }

  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    // A command — tagging the shot on screen, so far. Dart owns the session,
    // so the answer has to come from there; the watch waits on this reply to
    // know whether what it drew optimistically actually happened.
    if message["command"] is String {
      DispatchQueue.main.async { [weak self] in
        guard let channel = self?.channel else {
          replyHandler(["ok": false, "reason": "The phone app isn't running."])
          return
        }
        channel.invokeMethod("command", arguments: message) { result in
          if let reply = result as? [String: Any] {
            replyHandler(reply)
          } else {
            // FlutterError, FlutterMethodNotImplemented, or a Dart side too
            // old to know this command. All the same thing to the watch.
            replyHandler(["ok": false, "reason": "The phone couldn't do that."])
          }
        }
      }
      return
    }

    guard message["request"] as? String == "sync" else {
      replyHandler([:])
      return
    }
    // Answer instantly with the last screen so the watch has something to
    // draw, then ask Dart for a current one.
    DispatchQueue.main.async { [weak self] in
      replyHandler(self?.latestPayload ?? [:])
      self?.channel?.invokeMethod("requestSync", arguments: nil)
    }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    if message["command"] is String {
      notifyDart("command", message)
      return
    }
    guard message["request"] as? String == "sync" else { return }
    notifyDart("requestSync", nil)
  }
}
