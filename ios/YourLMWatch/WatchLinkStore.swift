import Combine
import Foundation
import WatchConnectivity

/// The watch's connection to the phone.
///
/// Three things arrive here, all carrying the same shape of payload:
///
/// * `didReceiveApplicationContext` — the state the phone left for us. This
///   is what makes the app open showing the last shot rather than a spinner,
///   even if it has been in a pocket for an hour.
/// * `didReceiveMessage` — a live shot, pushed the instant the phone has it.
/// * the reply to our own `sync` request, sent whenever the app appears or
///   the phone becomes reachable again.
///
/// Delegate callbacks arrive on a background queue; every published change is
/// hopped to the main queue, so SwiftUI only ever sees `payload` change under
/// it. Deliberately no `@MainActor`: `WCSessionDelegate` conformance is
/// simpler and warning-free without it.
final class WatchLinkStore: NSObject, ObservableObject {
  static let shared = WatchLinkStore()

  /// The screen to draw. Nil until the phone has been heard from at all.
  @Published private(set) var payload: WatchTilePayload?

  /// Whether the phone is awake and in range right now.
  @Published private(set) var phoneReachable = false

  /// Set while a sync request is outstanding, so the UI can say so.
  @Published private(set) var isRequesting = false

  /// Tags the golfer has just tapped, shown before the phone has confirmed
  /// them. Keyed by shot id so a stale optimistic state can never bleed onto
  /// the next shot. Cleared when the phone's own answer arrives.
  @Published private(set) var pendingTags: [Int: Set<Int>] = [:]

  /// Why the last command was refused, for one line of explanation on the
  /// wrist. Cleared when the next one is sent.
  @Published private(set) var commandError: String?

  private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

  private override init() {
    super.init()
  }

  func activate() {
    guard let session = session else { return }
    session.delegate = self
    if session.activationState == .activated {
      adopt(session.receivedApplicationContext)
      requestSync()
    } else {
      session.activate()
    }
  }

  /// Asks the phone for the current tiles. Cheap, and the only way to get
  /// fresh data after the watch has been asleep — application context is
  /// delivered when the system sees fit, not when the golfer looks at their
  /// wrist.
  func requestSync() {
    guard let session = session, session.activationState == .activated else { return }
    guard session.isReachable else {
      // Not reachable: whatever the phone last left in the context is the
      // freshest thing that exists, so show that rather than nothing.
      adopt(session.receivedApplicationContext)
      return
    }
    publish { $0.isRequesting = true }
    session.sendMessage(["request": "sync"]) { [weak self] reply in
      self?.publish {
        $0.isRequesting = false
        $0.merge(reply)
      }
    } errorHandler: { [weak self] error in
      NSLog("watch: sync request failed — \(error.localizedDescription)")
      self?.publish { $0.isRequesting = false }
    }
  }

  /// The tags to draw for [payload]: what the phone says, unless the golfer
  /// has tapped something since and the phone hasn't caught up.
  func tags(for payload: WatchTilePayload) -> Set<Int> {
    pendingTags[payload.shotId] ?? payload.shotTags
  }

  /// Adds or removes a tag on the shot currently shown.
  ///
  /// The change appears immediately and is corrected only if the phone
  /// refuses it — a golfer tapping a tag between swings shouldn't be made to
  /// wait on a round trip to see it happen.
  func toggleTag(_ tag: WatchTag, on payload: WatchTilePayload) {
    guard payload.canTag else { return }
    let shotId = payload.shotId
    let current = tags(for: payload)
    let turningOn = !current.contains(tag.id)

    publish { store in
      store.commandError = nil
      var next = current
      if turningOn { next.insert(tag.id) } else { next.remove(tag.id) }
      store.pendingTags[shotId] = next
    }

    guard let session = session, session.activationState == .activated, session.isReachable
    else {
      publish { store in
        store.pendingTags[shotId] = nil
        store.commandError = "Phone out of range"
      }
      return
    }

    let message: [String: Any] = [
      "command": "toggleTag",
      "shotId": shotId,
      "tagId": tag.id,
      "on": turningOn,
    ]

    session.sendMessage(message) { [weak self] reply in
      let ok = (reply["ok"] as? NSNumber)?.boolValue ?? false
      let reason = reply["reason"] as? String
      self?.publish { store in
        if ok {
          // The phone follows a successful command with a fresh payload;
          // dropping the optimistic copy lets that become the truth.
          store.pendingTags[shotId] = nil
        } else {
          store.pendingTags[shotId] = nil
          store.commandError = reason ?? "The phone refused that."
        }
      }
    } errorHandler: { [weak self] error in
      NSLog("watch: toggleTag failed — \(error.localizedDescription)")
      self?.publish { store in
        store.pendingTags[shotId] = nil
        store.commandError = "Phone didn't answer"
      }
    }
  }

  private func adopt(_ dictionary: [String: Any]) {
    publish { $0.merge(dictionary) }
  }

  /// Applies [dictionary] if it is newer than what is on screen. Payloads can
  /// overtake each other — a live message can beat the context queued before
  /// it — so the timestamp decides, not arrival order.
  private func merge(_ dictionary: [String: Any]) {
    guard let next = WatchTilePayload(dictionary: dictionary) else { return }
    if let current = payload, current.sentAt > next.sentAt { return }
    payload = next
    // Optimistic tags belong to the shot they were tapped on; anything for
    // another shot is dead weight.
    pendingTags = pendingTags.filter { $0.key == next.shotId }
  }

  private func publish(_ change: @escaping (WatchLinkStore) -> Void) {
    if Thread.isMainThread {
      change(self)
    } else {
      DispatchQueue.main.async { change(self) }
    }
  }
}

// MARK: - WCSessionDelegate

extension WatchLinkStore: WCSessionDelegate {
  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error = error {
      NSLog("watch: activation failed — \(error.localizedDescription)")
    }
    guard activationState == .activated else { return }
    adopt(session.receivedApplicationContext)
    let reachable = session.isReachable
    publish { store in
      store.phoneReachable = reachable
      if reachable { store.requestSync() }
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    publish { store in
      store.phoneReachable = reachable
      if reachable { store.requestSync() }
    }
  }

  func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    adopt(applicationContext)
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    adopt(message)
  }

  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    adopt(message)
    replyHandler([:])
  }
}
