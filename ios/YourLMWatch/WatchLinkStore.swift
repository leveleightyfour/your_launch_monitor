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
