import SwiftUI

/// The phone's tag picker, wrist-sized.
///
/// One row per tag, tapped to toggle it on the shot currently shown. The
/// change lands immediately and is only corrected if the phone refuses it —
/// standing over a ball is the wrong moment to wait on a round trip.
///
/// Tagging is by the shot's database id, not by "the current shot", so a tag
/// applied a moment after the shot lands still goes on the shot that was
/// being looked at even if the phone's selection has moved on since.
struct TagSheet: View {
  @EnvironmentObject private var store: WatchLinkStore
  @Environment(\.dismiss) private var dismiss

  let payload: WatchTilePayload

  var body: some View {
    let selected = store.tags(for: payload)

    ScrollView {
      VStack(spacing: 4) {
        header

        if payload.tags.isEmpty {
          MessageRow(text: "No tags yet. Create them on the phone.")
        } else if payload.shotId == 0 {
          MessageRow(text: "No shot to tag yet.")
        } else {
          ForEach(payload.tags) { tag in
            Button {
              store.toggleTag(tag, on: payload)
            } label: {
              row(tag: tag, isOn: selected.contains(tag.id))
            }
            .buttonStyle(.plain)
          }
        }

        if let error = store.commandError {
          Text(error.uppercased())
            .font(WatchTheme.label(9))
            .tracking(0.9)
            .foregroundStyle(WatchTheme.warning)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
        }
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 8)
    }
    .background(WatchTheme.background)
  }

  private var header: some View {
    HStack(spacing: 4) {
      Text("TAG SHOT")
        .font(WatchTheme.label(10))
        .tracking(1.1)
        .foregroundStyle(WatchTheme.textMuted)
      if payload.hasShot {
        Text("\(payload.shotIndex)/\(payload.shotCount)")
          .font(WatchTheme.footer(9))
          .foregroundStyle(WatchTheme.textDimmed)
      }
      Spacer(minLength: 2)
      Button { dismiss() } label: {
        Text("DONE")
          .font(WatchTheme.label(9))
          .tracking(0.9)
          .foregroundStyle(payload.accent)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
  }

  private func row(tag: WatchTag, isOn: Bool) -> some View {
    HStack(spacing: 8) {
      Circle()
        .fill(tag.color)
        .frame(width: 10, height: 10)

      Text(tag.name)
        .font(.system(size: 14, weight: isOn ? .semibold : .regular))
        .foregroundStyle(isOn ? .white : WatchTheme.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.6)

      Spacer(minLength: 2)

      // A checkmark rather than a toggle: the row is the control, and a
      // switch at this size is a target you miss with a glove on.
      Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 15))
        .foregroundStyle(isOn ? payload.accent : WatchTheme.border)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity)
    .background(
      isOn ? WatchTheme.surface : WatchTheme.card,
      in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct MessageRow: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12))
      .foregroundStyle(WatchTheme.textMuted)
      .multilineTextAlignment(.center)
      .padding(.vertical, 12)
      .padding(.horizontal, 8)
  }
}

#Preview {
  TagSheet(
    payload: WatchTilePayload(
      connection: .connected,
      tiles: [],
      shotCount: 12,
      shotIndex: 12,
      club: "7i",
      tags: [
        WatchTag(id: 1, name: "Draw", color: .green),
        WatchTag(id: 2, name: "Thin", color: .orange),
      ],
      shotTags: [1],
      shotId: 42
    )
  )
  .environmentObject(WatchLinkStore.shared)
}
