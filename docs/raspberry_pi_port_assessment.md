# Raspberry Pi Port Assessment

Whether this app can run on a Raspberry Pi 5 (Raspberry Pi OS 64-bit) with BLE
intact, what stands in the way, and the order to do it in.

**Scope confirmed with the owner before writing:**

| Question | Answer | Consequence |
|---|---|---|
| Camera tab on the Pi? | **Required** — OpenCV capture and impact clips must work | OpenCV must be built for arm64; drives the embedder choice |
| Display / input | **Touchscreen**, resolution to be confirmed | The app's Linux branches currently assume a desktop with a mouse |
| Shorebird OTA | **Not needed** — the Pi updates by rebuild | No work; already degrades cleanly |
| Share / export | **Local-folder export matters**, sharing does not | `share_plus` file sharing must be replaced on Linux |

Everything below was checked against the actual package sources pulled from
pub.dev at the versions in `pubspec.lock`, not inferred from package names.

**Code map**

| Area | File | Relevance |
|---|---|---|
| BLE port selection | `lib/features/launch_monitor/data/ble_adapter_factory.dart` | Chooses the adapter per platform |
| BLE implementation | `lib/features/launch_monitor/data/flutter_blue_plus_adapter.dart` | The only adapter Linux would use |
| Startup | `lib/main.dart` | BLE priming, migration, app boot |
| Camera pipeline | `lib/features/launch_monitor/application/camera_providers.dart` | Device enumeration, probe, backend selection |
| Capture worker | `lib/features/launch_monitor/application/camera_capture_worker.dart` | OpenCV `VideoCapture` in an isolate |
| Layout gating | `lib/shared/theme.dart` | `isDesktopPlatform`, `isCameraCapturePlatform`, breakpoints |
| Export | `lib/shared/services/clip_export_service.dart`, `csv_export_service.dart` | OpenCV `VideoWriter`, `share_plus` |

---

## 1. Verdict

**Feasible with significant caveats — and the caveats are concentrated in one
place: OpenCV, not BLE.**

The BLE half of this port is close to free. The camera half is the whole
project.

Three findings decide it:

1. **BLE needs essentially no work.** `flutter_blue_plus_linux` 7.0.3 is
   already resolved in `pubspec.lock` as a transitive dependency, and — the
   part that matters — it is a **Dart-only plugin**. Its pubspec declares
   `dartPluginClass: FlutterBluePlusLinux` with no native code at all; it
   talks to BlueZ through the pure-Dart `bluez` + `dbus` packages. There is no
   C++ platform side to port to flutter-pi. Separately, this app's
   `BleAdapter` interface is unusually narrow — scan, connect, discover,
   subscribe, read, write, disconnect — and touches none of the calls that
   normally break on BlueZ (see §4).

2. **The camera path is the real port.** `opencv_dart` / `dartcv4` 2.2.1+4 is
   not a Flutter plugin at all — it is an FFI package built through Dart
   **build hooks** (`hooks/user_defines` in `pubspec.yaml`), which compile
   OpenCV from source with CMake and ship it as a native asset. That is a
   third category your (a)/(b)/(c) taxonomy doesn't cover, and it behaves
   differently from both: there is no platform folder to port, but the build
   system must support native assets end to end. dartcv4 does declare a Linux
   CMake generator, so Linux is a supported target upstream — the risk is the
   embedder's build path, not the library.

3. **Linux is already half-wired, in ways that are currently wrong.**
   `isDesktopPlatform` (`lib/shared/theme.dart:303`) already returns `true` on
   Linux, and `isCameraCapturePlatform` (`:315`) includes it. So a Linux build
   would today attempt the full OpenCV camera pipeline and render the
   mouse-and-window desktop layout — on a touchscreen. These are not missing
   branches to add; they are existing branches that need to be re-decided now
   that the target is a touch panel.

Nothing found is architecturally fatal. There is no Android-only lifecycle
assumption, no `permission_handler` anywhere in the tree, no background
service, no foreground-service notification, and no method channel that Linux
needs (the two custom channels are Apple-only). The database, routing, state
management, theming, and the entire domain layer are pure Dart and port
untouched.

---

## 2. Plugin inventory

165 hosted packages resolve in `pubspec.lock`. 30 declare native platform
code; the remaining 135 are pure Dart and port as-is.

### (a) Pure Dart — works anywhere

All direct dependencies in this class need no attention:
`cupertino_icons`, `drift`, `drift_flutter`, `flutter_riverpod`, `go_router`,
`lucide_icons_flutter`, `path`, `riverpod_annotation`, `riverpod_devtools`,
`google_fonts`, plus every transitive package not listed below.

Two carry a caveat despite being pure Dart:

- **`google_fonts` 6.3.3** fetches DM Sans and IBM Plex Mono over HTTP at
  runtime and caches them under `path_provider`. On a Pi with no network — a
  realistic kiosk — the first launch silently falls back to Roboto and the
  app looks wrong. Not a blocker; see the mitigation table.
- **`shorebird_code_push` 2.0.6** is FFI into a symbol that only exists in the
  Shorebird-patched engine. It degrades correctly: `isAvailable` catches the
  lookup failure and returns `false`
  (`shorebird_updater_io.dart:33-43`), and the service already guards every
  entry point on it (`shorebird_update_service.dart:44,49,57`). The app's own
  doc comment already says "False on platforms Shorebird does not patch
  (desktop, web)". **No work needed**, consistent with your answer that the Pi
  updates by rebuild.

### (b) Plugin with an existing Linux implementation

| Package | Version | Linux mechanism | Notes |
|---|---|---|---|
| `flutter_blue_plus` → `flutter_blue_plus_linux` | 1.36.8 → 7.0.3 | **Dart-only** (`dartPluginClass`), via `bluez`/`dbus` | No native code. See §4 |
| `path_provider` → `path_provider_linux` | 2.1.5 → 2.2.1 | Dart-only, XDG dirs | Works |
| `sqlite3_flutter_libs` | 0.5.42 | Native (CMake), bundles SQLite | Already in `linux/flutter/generated_plugins.cmake` |
| `file_selector` → `file_selector_linux` | 1.1.0 → 0.9.4 | Native GTK file chooser | **Needs a display server — see blocker B4** |
| `share_plus` | 13.2.1 | Dart, delegates to `url_launcher_linux` | **Throws on file shares — see blocker B5** |
| `restart_app` | 1.8.3 | Native | Declared for Linux; unused on Pi (Shorebird is off) |
| `url_launcher_linux` | 3.2.2 | Native GTK | Pulled in only by `share_plus` |

### (c) Plugin with native code but no Linux implementation

| Package | Version | Used for | Runtime dependency on Linux? |
|---|---|---|---|
| **`camera`** | 0.11.4 | **Device *names* only** — `availableCameras()` at `camera_providers.dart:108`. Capture is OpenCV, not this plugin | **No — already fails safe.** The call is wrapped at `camera_providers.dart:574-578`, which catches and continues with an empty name list ("Names are a nicety"). But see blocker B2: the empty list shrinks the probe range |
| `camera_windows` | 0.2.6+4 | Nothing. Declared in `pubspec.yaml` but the file that would use it explains at length why it doesn't (`camera_providers.dart:1-9`) | No — dead weight, safe to drop |
| `camera_android_camerax`, `camera_avfoundation`, `camera_web` | — | Endorsed `camera` implementations | No — mobile paths only |
| `flutter_native_splash` | 2.4.7 | Build-time asset generator | No — never called at runtime |
| `flutter_plugin_android_lifecycle` | 2.0.35 | Android glue for `camera` | No |
| `file_selector_*`, `path_provider_*`, `url_launcher_*` (android/ios/macos/windows/web) | — | Federated siblings | No — inert off-platform |
| **`win_ble`** | 1.1.1 | Windows BLE backend | **No.** It is a pure-Dart package that shells out to a bundled `BLEServer.exe`, and `ble_adapter_factory.dart:9` only reaches it when `Platform.isWindows`. It compiles on Linux and is never constructed. It does bundle the `.exe` asset into every build, including the Pi's — wasted space, not a failure |

### (d) FFI via build hooks — the category that actually matters

| Package | Version | Mechanism |
|---|---|---|
| **`opencv_dart` → `dartcv4`** | 2.2.1+4 | Dart **build hooks** + CMake, producing a native asset |

`dartcv4`'s own pubspec declares per-platform CMake generators including
`linux: {generator: Unix Makefiles}`, so Linux is an upstream-supported
target. This repo's `pubspec.yaml` overrides the module list to
`imgproc`, `imgcodecs`, `videoio` — a deliberately minimal build, which works
in your favour on a Pi.

This is used by `camera_capture_worker.dart` (`VideoCapture`, `rotate`,
`flip`, `imencode`, `cvtColor`) and `clip_export_service.dart`
(`VideoWriter`). It is the single hardest dependency in the port.

---

## 3. Platform-specific code

Every `Platform.*` / `defaultTargetPlatform` check, method channel, and event
channel in `lib/`, with what it should do on Linux.

### Blocking or wrong on Linux

| Location | Current behaviour | What it should do on Linux |
|---|---|---|
| `lib/shared/theme.dart:303-307` | `isDesktopPlatform` returns **true** on Linux | **Re-decide.** Drives windowed-desktop layout and hover affordances. On a touch panel this should be false, or better, split into `isPointerPlatform` (mouse present) and `isLargeScreenLayout` (window size) — the two are conflated today and only the second is true on a Pi touchscreen |
| `lib/shared/theme.dart:315-317` | `isCameraCapturePlatform` includes Linux via `isDesktopPlatform` | Must stay true (camera is required), but it must stop being derived from `isDesktopPlatform` once that flips, or the camera tab vanishes |
| `camera_tab.dart:1420, 1441` | Export-folder picker row is inert when `!isDesktopPlatform` | If `isDesktopPlatform` flips to false, the Pi silently loses the "choose export folder" control — the exact feature you said matters. Must be gated on a capability, not on "is desktop" |
| `camera_providers.dart:65-69` | `_backend` switch falls through to `capAny` for Linux | Should be `CAP_V4L2` (200). `capAny` lets OpenCV probe backends in an arbitrary order, and on Linux the first hit can be GStreamer, which behaves differently for property queries |
| `camera_providers.dart:108` | `availableCameras()` — `camera` has no Linux impl | Needs a Linux name source. `/sys/class/video4linux/video*/name` is a two-line pure-Dart read and also gives the correct index range (blocker B2) |

### Correct as-is on Linux, no action needed

| Location | Behaviour | Why it's fine |
|---|---|---|
| `ble_adapter_factory.dart:9` | `if (Platform.isWindows) return WinBleAdapter(); return FlutterBluePlusAdapter();` | Linux correctly falls through to flutter_blue_plus. **No change required** |
| `main.dart:22` | `if (!Platform.isWindows)` → Linux runs `setLogLevel` + `_primeBlePermissions()` | `setLogLevel` is implemented in the Linux backend. The 50 ms priming scan is a no-op on Linux (no permission model) and both calls are individually try/caught at `main.dart:46-51` |
| `macos_data_migration.dart:44` | `if (!Platform.isMacOS) return;` | Returns immediately on Linux |
| `database.dart:410` | macOS-only Application Support branch | Linux takes the default `driftDatabase(name:)` path → XDG documents dir via `path_provider_linux`. Correct |
| `shorebird_update_service.dart:89` | `quitOnlyRestart => Platform.isIOS` | False on Linux; the whole service is inert because `isAvailable` is false |
| `camera_providers.dart:73, 313, 317` | `MethodChannel('omni_sniffer/apple_cameras')`, `MethodChannel('omni_sniffer/native_camera')`, `EventChannel('omni_sniffer/native_camera/frames')` | **All three are Apple-only.** Guarded at `:82-83` and `:329-330` by explicit `TargetPlatform.macOS`/`iOS` checks, and implemented in `ios/Runner/AppDelegate.swift` and `macos/Runner/MainFlutterWindow.swift`. **Linux needs no channel work at all** — this is the finding that makes flutter-pi even thinkable |
| `clip_export_service.dart:73, 81` | iOS exclusions in the video-writer codec ladder | Linux takes the full ladder. The `avc1`/AVFoundation rung will simply fail to open on Linux and the ladder moves on to MJPG AVI, which is the design |
| `camera_tab.dart:866-871, 925-926, 1259-1261` | Platform-specific help copy | Linux falls to the generic "Plug in a USB camera" string — correct, though `_localDestinationName` (`:1259`) has no Linux case and will read awkwardly |
| `session_screen.dart:290`, `session_screen_v2.dart:246` | `PopScope` protecting the finish flow from the system back gesture | Linux has no system back gesture, so this never fires. Harmless — but it means the on-screen X button is the **only** exit from a session on the Pi. Worth a manual check that it's reachable at your panel size |
| `profile_screen.dart:424` | `Switch.adaptive` | Resolves to Material on Linux. Fine |

**Method/event channels: three exist, all Apple-only, none need a Linux
implementation.** There is no `permission_handler` dependency anywhere in the
tree, no `WidgetsBindingObserver`, and no `AppLifecycleState` handling —
so there are no mobile lifecycle assumptions to unwind.

---

## 4. BLE layer

**Current version: `flutter_blue_plus` 1.36.8**, resolving
`flutter_blue_plus_linux` **7.0.3** transitively. This is comfortably new
enough — the federated Linux implementation has been endorsed since the 1.35
line, and 7.0.3 is the current Linux implementation for it.

### The Linux implementation is complete

I read all 1,138 lines of `flutter_blue_plus_linux.dart`. It contains **zero**
`UnimplementedError`, `UnsupportedError`, or `TODO` markers. Every method this
app's adapter reaches is implemented against BlueZ:

| App call (`flutter_blue_plus_adapter.dart`) | Linux backend | Status |
|---|---|---|
| `FlutterBluePlus.startScan(timeout:)` `:22` | `adapter.startDiscovery()` + discovery filter | Works. The `timeout` is enforced **Dart-side** in the core package (`flutter_blue_plus.dart:351-352` sets a `Timer` that calls `stopScan`), so it is backend-independent |
| `FlutterBluePlus.stopScan()` `:68` | `adapter.stopDiscovery()` | Works |
| `device.connect(autoConnect: false)` `:76` | `device.connect()` | Works — and `autoConnect: false` is the right choice, see below |
| `device.connectionState` `:83` | `onConnectionStateChanged` from BlueZ property changes | Works |
| `device.discoverServices()` `:92` | Full GATT walk | Works |
| `char.setNotifyValue(true)` `:151` | `startNotify` | Works |
| `char.onValueReceived` `:153` | `onCharacteristicReceived` | Works |
| `char.read()` / `char.write()` `:162, 173` | `readValue` / `writeValue` | Works |
| `FlutterBluePlus.setLogLevel` (`main.dart:23`) | Implemented | Works |

### Nothing in this app needs porting away from

The `BleAdapter` interface (`ble_adapter.dart:29-76`) is deliberately narrow,
and that pays off here. Checked and **absent from the entire codebase**:

- **No runtime permission requests.** `permission_handler` is not a
  dependency. The only permission-adjacent code is `_primeBlePermissions()`
  (`main.dart:41-52`), which is just a 50 ms scan whose only purpose is to
  trigger the *mobile* OS prompt. On Linux it is a harmless no-op.
- **No Android-specific scan settings.** No `androidScanMode`, no
  `AndroidScanMode`, no `withServices` filter — `scan()` passes only a
  timeout, and filtering happens in Dart on name and manufacturer data
  (`providers.dart:174-186`).
- **No MTU calls.** `requestMtu` appears nowhere. (It is also not implemented
  in the Linux backend — BlueZ negotiates MTU itself and exposes no setter —
  so this is a lucky escape rather than a designed one.)
- **No connection priority.** `requestConnectionPriority` is Android-only and
  is not called.
- **`autoConnect` is explicitly `false`** (`flutter_blue_plus_adapter.dart:76`).
  This is the correct value for Linux; `autoConnect: true` has no BlueZ
  equivalent and behaves differently across backends.
- **No background or foreground service handling.** No
  `WidgetsBindingObserver`, no `AppLifecycleState`, no foreground-service
  notification. The app assumes it is always in the foreground — which is
  exactly true on a Pi kiosk.

### Three real BlueZ behaviour differences

These are not blockers, but they will produce confusing symptoms if unknown.

1. **Scan results only report *newly discovered* devices.**
   `flutter_blue_plus_linux.dart:222-223` maps `_client.deviceAdded`. BlueZ
   keeps known devices in its object tree after a scan ends, and a device
   already in that tree does **not** re-fire `deviceAdded`. Practical effect:
   the Square Golf unit appears in the picker on first scan after boot, then
   may never appear again until BlueZ ages it out. Mitigation is
   `getSystemDevices` (implemented at `:525`), which returns BlueZ's known
   devices and should be merged into the picker list on Linux.

2. **Auto-reconnect will fail on a cold boot.** `_maybeAutoReconnect()`
   (`providers.dart:124-144`) connects straight to the stored device ID
   without scanning first. On Linux, `connect` does
   `_client.devices.singleWhere((d) => d.remoteId == request.remoteId)`
   (`flutter_blue_plus_linux.dart:296-299`), which **throws `StateError`** if
   BlueZ has never seen that device in this session. The call is already
   `silent: true` and fails open, so the app won't crash — auto-reconnect will
   just quietly never work until a manual scan has run. Fix is a scan-then-
   connect path on Linux, or relying on BlueZ's own pairing/trust so the
   device is already in the tree at boot.

3. **Manufacturer data is present but arrives once.** Good news first:
   `manufacturerData` **is** populated on Linux (`:232-236`), so
   `detectDeviceType()` and the Omni magic-bytes match
   (`providers.dart:180-184`) will work. But because the mapping is on
   `deviceAdded`, later advertisement updates don't re-emit — the values seen
   at first discovery are the ones you get.

### One deployment prerequisite, not a code change

BlueZ access over D-Bus is governed by polkit. The user running the app needs
to be in the `bluetooth` group, and pairing/trusting the Square Golf device
once via `bluetoothctl` will make points 1 and 2 above largely moot.

---

## 5. UI assumptions

The layout is in better shape than a mobile-first app usually is: there is no
`Cupertino*` widget anywhere (one `Switch.adaptive` at
`profile_screen.dart:424`, which resolves to Material on Linux), and the
screens are built on `LayoutBuilder` breakpoints rather than fixed sizes.

### Touch vs pointer

You confirmed a **touchscreen**, which makes the `isDesktopPlatform` problem
described in §3 the main UI issue. Concretely:

- 15 usages of `MouseRegion` / `onHover` / `SystemMouseCursors` across the
  presentation layer. Hover-only affordances are invisible on a touch panel —
  anything that *only* reveals on hover needs a persistent equivalent.
- `camera_tab.dart:1420, 1441` — the export-destination row's edit affordance
  and its `onTap` are both `null` unless `isDesktopPlatform`. Flip that flag
  for touch and you lose folder selection; leave it and you keep a hover
  affordance nobody can see. This needs an explicit decision, which is why it
  is blocker B4.
- `theme.dart:360-369` — `dualCameraPrefersOwnRow` requires
  `isDesktopPlatform`, so the two-camera layout changes shape with that flag.

### Safe areas and system gestures

- 16 `SafeArea` usages. On Linux `MediaQuery.padding` is all zeros, so these
  become no-ops — harmless, but it means `app_shell.dart:26,40` places the
  floating pill nav just 16 px from the physical bottom edge. On a bezelled
  panel that can be genuinely hard to hit. Check this against your enclosure.
- `PopScope` at `session_screen.dart:290` and `session_screen_v2.dart:246`
  exists to stop the system back gesture skipping the session-finish
  confirmation. **Linux has no system back gesture**, so this protection never
  fires and the on-screen X is the only exit. Not a bug — but verify the X is
  reachable at your resolution.

### Target display resolution — what I need from you

This is the one thing I could not determine from the code, and it decides
several layout outcomes. The app's real breakpoints are:

| Breakpoint | Location | What flips |
|---|---|---|
| `shortestSide >= 600` | `theme.dart:289` | Tablet layout |
| `shortestSide >= 600 && aspect >= 1.9` | `theme.dart:295-296` | Ultra-wide layout |
| `maxWidth >= 1000` | `session_screen_v2.dart:267` | Session screen goes two-pane |
| `maxWidth >= 640` | `camera_tab.dart:235` | Camera tab side-by-side |
| `maxWidth >= 600` | `club_tab.dart:58` | Club tab wide layout |
| `maxWidth >= 520` | `camera_tab.dart:2000` | Camera control row vs column |
| `360 min / 540 comfortable` per pane | `theme.dart:_minPaneWidth`, `_comfortPaneWidth` | How many panes fit |
| `height * 0.85` | `tiles_tab.dart:735` | Sheet max height |

**Please tell me four things:**

1. **Native panel resolution in physical pixels** (e.g. 1280×800, 1024×600,
   1920×1080). The common 7" Pi touchscreens are 800×480 — which is *below*
   the 600 `shortestSide` threshold and below the 640 camera-tab breakpoint,
   meaning you'd get the phone layout and a stacked camera tab on a landscape
   display. That would need new breakpoints, not just a config change.
2. **Orientation** — landscape is assumed; portrait would change which
   breakpoints bind.
3. **Intended `flutter-pi` pixel ratio / scale factor.** flutter-pi lets you
   set this independently of the panel, and it divides the logical resolution
   the breakpoints see. A 1920×1080 panel at ratio 2.0 presents as 960×540
   logical — under the 1000 two-pane threshold.
4. **Physical panel size in inches**, so touch targets can be sized properly.
   The current tap targets are tuned for a phone held at arm's length, not a
   panel behind a hitting mat.

Give me those and I can tell you exactly which screens need new breakpoints
rather than guessing.

---

## 6. Blockers and mitigations

| # | Blocker | Severity | Mitigation |
|---|---|---|---|
| **B1** | **`opencv_dart`/`dartcv4` must build for arm64 Linux via Dart build hooks.** This compiles OpenCV from source with CMake. Whether the chosen embedder's build path supports native assets is the single biggest unknown in this port | **High** | Prove it first, before any other work (see §8 step 1). The module list is already minimal (`imgproc`, `imgcodecs`, `videoio`). Expect a long first build; cross-compile from an x86 host or build once and cache. If native assets turn out to be unsupported in your embedder, the fallbacks are (a) pre-build `libdartcv.so` for arm64 and load it manually, or (b) replace the capture path with GStreamer/V4L2 |
| **B2** | **Camera enumeration returns nothing on Linux, which silently shrinks the probe range.** `availableCameras()` (`camera_providers.dart:108`) throws; the catch at `:574-578` continues with an empty list; then `limit = names.length + _probeOvershoot` (`:645`) evaluates to **2**, so only `/dev/video0` and `/dev/video1` are probed. On a Pi many drivers expose two nodes per camera (capture + metadata), and the Pi additionally has `video10`–`video16` for its codecs — so with two USB cameras the second one may simply never be found | **High** | Add a Linux branch to `_deviceNames()` reading `/sys/class/video4linux/video*/name`. Pure Dart, no new dependency, and it fixes both the names and the index range in one change. Drop `camera` and `camera_windows` from `pubspec.yaml` at the same time — neither is used for capture |
| **B3** | **`_backend` resolves to `capAny` on Linux** (`camera_providers.dart:65-69`), letting OpenCV pick the V4L2/GStreamer backend nondeterministically | Medium | Add `TargetPlatform.linux => capV4l2` (200) to the switch. One line, and it makes `CAP_PROP_FRAME_WIDTH/HEIGHT/FPS/FOURCC` behave predictably |
| **B4** | **Folder picker needs a display server.** `file_selector_linux` 0.9.4 is a native **GTK** plugin, used at `camera_tab.dart:1444` for the export destination — which you confirmed matters. Under flutter-pi there is no GTK, X11, or Wayland, so this cannot work. It also sits behind `isDesktopPlatform`, which is the flag you'd flip for touch | **High** (given export matters) | Under flutter-elinux with a Wayland/X11 backend, it works as-is. Under flutter-pi, replace it with an in-app folder browser (pure Dart over `dart:io`) or a fixed configured path — a GTK dialog on a bare-DRM touchscreen would be a poor experience regardless. Decouple the row's gating from `isDesktopPlatform` either way |
| **B5** | **`share_plus` throws on Linux for file shares.** `share_plus_linux.dart:24` is literally `throw UnimplementedError('Sharing files not supported on Linux')`. Hit by `csv_export_service.dart:69` and `protocol_capture_export.dart:52`, both of which pass `files:` | Medium | Both call sites already `try`/`catch` and surface an error message, so nothing crashes — the feature just fails. Since you want local-folder export rather than sharing, add a Linux branch that writes to the configured export directory and shows a confirmation. `saved_holes_sheet.dart:362` shares **text only**, which routes to a `mailto:` URL via `url_launcher_linux` — it won't throw, but it needs a registered mail handler, so hide it on Linux too |
| **B6** | **`isDesktopPlatform` is true on Linux but the target is a touchscreen** (`theme.dart:303-307`), driving desktop layout, hover-only affordances, and the gating in B4 | Medium | Split the concept. `isDesktopPlatform` currently answers two different questions — "is there a mouse?" and "is this a big resizable window?" — and on a Pi touch panel the answers differ. Introduce `isPointerPlatform` and keep size decisions on `LayoutBuilder`. Mechanical change, but it touches several call sites |
| **B7** | **Unknown display resolution.** Common Pi panels (800×480) fall below the `shortestSide >= 600` and `maxWidth >= 640` breakpoints, which would give you the phone layout and a stacked camera tab | Medium | Blocked on your answer to §5. May require new breakpoints rather than configuration |
| **B8** | **`google_fonts` fetches over HTTP at first run.** Offline Pi → silent fallback to Roboto | Low | Bundle DM Sans and IBM Plex Mono as assets and use `GoogleFonts.config.allowRuntimeFetching = false`. Also makes startup deterministic |
| **B9** | **`win_ble` bundles `BLEServer.exe` into every build**, including the Pi's | Low | Cosmetic. Move `win_ble` behind a conditional import, or accept the wasted space |
| **B10** | **BlueZ scan/reconnect semantics** differ as described in §4 — devices appear only once, and cold-boot auto-reconnect throws internally | Low | Merge `getSystemDevices` into the picker list on Linux; pair and trust the device once with `bluetoothctl` |

---

## 7. Recommended embedder

**Recommendation: the standard Flutter Linux desktop embedder — via
`flutter-elinux` if you want the Wayland/DRM backends, or plain
`flutter build linux` on Raspberry Pi OS Desktop.**

**Reasoning, in the order the reasons actually matter:**

1. **The camera requirement decides this.** With OpenCV mandatory, you need a
   build path that supports Dart build hooks / native assets. `flutter build
   linux` on a recent SDK (this repo pins Dart ≥ 3.12, Flutter ≥ 3.44 —
   `pubspec.lock:1344-1346`) supports them. flutter-pi's toolchain
   (`flutterpi_tool`) has **no documentation of native-asset support at all** —
   I checked its README and found no mention of native assets,
   `dartPluginClass`, or the Dart plugin registrant. That is not proof it
   fails, but it is an unproven path for the hardest dependency in the port,
   and the first thing you should test if you want to pursue it.
2. **Export needs a file picker.** `file_selector_linux` is GTK. Under the
   desktop embedder it works today; under flutter-pi it cannot, and you'd
   have to build an in-app browser (B4).
3. **The scaffolding already exists.** `linux/` is present and tracked
   (`linux/runner/my_application.cc`, `CMakeLists.txt`,
   `generated_plugin_registrant.cc`), currently registering
   `file_selector_linux`, `restart_app`, `sqlite3_flutter_libs`, and
   `url_launcher_linux`. It is stock scaffolding — window title still
   `omni_sniffer`, default 1280×720 (`my_application.cc:50,56`) — but it is a
   working starting point, not a blank slate.
4. **flutter-pi's genuine advantage does not apply here.** Its selling point
   is running with no compositor on constrained hardware. A Pi 5 is not
   constrained, and the moment you need OpenCV, GTK file dialogs, and a
   full-screen touch UI, the desktop embedder's compatibility is worth more
   than flutter-pi's lower overhead.

**The one thing that would change this recommendation:** if you drop the
camera requirement, flutter-pi becomes genuinely attractive — because
`flutter_blue_plus_linux` is Dart-only, a BLE-only build of this app would
need **no plugin porting whatsoever**. That is a rare position to be in, and
worth remembering if the camera work proves too costly.

**If you want flutter-pi anyway**, test in this order and stop at the first
failure: (1) native assets — does `dartcv4` build and does `cv.VideoCapture`
resolve its symbols? (2) Dart plugin registrant — does
`FlutterBluePlusLinux.registerWith()` actually get called? (3) `sqlite3_flutter_libs`
— the one native plugin you cannot avoid, since the whole database depends on
it. Kiosk mode on the desktop embedder (`gtk_window_fullscreen`, hidden
cursor, autostart unit) gets you most of flutter-pi's user-facing benefit
without any of its porting risk.

---

## 8. Migration plan

Each step leaves the Android and iOS builds fully working. Steps 1–3 are
investigation and repo hygiene with no behavioural change; the risky work is
deliberately front-loaded into step 1 so you find out early if the port is
affordable.

**Step 0 — Establish the baseline.** Record what Android/iOS do today so
every later step can be checked against it. Confirm `flutter test` is green
before touching anything.
*Mobile impact: none.*

**Step 1 — Prove OpenCV builds for arm64 Linux. Do this before anything
else.** In a scratch Flutter app with only `opencv_dart` as a dependency, on
the Pi 5, build and call `cv.VideoCapture.fromDevice(0)` against a USB camera.
This single experiment answers the port's biggest unknown (B1). If it fails,
stop and reconsider before spending effort on the rest. Do it in a throwaway
project so this repo stays untouched.
*Mobile impact: none — no repo changes.*

**Step 2 — Answer the open questions.** Panel resolution, orientation, pixel
ratio, physical size (§5). Cheap, and it determines how much of step 7 is
real work.
*Mobile impact: none.*

**Step 3 — Remove dead weight.** Drop `camera` and `camera_windows` from
`pubspec.yaml` and replace `availableCameras()` with a per-platform name
source. `camera` is used **only** for device names, and its failure is already
caught — so removing it changes nothing on any platform while eliminating a
whole class-(c) dependency. Include the `/sys/class/video4linux` reader for
Linux here (B2), since it is the same edit.
*Mobile impact: none — mobile capture never used the `camera` plugin. Verify
Android/iOS device names still populate via their existing paths.*

**Step 4 — First Linux build, BLE only.** Build for the desktop embedder,
launch, and connect to the Square Golf unit. Expect the camera tab to be
broken; ignore it. This is where §4's three BlueZ behaviours get confirmed or
disproved on real hardware, and where you learn whether BLE really is as
close to free as the source reading suggests.
*Mobile impact: none — Linux-only build target.*

**Step 5 — Fix BLE for BlueZ.** Merge `getSystemDevices` into the picker list
and add a scan-then-connect path for auto-reconnect on Linux (B10). Both are
additive Linux branches in `flutter_blue_plus_adapter.dart` and
`providers.dart`.
*Mobile impact: none if gated on `Platform.isLinux`. Regression-test the
mobile picker and auto-reconnect anyway, since these files are shared.*

**Step 6 — Camera on Linux.** Set the V4L2 backend (B3), wire up the probe
range from step 3's enumeration, and get a live preview. Then the impact-clip
ring buffer, then `VideoWriter` export — in that order, because each depends
on the previous one working.
*Mobile impact: none if the backend switch adds a `TargetPlatform.linux` case
rather than changing existing ones.*

**Step 7 — Touch UI pass.** Split `isDesktopPlatform` into pointer-vs-layout
concepts (B6), re-gate the export-folder row (B4), audit the 15 hover-only
affordances, and apply whatever breakpoint changes step 2's answers demand
(B7).
*Mobile impact: this is the step with real regression risk — `theme.dart`'s
flags are read across the presentation layer. Do it last, keep
`isDesktopPlatform`'s value unchanged for Windows/macOS, and lean on the
existing `test/shared/split_pane_breakpoint_test.dart` while adding cases for
the Pi's resolution.*

**Step 8 — Export and polish.** Replace the `share_plus` file path with a
write-to-configured-directory branch on Linux (B5), bundle the fonts (B8), and
set up kiosk mode — fullscreen, hidden cursor, systemd autostart. Update
`linux/runner/my_application.cc`, whose window title and 1280×720 default are
still Flutter's scaffolding.
*Mobile impact: none if the export change is a Linux branch alongside the
existing share path.*

**Deliberately not in this plan:** anything touching Shorebird (inert on
Linux, and you don't need it), `win_ble` (B9 is cosmetic), and the Apple
method channels (Linux never reaches them).
