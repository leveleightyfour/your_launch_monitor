import SwiftUI

/// One metric, drawn the way the phone draws it: small-caps label on top, the
/// number as large as the tile allows, unit under it, and the session average
/// in a pill at the foot.
///
/// The digit size is passed in rather than measured per tile. That is the one
/// rule the phone's grid is built on — every tile in view shares a size, set
/// by the widest value on show — and it is what stops a grid of numbers from
/// looking like a ransom note.
struct MetricTileView: View {
  let tile: WatchTile
  let accent: Color
  let valueSize: CGFloat

  /// Focus mode drops the grid's compromises: one tile, whole screen, every
  /// supporting line it can carry.
  var expanded = false

  var body: some View {
    VStack(spacing: expanded ? 6 : 1) {
      Text(tile.label)
        .font(WatchTheme.label(expanded ? 11 : 8.5))
        .tracking(1.1)
        .foregroundStyle(WatchTheme.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      if tile.isSplit {
        splitValue
      } else {
        value
      }

      // The unit line is laid out even for a metric that hasn't got one —
      // smash factor is the only one today. Dropping the row shortens the
      // whole card, and one card a line shorter than its neighbours reads
      // as broken rather than as tidy. A single space occupies exactly one
      // line of the style. The phone's tiles keep this same rule, and for
      // the same reason.
      Text(tile.unit.isEmpty ? " " : tile.unit)
        .font(WatchTheme.unit(expanded ? 11 : 8))
        .foregroundStyle(WatchTheme.textDimmed)

      // Likewise the average pill: hidden rather than removed, so a metric
      // with nothing to compare against yet still stands as tall as the
      // rest of the grid.
      Text(tile.footer.isEmpty ? " " : tile.footer)
        .font(WatchTheme.footer(expanded ? 10 : 8))
        .foregroundStyle(WatchTheme.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(WatchTheme.surface, in: Capsule())
        .opacity(tile.footer.isEmpty ? 0 : 1)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 5)
    .padding(.vertical, expanded ? 10 : 6)
    .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: expanded ? 16 : 12))
  }

  /// The number at full size with any direction letter half-size beside it,
  /// sharing a baseline — `1.1° R`, not a shrunken `1.1° R`.
  private var value: some View {
    HStack(alignment: .firstTextBaseline, spacing: valueSize * 0.06) {
      Text(tile.value)
        .font(WatchTheme.value(valueSize))
        .foregroundStyle(isBlank ? WatchTheme.textDimmed : .white)
      if !tile.suffix.isEmpty {
        Text(tile.suffix)
          .font(WatchTheme.value(valueSize * 0.55))
          .foregroundStyle(accent)
      }
    }
    .lineLimit(1)
    .minimumScaleFactor(0.4)
  }

  /// The impact tile: two readouts, one above the other, split by a hairline.
  private var splitValue: some View {
    VStack(spacing: 2) {
      impactRow(label: "HORIZ", text: tile.value)
      Rectangle()
        .fill(WatchTheme.border)
        .frame(height: 1)
      impactRow(
        label: tile.secondaryLabel.isEmpty ? "VERT" : tile.secondaryLabel,
        text: tile.secondaryValue)
    }
  }

  private func impactRow(label: String, text: String) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(WatchTheme.label(7.5))
        .tracking(0.8)
        .foregroundStyle(WatchTheme.textDimmed)
      Spacer(minLength: 2)
      Text(text)
        .font(WatchTheme.value(valueSize * 0.62))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
  }

  private var isBlank: Bool { tile.value == "--" }
}

#Preview {
  MetricTileView(
    tile: WatchTile(
      id: "carry", label: "CARRY", value: "265.4", unit: "yds", average: "258.1",
      delta: "±7.3"),
    accent: WatchTheme.defaultAccent,
    valueSize: 22
  )
  .padding()
  .background(WatchTheme.background)
}
