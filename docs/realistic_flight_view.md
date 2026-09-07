# Realistic flight view

Profile → Preferences → **3D flight view** selects Classic or Realistic. The
selection is stored in `unit_prefs.json`; older installs and unknown values use
Classic. Every `Flight3DTab` reads the same preference, including saved sessions,
split panes and both session screen layouts. Changing style preserves the mounted
view's camera, selected shot, trails and replay position.

The new painters live in `realistic_flight_painters.dart`, a part of the existing
flight-view library so they can reuse its private camera/projection helpers.
Constructor selection changes the art direction, while launch physics, bounce,
roll, sample timing, camera fitting and controls stay shared.

Realistic adds world-anchored sun/moon, soft clouds, a layered distant skyline,
broadleaf tree canopies, terrain detail, range boards and a shaded golf ball.
Custom hole terrain keeps its exact cell boundaries and pin placement, with
colours coordinated to the selected sky. All five sky scenes are supported.
The analytic grid and translucent flight curtain are omitted in Realistic;
carry/apex annotations, the shot tracer and comparison trails remain available.

## Rendering budget

- Flutter Canvas only; no new packages, downloaded scenery, native renderer,
  texture files or shader compilation requirements.
- Separate repaint boundaries retain the existing static world / animated flight
  split. Only Follow makes the world listen to the replay clock. No idle scenery
  animation is introduced.
- Procedural surface detail examines at most 676 candidates per scene repaint,
  reduced to 324 in compact panes and Follow. It rejects offscreen/distant points
  and fades them by camera depth. Placement is deterministic in world space.
- Custom-hole trees reuse the existing per-grid stand cache and draw every
  visible tree back to front, without a nearest-tree count cap. Visibility uses
  the full projected canopy, trunk and shadow against the canvas clip bounds.
  Crowns with a projected radius up to 5 logical pixels use three flat-colour
  lobes and no shadow; shadows fade in between radii of 5 and 10 pixels. Crowns
  below 12 pixels and compact/Follow views use three lobes; larger crowns use
  seven. Analytic holes use up to 36 decorative trees outside their fairway and
  green, with the same bounds checks and screen-size detail.
- The new animated tracer and ball use ordinary strokes and radial gradients;
  they do not use `MaskFilter.blur`, `saveLayer`, lighting/shadow maps or animated
  reflections. Device pixel ratio does not increase procedural object counts.

This remains a perspective Canvas visualization, not a photorealistic 3D engine.
The ground is flat to match the flight model. Trees are decorative, and the shot
layer stays visible over foliage, as in Classic. The custom hole's rectangular
terrain edges are preserved rather than inventing different landing surfaces.
Surface detail is capped; tree cost scales with the visible stand and projected
size. These optimizations are not a measured FPS guarantee.

## Validation

Run the preference and widget checks plus the existing flight regressions:

```sh
flutter test test/shared/flight_view_style_pref_test.dart \
  test/features/launch_monitor/presentation/realistic_flight_test.dart \
  test/features/launch_monitor/presentation/flight_3d_controls_test.dart \
  test/features/launch_monitor/presentation/flight_trails_test.dart \
  test/features/launch_monitor/presentation/replay_timing_test.dart \
  test/features/launch_monitor/presentation/mow_bands_test.dart
```

Before release, profile on a representative Android phone and iPhone with
`flutter run --profile`. In DevTools Performance, record replay, orbit and Follow
for both styles on the same shot, first in a full tab and then in a split pane.
Include a densely wooded custom hole, short chips and driver shots. Inspect UI
and raster frame durations against the device refresh budget (16.7 ms at 60 Hz),
plus memory and sustained thermal behaviour. Check all skies and restart the app
after changing Profile to confirm persistence on device. Desktop/widget-test
rendering does not establish mobile GPU performance.
