import SwiftUI

/// The watch face of a practice session: the phone's Tiles tab, two columns
/// wide, glanceable between swings.
///
/// Tap any tile to blow it up full-screen and swipe between them — at address
/// with a club in hand, one number the size of the watch beats six the size
/// of a fingernail.
struct TilesScreen: View {
  @EnvironmentObject private var store: WatchLinkStore
  @State private var focus: FocusSelection?

  var body: some View {
    ZStack {
      WatchTheme.background.ignoresSafeArea()
      content
    }
    .onAppear { store.activate() }
    .fullScreenCover(item: $focus) { selection in
      FocusPager(startID: selection.id)
        .environmentObject(store)
    }
  }

  @ViewBuilder
  private var content: some View {
    if let payload = store.payload {
      if payload.tiles.isEmpty {
        MessageView(
          title: "NO TILES SELECTED",
          detail: "Pick metrics in Customize on the phone.")
      } else {
        grid(payload)
      }
    } else {
      MessageView(
        title: store.isRequesting ? "SYNCING…" : "WAITING FOR IPHONE",
        detail: "Open Your Launch Monitor on your phone.")
    }
  }

  private func grid(_ payload: WatchTilePayload) -> some View {
    GeometryReader { geometry in
      let columns = payload.tiles.count == 1 ? 1 : 2
      let tileWidth = (geometry.size.width - 8 - CGFloat(columns - 1) * 6) / CGFloat(columns)
      let valueSize = Self.sharedValueSize(for: payload.tiles, tileWidth: tileWidth)

      ScrollView {
        VStack(spacing: 6) {
          SessionHeader(payload: payload)

          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: 6), count: columns),
            spacing: 6
          ) {
            ForEach(payload.tiles) { tile in
              MetricTileView(tile: tile, accent: payload.accent, valueSize: valueSize)
                .onTapGesture { focus = FocusSelection(id: tile.id) }
            }
          }

          LinkFooter(payload: payload)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
      }
    }
  }

  /// One digit size for the whole grid, set by the widest value on show —
  /// the same rule the phone's tiles follow. Heavy tabular digits run about
  /// 0.62em wide, which is what the divisor below is.
  static func sharedValueSize(for tiles: [WatchTile], tileWidth: CGFloat) -> CGFloat {
    let widest =
      tiles
      .filter { !$0.isSplit }
      .map { $0.value.count + ($0.suffix.isEmpty ? 0 : 1) }
      .max() ?? 3
    let usable = max(tileWidth - 12, 24)
    return min(max(usable / (0.62 * CGFloat(widest)), 11), 30)
  }
}

/// Wraps a tile id so `fullScreenCover(item:)` can carry it.
private struct FocusSelection: Identifiable {
  let id: String
}

// MARK: - Header

/// Club, shot number, device state — the context a bare number can't carry.
private struct SessionHeader: View {
  let payload: WatchTilePayload

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(statusColor)
        .frame(width: 6, height: 6)

      if !payload.club.isEmpty {
        Text(payload.club.uppercased())
          .font(WatchTheme.label(10))
          .tracking(1)
          .foregroundStyle(.white)
      }

      Spacer(minLength: 2)

      if payload.hasShot {
        Text("\(payload.shotIndex)/\(payload.shotCount)")
          .font(WatchTheme.footer(10))
          .foregroundStyle(WatchTheme.textMuted)
      } else if payload.connection.isLive {
        Text(payload.ballReady ? "READY" : "NO SHOTS")
          .font(WatchTheme.label(9))
          .tracking(0.8)
          .foregroundStyle(payload.ballReady ? payload.accent : WatchTheme.textMuted)
      }

      if let battery = payload.battery {
        Text("\(battery)%")
          .font(WatchTheme.footer(9))
          .foregroundStyle(battery <= 15 ? WatchTheme.warning : WatchTheme.textDimmed)
      }
    }
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }

  private var statusColor: Color {
    switch payload.connection {
    case .connected: return payload.ballReady ? payload.accent : payload.accent.opacity(0.55)
    case .connecting, .scanning: return WatchTheme.warning
    case .disconnected: return WatchTheme.textDimmed
    }
  }
}

// MARK: - Footer

/// What the link is doing, and a way to ask for fresh numbers. Only ever
/// shown when there is something worth saying — a live, in-range session
/// gets the whole screen for its tiles.
private struct LinkFooter: View {
  @EnvironmentObject private var store: WatchLinkStore
  let payload: WatchTilePayload

  var body: some View {
    if let message = message {
      Button(action: store.requestSync) {
        Text(message)
          .font(WatchTheme.label(9))
          .tracking(0.9)
          .foregroundStyle(WatchTheme.textMuted)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 5)
          .background(WatchTheme.surface, in: Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  private var message: String? {
    if store.isRequesting { return "SYNCING…" }
    if !store.phoneReachable { return "PHONE OUT OF RANGE · TAP TO RETRY" }
    if !payload.connection.isLive { return "\(payload.connection.label) · TAP TO REFRESH" }
    return nil
  }
}

// MARK: - Empty states

private struct MessageView: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 6) {
      Text(title)
        .font(WatchTheme.label(11))
        .tracking(1.2)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      Text(detail)
        .font(.system(size: 11))
        .foregroundStyle(WatchTheme.textMuted)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 10)
  }
}

#Preview {
  TilesScreen()
    .environmentObject(WatchLinkStore.shared)
}
