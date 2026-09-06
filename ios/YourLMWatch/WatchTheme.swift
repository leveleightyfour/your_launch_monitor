import SwiftUI

/// The phone's palette, transplanted.
///
/// These are the literal values from `lib/shared/theme.dart` — the watch is
/// the same product on a smaller screen, and a golfer glancing down mid-swing
/// should recognise it instantly. Only the accent varies, because the golfer
/// chooses it on the phone and it travels with every payload.
enum WatchTheme {
  static let background = Color(hex: "#0C0C10")!
  static let surface = Color(hex: "#12151E")!
  static let card = Color(hex: "#1A1A24")!
  static let border = Color(hex: "#2A2A32")!
  static let textMuted = Color(hex: "#9C9C9C")!
  static let textDimmed = Color(hex: "#848484")!
  static let defaultAccent = Color(hex: "#2DD4B0")!
  static let warning = Color(hex: "#F59E0B")!

  /// Label / value / unit, matching the phone's `AppTextStyles` trio as
  /// closely as the watch's system face allows. DM Sans isn't bundled here —
  /// SF's heavy weight with tabular figures reads the same way at a glance
  /// and costs the prototype nothing.
  static func label(_ size: CGFloat = 8.5) -> Font {
    .system(size: size, weight: .bold).width(.condensed)
  }

  static func value(_ size: CGFloat) -> Font {
    .system(size: size, weight: .heavy).monospacedDigit()
  }

  static func unit(_ size: CGFloat = 8) -> Font {
    .system(size: size, weight: .regular).italic()
  }

  static func footer(_ size: CGFloat = 8) -> Font {
    .system(size: size, weight: .medium).monospacedDigit()
  }
}

extension Color {
  /// `#RRGGBB` — the form the phone sends its accent in.
  init?(hex: String) {
    var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}
