import SwiftUI

/// One tile, full screen, swipe for the next.
///
/// The grid is for reviewing a shot; this is for reading one number from
/// address position. It reads the tiles out of the store rather than being
/// handed a copy, so a shot landing while it is open updates it in place.
struct FocusPager: View {
  @EnvironmentObject private var store: WatchLinkStore
  @Environment(\.dismiss) private var dismiss

  let startID: String
  @State private var selection: String = ""

  var body: some View {
    let payload = store.payload
    let tiles = payload?.tiles ?? []

    ZStack {
      WatchTheme.background.ignoresSafeArea()

      TabView(selection: $selection) {
        ForEach(tiles) { tile in
          MetricTileView(
            tile: tile,
            accent: payload?.accent ?? WatchTheme.defaultAccent,
            valueSize: 44,
            expanded: true
          )
          .padding(.horizontal, 6)
          .tag(tile.id)
        }
      }
      .tabViewStyle(.page)
    }
    .onAppear { selection = startID }
    .onTapGesture { dismiss() }
  }
}
