import Foundation
import SwiftUI

/// A screen's worth of tiles, exactly as the phone formatted them.
///
/// Nothing here is computed on the watch: the iPhone has already applied the
/// golfer's unit preferences, worked out the session average and split the
/// direction letter off the number. The watch's whole job is layout, which is
/// what keeps the two screens from ever disagreeing about a shot.
///
/// Decoding is hand-written rather than `Codable` because WatchConnectivity
/// delivers property-list dictionaries, not JSON, and a payload that gains a
/// field must not stop an older watch build from drawing the fields it does
/// understand.
struct WatchTile: Identifiable, Equatable {
  let id: String
  let label: String
  let value: String
  let suffix: String
  let unit: String
  let average: String
  let delta: String
  let secondaryLabel: String
  let secondaryValue: String

  /// True for the impact-location tile, the one metric drawn as two stacked
  /// readouts instead of a single number.
  var isSplit: Bool { !secondaryValue.isEmpty }

  init?(dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? String,
      let label = dictionary["label"] as? String,
      let value = dictionary["value"] as? String
    else { return nil }
    self.id = id
    self.label = label
    self.value = value
    self.suffix = dictionary["suffix"] as? String ?? ""
    self.unit = dictionary["unit"] as? String ?? ""
    self.average = dictionary["average"] as? String ?? ""
    self.delta = dictionary["delta"] as? String ?? ""
    self.secondaryLabel = dictionary["secondaryLabel"] as? String ?? ""
    self.secondaryValue = dictionary["secondaryValue"] as? String ?? ""
  }

  init(
    id: String, label: String, value: String, suffix: String = "", unit: String = "",
    average: String = "", delta: String = "", secondaryLabel: String = "",
    secondaryValue: String = ""
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.suffix = suffix
    self.unit = unit
    self.average = average
    self.delta = delta
    self.secondaryLabel = secondaryLabel
    self.secondaryValue = secondaryValue
  }

  /// The footer line under the value: the session average and this shot's
  /// distance from it, the same sentence the phone prints.
  var footer: String {
    if isSplit {
      return average.isEmpty ? "" : "AVG \(average)"
    }
    switch (average.isEmpty, delta.isEmpty) {
    case (true, _): return ""
    case (false, true): return "AVG \(average)"
    case (false, false): return "AVG \(average) · \(delta)"
    }
  }
}

/// One of the golfer's tags: a coloured dot and a name, plus the id the
/// watch sends back when it's tapped.
struct WatchTag: Identifiable, Equatable {
  let id: Int
  let name: String
  let color: Color

  init?(dictionary: [String: Any]) {
    guard let id = (dictionary["id"] as? NSNumber)?.intValue,
      let name = dictionary["name"] as? String
    else { return nil }
    self.id = id
    self.name = name
    self.color = Color(hex: dictionary["color"] as? String ?? "") ?? WatchTheme.textMuted
  }

  init(id: Int, name: String, color: Color) {
    self.id = id
    self.name = name
    self.color = color
  }
}

enum WatchConnection: String {
  case disconnected, scanning, connecting, connected

  var label: String {
    switch self {
    case .disconnected: return "DISCONNECTED"
    case .scanning: return "SCANNING"
    case .connecting: return "CONNECTING"
    case .connected: return "CONNECTED"
    }
  }

  var isLive: Bool { self == .connected }
}

struct WatchTilePayload: Equatable {
  let connection: WatchConnection
  let tiles: [WatchTile]
  let shotCount: Int
  let shotIndex: Int
  let club: String
  let accent: Color
  let battery: Int?
  let ballReady: Bool

  /// Every tag the golfer has, and the ones already on the shot on screen.
  let tags: [WatchTag]
  let shotTags: Set<Int>

  /// Database id of the shot being shown. Zero means there is nothing the
  /// watch could tag — no shot yet, or one the phone hasn't persisted.
  let shotId: Int

  let sentAt: Date

  init?(dictionary: [String: Any]) {
    // A payload without tiles is not a screen; ignore it rather than
    // blanking whatever the watch is already showing.
    guard let rawTiles = dictionary["tiles"] as? [[String: Any]] else { return nil }
    self.tiles = rawTiles.compactMap(WatchTile.init(dictionary:))
    self.connection =
      WatchConnection(rawValue: dictionary["connection"] as? String ?? "") ?? .disconnected
    // Numbers arrive as NSNumber whichever side sent them, so they are read
    // through it rather than cast straight to Int/Double.
    self.shotCount = (dictionary["shotCount"] as? NSNumber)?.intValue ?? 0
    self.shotIndex = (dictionary["shotIndex"] as? NSNumber)?.intValue ?? 0
    self.club = dictionary["club"] as? String ?? ""
    self.accent = Color(hex: dictionary["accent"] as? String ?? "") ?? WatchTheme.defaultAccent
    self.battery = (dictionary["battery"] as? NSNumber)?.intValue
    self.ballReady = (dictionary["ballReady"] as? NSNumber)?.boolValue ?? false
    self.tags = (dictionary["tags"] as? [[String: Any]] ?? []).compactMap(WatchTag.init(dictionary:))
    self.shotTags = Set((dictionary["shotTags"] as? [NSNumber] ?? []).map { $0.intValue })
    self.shotId = (dictionary["shotId"] as? NSNumber)?.intValue ?? 0
    let ms =
      (dictionary["sentAtMs"] as? NSNumber)?.doubleValue
      ?? Date().timeIntervalSince1970 * 1000
    self.sentAt = Date(timeIntervalSince1970: ms / 1000)
  }

  init(
    connection: WatchConnection, tiles: [WatchTile], shotCount: Int, shotIndex: Int,
    club: String, accent: Color = WatchTheme.defaultAccent, battery: Int? = nil,
    ballReady: Bool = false, tags: [WatchTag] = [], shotTags: Set<Int> = [],
    shotId: Int = 0, sentAt: Date = Date()
  ) {
    self.connection = connection
    self.tiles = tiles
    self.shotCount = shotCount
    self.shotIndex = shotIndex
    self.club = club
    self.accent = accent
    self.battery = battery
    self.ballReady = ballReady
    self.tags = tags
    self.shotTags = shotTags
    self.shotId = shotId
    self.sentAt = sentAt
  }

  var hasShot: Bool { shotIndex > 0 }

  /// Whether the shot on screen can be tagged from here: it exists on the
  /// phone, and there are tags to put on it.
  var canTag: Bool { shotId > 0 && !tags.isEmpty }
}
