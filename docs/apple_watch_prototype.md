# Apple Watch companion (prototype)

A watchOS app that mirrors the session screen's tiles on the wrist, fed live
from the iPhone over WatchConnectivity.

It is deliberately a mirror, not a second app. The watch holds no database,
speaks no BLE and computes nothing: the phone formats a whole screen — which
metrics, in which order, in the golfer's units, with the session average
behind each one — and the watch draws it. That is what keeps the two screens
from ever disagreeing about what a shot carried.

**Code map**

| Layer | File | Responsibility |
|---|---|---|
| Domain | `lib/features/launch_monitor/domain/entities/watch_tile_payload.dart` | `WatchTilePayload`, `WatchTile`, `WatchTag` — the wire format |
| Application | `lib/features/launch_monitor/application/tile_formatting.dart` | `metricValue` / `tileUnit` / `splitValueSuffix` — the formatters the phone's tiles use, moved here so the watch can share them |
| Application | `lib/features/launch_monitor/application/watch_sync_provider.dart` | Builds the payload from session state; throttles and pushes it |
| Data | `lib/features/launch_monitor/data/watch_connectivity_channel.dart` | The `omni_sniffer/watch` method channel, `WatchLinkState`, `WatchCommand` |
| iOS | `ios/Runner/WatchBridge.swift` | `WCSession` on the phone side |
| watchOS | `ios/YourLMWatch/` | The watch app: SwiftUI tiles, tag sheet, `WatchLinkStore` |
| Project | `ios/tool/add_watch_target.rb` | Recreates the watch target in `Runner.xcodeproj` |
| Tests | `test/features/launch_monitor/application/watch_payload_test.dart` | Tile mapping, wire format, link state |

---

## 1. What the watch shows

Two columns of tiles, in the order set by **Customize** on the phone, under a
header carrying the club, the shot number within the session, the device
battery and a connection dot. Tapping a tile opens it full screen; swipe to
move between tiles and tap again to return. One number the size of the watch
is what a golfer standing over the ball can actually read.

Colours are the phone's: background `#0C0C10`, cards `#1A1A24`, and the
golfer's chosen accent, which travels with every payload. Type is SF at heavy
weight with tabular figures rather than the phone's DM Sans — the font is not
bundled into the watch app, and at a glance the difference does not register.
Every tile in a grid shares one digit size set by the widest value on show,
the same rule the phone's tiles follow.

States it can be in:

- **WAITING FOR IPHONE** — nothing has ever arrived.
- **PHONE OUT OF RANGE** — tap to retry; the last received screen stays up.
- **DISCONNECTED / SCANNING / CONNECTING** — the launch monitor's state, from
  the phone. Tap to refresh.

## 2. How the data travels

```
LaunchMonitor state ─┐
selectedTiles        ├─► watchTilePayloadProvider ─► WatchConnectivityChannel
UnitPrefs, accent    │        (formatted strings)      │  MethodChannel
club, selected shot ─┘                                 ▼
                                              WatchBridge.swift (WCSession)
                                                       │
                              updateApplicationContext  │  sendMessage
                                          (state)       │  (live, when reachable)
                                                       ▼
                                             WatchLinkStore ─► TilesScreen
```

Two transports, deliberately:

- `updateApplicationContext` carries **state**. The system keeps only the
  newest one and hands it over whenever the watch app next runs, so opening
  the app shows the last shot rather than a spinner.
- `sendMessage` carries the **same payload again** when the watch is
  reachable, because context delivery happens at the system's convenience and
  a shot should land on the wrist immediately.

The watch can also ask: on launch, and whenever the phone becomes reachable,
it sends `{"request": "sync"}`. The bridge answers instantly from the last
payload it sent and asks Dart for a fresh one, which follows moments later.

Payloads are throttled to one per 300 ms with a trailing send, and identical
payloads are dropped (`WatchTilePayload.signature` ignores the timestamp), so
an idle session costs no radio.

Only property-list types cross the boundary — WatchConnectivity rejects
anything else, `null` included, so absent values (an unknown battery) are
omitted rather than sent empty.

## 3. Tagging a shot from the wrist

The one thing that travels watch → phone. A bar under the header shows what
the shot on screen is tagged with — which is usually the question between
swings, rather than wanting to tag something — and opens the tag list when
tapped.

```
watch: toggleTag(shotId, tagId, on)  ──►  WatchBridge  ──►  Dart WatchSync
                                                                   │
       optimistic tag drawn immediately                  updateShotTags(...)
                     ▲                                             │
                     └────── reply {ok} ◄── fresh payload ◄────────┘
```

Three things make it behave under real conditions:

- **Tagging is by database id, not by "the current shot."** A shot lands, the
  golfer tags it a moment later, and by then the phone's selection may have
  moved on. The id puts the tag on the shot they were looking at. A shot the
  phone hasn't persisted yet reports `shotId: 0` and the watch treats it as
  untaggable rather than failing after the tap.
- **The tap draws immediately** and is corrected only if the phone refuses.
  Optimistic state is keyed by shot id, so it can never bleed onto the next
  shot; the phone's follow-up payload replaces it.
- **The phone is the authority.** It re-checks that the shot is still in the
  session and the tag still exists, then goes through the same
  `updateShotTags` path as the phone's own tag picker, so the database and
  every other surface see one code path. A refusal comes back as a sentence
  the watch can show.

Commands are a closed set with a named action — the wrist is a remote control
for the phone's session, not a second author of it.

## 4. Building and running it

The watch target lives in `ios/Runner.xcodeproj` as `YourLMWatch`
(`com.leveleightyfour.YourLaunchMonitor.watchkitapp`), embedded into
`Runner.app/Watch/`. `flutter build ios` and `flutter run` build it as a
dependency of Runner; nothing about the normal workflow changes.

To run it on a watch: open `ios/Runner.xcworkspace`, pick the **YourLMWatch**
scheme and a paired watch or watch simulator. Run the iPhone app alongside it —
the tiles only populate once the phone app is running, since that is where the
payload comes from.

Xcode is not required to modify the project: `ios/tool/add_watch_target.rb`
rebuilds the target from scratch and is safe to re-run (`gem install
xcodeproj` first). If the target is ever lost to a merge or a Flutter
regeneration, run it again.

**Prototype limits, deliberately left open:**

- The watch app icon is the iPhone app's 1024px artwork. watchOS masks icons
  to a circle; this one is centred with clear margins so nothing clips, but
  the device reads small at 45mm and would carry further as a tighter crop.
- Signing is Automatic on this target while the iPhone target is Manual. A
  store build needs a provisioning profile for the watch bundle id; without
  one, archiving fails on the watch target rather than the app.
- Tagging is the only command the watch can send: no arming the device, no
  changing club, no starting or finishing a session.
- No complications, no always-on refresh, no background delivery beyond what
  application context gives for free.

To remove it entirely: delete the `YourLMWatch` target and the *Embed Watch
Content* phase in Xcode, or restore `ios/Runner.xcodeproj/project.pbxproj`
from git and delete `ios/YourLMWatch/`. Nothing else depends on it — the Dart
side is inert wherever the channel is absent.
