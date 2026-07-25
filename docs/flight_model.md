# Ball Flight Model & 3D Flight View

The Omni measures the ball at impact only — ball speed, launch angle, launch
direction, total spin and spin axis. Everything that happens afterwards (carry,
apex, descent angle, curvature, how the ball behaves when it lands, where it
finishes) has to be simulated. This document covers the simulation and the 3D
view built on top of it.

How the simulation is checked — and what it is known to get wrong — is a
separate document: [`flight_model_validation.md`](flight_model_validation.md).

**Code map**

| Layer | File | Responsibility |
|---|---|---|
| Domain | `lib/features/launch_monitor/domain/entities/shot_trajectory.dart` | `BallFlightModel` integrator, `ShotTrajectory`, `TrajectoryPoint`, `Vec3` |
| Domain | `lib/features/launch_monitor/domain/entities/shot_data.dart` | `ShotData.trajectory` and the derived getters that read from it |
| Presentation | `lib/features/launch_monitor/presentation/widgets/tabs/flight_3d_tab.dart` | `Flight3DTab` — camera, renderer, replay |
| Tests | `test/features/launch_monitor/domain/entities/shot_trajectory_test.dart` | Behaviour and API: reference flights, curvature, roll, degenerate input |
| Tests | `test/features/launch_monitor/domain/entities/shot_trajectory_validation_test.dart` | Whether the physics is right — see the validation doc |

All distances in the domain layer are **yards**, speeds **mph**, angles
**degrees**. Unit conversion happens at the presentation layer via `UnitPrefs`.

---

## 1. The flight

`BallFlightModel.simulate()` integrates the ball's equations of motion with
RK4 at a 5 ms step, stopping when the ball returns to the ground and
interpolating the exact touchdown point. It then hands the touchdown state —
position, velocity *and* the spin left on the ball — to the ground phase in
§2.

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

---

## 2. The ground: bounce and roll

Spin does not stop mattering when the ball lands — it is most of what decides
whether a shot releases 25 yards or checks and comes back. So the ground phase
is simulated rather than estimated: the ball bounces, slides, then rolls, and
the spin it arrived with drives all three.

### The bounce

Each impact applies two impulses.

**Normal.** Rebound speed is `e × |v_n|`, with `e` from Penner's fit to
measured golf-ball/turf impacts:

```
e = 0.510 − 0.0375·v_n + 0.000903·v_n²
```

Fast, steep arrivals bury into the turf and barely rebound (e ≈ 0.12 at 17 m/s);
slow ones bounce (e ≈ 0.35 at 5 m/s). The turf preset scales it.

**Tangential.** This is where spin enters. The velocity of the ball's contact
patch is

```
u = v_tangential − r·(ω × n̂)
```

For a backspinning ball the patch is racing *forwards* — faster than the ball's
centre — so friction acts backwards, killing forward speed and the backspin
with it. Sidespin drives the patch sideways and the ball gets kicked the same
way. The impulse per unit mass is

```
j = min( (2/7)·|u| , μ·(1+e)·|v_n| )
```

the first term being what it takes to stop the patch slipping entirely (the
no-slip limit for a sphere), the second what friction can actually deliver.
Whichever binds, the same impulse both slows the ball (`Δv = −j·û`) and spins
it down (`Δω = 5j/(2r)·(n̂ × û)`). A steep wedge with 9,000 rpm hits the
friction limit and can have its forward speed reversed outright.

**Ploughing.** Friction alone under-predicts how much real turf takes: the ball
digs a pitch mark and has to climb out of it, and the crater wall pushes back
along the ground track. That is a reaction force, not friction, so it is not
capped by the no-slip limit:

```
dig = min( ploughing·|v_n| , 0.55·|v_tangential| )
```

It scales with how steeply the ball arrives, and it is capped as a *fraction*
of the speed the ball has. The fractional cap matters: an earlier version
scaled as `v_n²/v_tangential`, which blew up as the ball slowed and let a
bouncy surface kill the ball dead on its fourth, gentlest hop.

### Sliding and rolling

Between bounces the ball is integrated as a normal flight. On the ground it
slides while the contact patch is still slipping — the same friction law,
applied continuously — until `u` reaches zero, then rolls with rolling
resistance only, spin locked to `ω = (n̂ × v)/r`. A ball still carrying
backspin when it settles can therefore walk backwards before it rolls forwards,
which is exactly what a spinning wedge does on a green.

### Turf presets

| Preset | Ploughing | Friction | Rolling resistance | Restitution scale |
|---|---|---|---|---|
| `fairway` (default) | 0.19 | 0.40 | 0.42 | 1.00 |
| `green` | 0.26 | 0.50 | 0.32 | 0.70 |
| `firm` (links) | 0.11 | 0.34 | 0.26 | 1.25 |
| `rough` | 0.45 | 0.60 | 1.10 | 0.45 |

Fairway was fitted against the tour carry-to-total deltas — roll RMS 2.5 yd
across driver through pitching wedge. Ball–turf friction was pinned to Penner's
measured 0.40 rather than fitted, so the spin-to-turf coupling stays physical
and only the two turf-deformation terms absorb the fit. The other presets are
scaled from it by hand, and are ordered as you would expect:
`rough < green < fairway < firm`.

The surface is currently fixed to `fairway`. `BallFlightModel.copyWith(ground:)`
switches it; there is no user-facing control yet.

### Roll and the device

A device-reported `ShotData.run` still wins. The bounce is simulated anyway for
its *shape*, then the whole ground path is scaled so its downrange extent
matches the measurement — the 3D view shows a plausible bounce sequence that
still totals exactly what the device said.

`roll` is the downrange (target-line) distance gained after touchdown, matching
how `carry` is measured, so `totalDistance == carry + roll` always holds. It
can be negative when a steep, spinning shot comes back.

---

## 3. What reads from the model

`ShotData` caches one simulation per shot (via an `Expando`, so the class stays
`const`-constructible) and derives:

| Getter | Source |
|---|---|
| `carry` | simulation |
| `lateralOffset` | simulation — includes curvature, not just the start line |
| `totalDistance` | carry + roll |
| `apexHeight` | device `apex`, else simulation |
| `rollDistance` | device `run`, else the simulated bounce and roll |
| `curveDistance` | sideways yards gained in the air, measured from the start line |
| `descentAngle` | simulation |

`ShotTrajectory` also exposes `groundPoints` (the bounce-and-roll path),
`bounces`, `landingSpin`, `landingSpeed`, `groundTime` and `restPosition`.

> **Note:** `carry` and `lateralOffset` previously used a vacuum-ballistic
> approximation with a flat 20% lift fudge, which over-read carry by roughly
> 15–20% and ignored curvature entirely. Every view that shows carry or
> dispersion moved with them, so those numbers are now both smaller and
> consistent with the 3D view.

---

## 4. The 3D view

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
selected shot changes, then carries on through the bounce and roll — the
ground phase is compressed to at most 1.8 s so a long release doesn't stretch
the animation. The replay button re-runs it. The trails toggle overlays
previous shots with the same club.

**Scaling.** The view is used as a full tab, as one half of a split, and as a
pane on a phone, so a `_Density` tier is derived from the available size and
everything keys off it: 7 stats shrink to 4 and then 3, camera chips drop their
labels, stroke widths and label sizes scale, and the apex label and grid
numbers are dropped when there is no room for them. The camera frames into the
area the control strip does *not* cover rather than the raw viewport, so the
shot stays clear of the chips at every size.

**Clipping.** Everything is clipped against the near plane — segments by
interpolation, polygons by Sutherland–Hodgman — so nothing wraps around when
the camera is close to the ground.

**Cost.** Paths are batched: the flight, its shadow, the curtain and the
bounce path are one `Path` each, so the glow pass is a single blurred draw
rather than one per segment. The simulation itself is cached per shot.
