# Ball Flight Model & 3D Flight View

The Omni measures the ball at impact only — ball speed, launch angle, launch
direction, total spin and spin axis. Everything that happens afterwards (carry,
apex, descent angle, curvature, where the ball finishes) has to be simulated.
This document covers the simulation and the 3D view built on top of it.

**Code map**

| Layer | File | Responsibility |
|---|---|---|
| Domain | `lib/features/launch_monitor/domain/entities/shot_trajectory.dart` | `BallFlightModel` integrator, `ShotTrajectory`, `TrajectoryPoint`, `Vec3` |
| Domain | `lib/features/launch_monitor/domain/entities/shot_data.dart` | `ShotData.trajectory` and the derived getters that read from it |
| Presentation | `lib/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart` | `Flight3DTab` — camera, renderer, replay |
| Tests | `test/features/launch_monitor/domain/entities/shot_trajectory_test.dart` | Reference flights, curvature, roll, degenerate input |

All distances in the domain layer are **yards**, speeds **mph**, angles
**degrees**. Unit conversion happens at the presentation layer via `UnitPrefs`.

---

## 1. The simulation

`BallFlightModel.simulate()` integrates the ball's equations of motion with
RK4 at a 5 ms step, stopping when the ball returns to the ground and
interpolating the exact touchdown point.

Three forces act on the ball:

| Force | Expression |
|---|---|
| Gravity | `-g ŷ` |
| Drag | `-½ρA/m · C_d · \|v\| · v` |
| Magnus | `½ρA/m · C_l · \|v\|² · (ŝ × v̂)` |

with a conforming ball (45.93 g, 42.67 mm) in sea-level ISA air
(1.225 kg/m³), no wind.

### Coordinate frame

`+x` right of the target line, `+y` up, `+z` downrange. A right-handed frame,
so `x̂ × ŷ = ẑ`.

### Spin axis

Pure backspin is perpendicular to both the velocity and vertical
(`ŝ₀ = v̂ × ŷ`). The measured spin axis rotates that vector about the velocity
using Rodrigues' formula, so a **positive spin axis curves the ball right** —
matching the launch-monitor convention. The spin vector direction is fixed at
launch (angular momentum is conserved); only its magnitude decays, with a 24 s
time constant.

### Coefficients

Both coefficients are functions of the spin ratio `S = ωr/v`:

```
C_d = dragBase + dragPerSpin·S + dragAtLowSpeed·max(0, (55 − v)/55)
C_l = liftMax·S / (liftHalfSpin + S)
```

The `dragAtLowSpeed` term captures the drag crisis: a dimpled ball sits in the
low-drag supercritical regime at driver speeds and drifts back towards
subcritical drag as it slows.

The constants were fitted by grid search against Trackman tour averages
(driver through pitching wedge) on carry, apex, descent angle and hang time
simultaneously. Current accuracy:

| Club | Carry (sim / ref) | Apex | Descent | Hang time |
|---|---|---|---|---|
| PGA driver | 262 / 275 | 32 / 32 | 40 / 38 | 6.6 / 6.4 |
| LPGA driver | 211 / 218 | 25 / 25 | 37 / 37 | 5.7 / 5.7 |
| 3-wood | 247 / 243 | 30 / 30 | 40 / 43 | 6.5 / 6.2 |
| 5-iron | 206 / 195 | 34 / 31 | 46 / 46 | 6.6 / 6.2 |
| 7-iron | 173 / 172 | 30 / 32 | 45 / 50 | 6.0 / 6.1 |
| 9-iron | 149 / 152 | 29 / 30 | 48 / 51 | 5.7 / 5.8 |
| Pitching wedge | 134 / 136 | 30 / 29 | 50 / 52 | 5.6 / 5.6 |

Every club is within 6% on carry. The reference numbers are themselves
averages taken across a range of venues and conditions, so treat the residuals
as the noise floor rather than a target to fit away. The test suite enforces
8% on carry, 4.5 yards on apex, 6° on descent and 0.6 s on hang time — change
a coefficient and it will tell you what broke.

### Roll

The device does not report roll. When `ShotData.run` is null the model
estimates it from the landing angle: a ~30° descent runs out about 12% of its
carry, a ~50° wedge only 4%, capped at 15%. A device-reported `run` always
wins.

---

## 2. What reads from the model

`ShotData` caches one simulation per shot (via an `Expando`, so the class stays
`const`-constructible) and derives:

| Getter | Source |
|---|---|
| `carry` | simulation |
| `lateralOffset` | simulation — includes curvature, not just the start line |
| `totalDistance` | carry + roll |
| `apexHeight` | device `apex`, else simulation |
| `rollDistance` | device `run`, else estimate |
| `curveDistance` | sideways yards gained in the air, measured from the start line |
| `descentAngle` | simulation |

> **Note:** `carry` and `lateralOffset` previously used a vacuum-ballistic
> approximation with a flat 20% lift fudge, which over-read carry by roughly
> 15–20% and ignored curvature entirely. Every view that shows carry or
> dispersion moved with them, so those numbers are now both smaller and
> consistent with the 3D view.

---

## 3. The 3D view

`Flight3DTab` renders the flight with a `CustomPainter` and about 120 lines of
projection maths — no 3D engine, no extra dependency.

**Camera.** A pinhole camera orbits the shot: yaw, pitch, and a distance found
by fitting. Because the shot has to stay on screen from any angle, the fit
bisects on distance for the closest camera that keeps every sampled flight
point inside a safe margin, then nudges the principal point so the *projected*
shot is centred and re-fits into the space that frees up. (Scaling the distance
by the overflow directly does not converge — points near the camera grow much
faster than 1/distance.)

Presets: **Behind**, **Side**, **Angled**, **Top**, and **Follow** (a chase cam
locked to the ball). Drag to orbit, pinch to zoom, double-tap to reset.

**Scene.** Ground plane with a fairway strip and a distance grid on the
display-unit lattice (25 yd or 25 m), a target line, the flight itself, its
ground shadow, a faint curtain between the two for depth, an apex marker, and
landing rings with a dashed roll-out to where the ball comes to rest.

**Replay.** The flight draws itself in at ~1.15× real time whenever the
selected shot changes; the replay button re-runs it. The trails toggle overlays
previous shots with the same club.

**Clipping.** Everything is clipped against the near plane — segments by
interpolation, polygons by Sutherland–Hodgman — so nothing wraps around when
the camera is close to the ground.

**Cost.** Paths are batched: the flight, its shadow and the curtain are one
`Path` each, so the glow pass is a single blurred draw rather than one per
segment.
