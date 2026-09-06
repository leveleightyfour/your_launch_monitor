import SwiftUI

/// Your Launch Monitor, on the wrist.
///
/// A companion, not a second app: it holds no database, talks to no launch
/// monitor and computes nothing. The iPhone sends it a screen and it draws
/// it. Everything that decides what a tile says — which metrics, which units,
/// which club, which shot — is settled on the phone.
@main
struct YourLMWatchApp: App {
  @StateObject private var store = WatchLinkStore.shared

  var body: some Scene {
    WindowGroup {
      TilesScreen()
        .environmentObject(store)
    }
  }
}
