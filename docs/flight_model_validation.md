# Validating the Flight Model

The Omni measures the ball for a few milliseconds after impact. Everything the
app shows about the rest of the shot — carry, apex, descent, curve, the bounce,
the roll, the 3D flight itself — is simulated. So "is the simulation right?" is
not a side question; it is the question that decides whether the numbers on
screen mean anything.

This document explains how that gets checked, what the current numbers are, and
what the model is known to get wrong. The executable form lives in
`test/features/launch_monitor/domain/entities/shot_trajectory_validation_test.dart`
— every claim below is asserted there and runs in CI.

---

## 1. Why reference data alone is not enough

The obvious way to validate a flight model is to feed it published launch
conditions and check the carry. That is necessary but weak, for three reasons:

- **It confounds layers.** If the carry is 5% low, is the integrator wrong, the
  drag law wrong, or the fitted constant wrong? Reference data cannot tell you.
- **It rewards overfitting.** With five free coefficients you can hit any seven
  reference points and still have a model that behaves absurdly two degrees
  outside the sampled range.
- **The references are noisy.** Trackman tour averages pool players, venues,
  altitudes, temperatures and balls. Treating them as ground truth to three
  significant figures is a mistake — the residuals below are partly *their*
  noise, not the model's.

So validation is layered, each layer testing something the layer above cannot.
A failure at a low layer invalidates everything above it.

| # | Layer | Question | Depends on reference data? |
|---|---|---|---|
| 1 | Integrator | Does the solver solve the equations? | No |
| 2 | Convergence | Is the answer independent of the time step? | No |
| 3 | Invariants | Does it respect physical bounds and symmetry? | No |
| 4 | Sensitivity | Does every input move the flight the right way? | No |
| 5 | Reference | Do published launch conditions give published flights? | Yes |
| 6 | Cross-model | Does an independently built model agree? | Indirectly |
| 7 | Field | Does it match *this user's* shots on *this* range? | User's own |

Layers 1–4 need no data at all, which is what makes them valuable: they are
falsifiable without appealing to anyone's authority.

---

## 2. Layer 1 — the integrator, against a closed form

Set drag and lift to zero and the equations of motion collapse to a parabola
with an exact solution:

```
range = v²·sin(2θ)/g     apex = v²·sin²θ/(2g)     time = 2v·sinθ/g
```

The model is run in that configuration and compared. This tests the RK4
integrator, the coordinate frame, the launch-vector construction, the
touchdown interpolation, and every unit conversion — with no aerodynamic
assumption involved. Anything but a near-exact match is a bug.

| Launch | Range error | Apex error | Time error | Descent error |
|---|---|---|---|---|
| 100 mph @ 10° | −0.0002% | −0.0004% | −0.0002% | 0.000° |
| 150 mph @ 20° | <0.0001% | <0.0001% | <0.0001% | 0.000° |
| 167 mph @ 30° | <0.0001% | <0.0001% | <0.0001% | 0.000° |
| 80 mph @ 45° | <0.0001% | <0.0001% | <0.0001% | 0.000° |
| 120 mph @ 60° | <0.0001% | <0.0001% | <0.0001% | 0.000° |

Two structural checks come with it: a ball with no spin finishes exactly on its
start line (no numerical drift sideways), and adding launch direction rotates
the whole flight rigidly — same ground distance, heading exactly as launched.

> **Note.** The drag coefficient is clamped to an upper bound only. It used to
> be clamped below at 0.15, which silently made the zero-drag configuration
> impossible and this entire layer untestable. That clamp was removed when this
> test was written — the first thing the validation suite caught.

## 3. Layer 2 — convergence

A number that changes when you change the time step is an artefact, not a
prediction. Driver carry (167 mph, 10.9°, 2686 rpm) against step size:

| Step | Carry (yd) | Change from previous |
|---|---|---|
| 0.04 s | 261.52167 | — |
| 0.02 s | 261.51127 | 0.0104 |
| 0.01 s | 261.50617 | 0.0051 |
| **0.005 s (shipped)** | **261.50360** | 0.0026 |
| 0.0025 s | 261.50227 | 0.0013 |
| 0.00125 s | 261.50160 | 0.0007 |

Discretisation error at the shipped step is under **three thousandths of a
yard** — six orders of magnitude below the model's accuracy against real data.

The convergence is first-order, not the fourth-order RK4 would suggest, and the
reason is worth recording: spin is held constant across each step and decayed
afterwards. Rerunning the sweep with spin decay disabled drops every delta to
round-off (≤1×10⁻⁵ yd), which confirms the diagnosis. Fixing it would buy
0.003 yd, so it stands — but if the integrator is ever reworked, evaluate spin
at the RK4 midpoints and the scheme recovers its natural order.

The ground phase is checked the same way: halving the step moves total distance
by less than half a yard.

## 4. Layer 3 — invariants

Bounds the model must respect whatever its coefficients are:

- **Terminal velocity.** A high, slow lob cannot land faster than
  `sqrt(2mg/ρACd)` ≈ 80 mph. Asserted against the model's own coefficient.
- **No free energy.** No airborne sample exceeds the launch speed. Drag can
  only take.
- **Drag costs distance.** With spin at zero so lift cannot mask it, the real
  model carries less than 75% of the vacuum equivalent.
- **Lift pays it back.** At driver launch conditions the full model carries more
  than 1.3× a lift-free ball — which is why a 10.9° launch works at all.
- **Mirror symmetry.** A shot launched 4° right with a +12° axis and one
  launched 4° left with a −12° axis produce identical carry and apex and
  exactly opposite offline, curve and rest position, to 1×10⁻⁹ yards. This
  catches any accidental left/right bias in the spin-axis construction, which
  is the easiest thing in the whole model to get subtly wrong.
- **Determinism.** Same input, byte-identical output. No RNG, no time
  dependence, no accumulated state.

## 5. Layer 4 — sensitivity

Reference data pins down a handful of points. Sensitivity testing constrains
the shape of the whole surface, which is what stops a well-fitted model being
nonsense elsewhere. Each of these is asserted over a sweep, not at a point:

| Input | Required response |
|---|---|
| Ball speed ↑ | carry rises, monotonically, over 90–180 mph |
| Launch angle | carry is single-peaked with the peak strictly interior |
| Spin | carry is single-peaked with the peak strictly interior |
| Spin ↑ | apex rises, descent steepens, landing speed falls |
| Spin axis ↑ | curve grows monotonically, and grows with total spin too |
| Flight time | spin decays, ending between 60% and 100% of launch spin |
| Backspin at landing ↑ | roll falls, monotonically, over 2000–10000 rpm |
| Descent angle ↑ | roll falls |
| Turf firmness ↑ | roll rises: rough < green < fairway < firm |
| Sidespin | the bounce kicks the ball further offline, in the curve direction |

The single-peaked assertions are the strongest of these. A model with the wrong
lift-to-drag balance can still hit a carry number, but it will put the optimum
launch at 4° or 40°, and the sweep catches that immediately.

## 6. Layer 5 — reference flights

Trackman tour averages, driver through pitching wedge. Simulated / reference:

| Club | Carry | Apex | Descent | Hang | Roll | Total |
|---|---|---|---|---|---|---|
| PGA driver | 262 / 275 (−4.9%) | 32 / 32 | 40 / 38 | 6.6 / 6.4 | 21 / 25 | 283 / 300 |
| LPGA driver | 211 / 218 (−3.3%) | 25 / 25 | 36 / 37 | 5.7 / 5.7 | 23 / 20 | 234 / 238 |
| 3-wood | 247 / 243 (+1.5%) | 30 / 30 | 40 / 43 | 6.5 / 6.2 | 19 / 15 | 265 / 258 |
| 5-iron | 206 / 195 (+5.8%) | 34 / 31 | 46 / 46 | 6.6 / 6.2 | 12 / 10 | 218 / 205 |
| 7-iron | 173 / 172 (+0.8%) | 30 / 32 | 45 / 50 | 6.0 / 6.1 | 9 / 9 | 182 / 181 |
| 9-iron | 149 / 152 (−2.0%) | 29 / 30 | 48 / 51 | 5.7 / 5.8 | 6 / 7 | 155 / 159 |
| PW | 134 / 136 (−1.4%) | 30 / 29 | 50 / 52 | 5.6 / 5.6 | 4 / 5 | 138 / 141 |

**Carry RMS 3.3%, worst case 5.8%. Roll RMS 2.5 yd.**

The residuals are not random — the driver is consistently short and the 5-iron
consistently long. That is a real limitation of a five-coefficient aerodynamic
model asked to span a 3× range of spin ratios, and it is left visible rather
than papered over with a club-dependent fudge.

The test enforces 8% on carry, 4.5 yd on apex, 6° on descent and 0.6 s on hang
time — loose enough to absorb reference noise, tight enough that any
coefficient change large enough to matter will trip it.

### Where the coefficients came from

Grid search over `dragBase`, `dragPerSpin`, `dragAtLowSpeed`, `liftMax`,
`liftHalfSpin` against all seven clubs at once, scoring carry (weight 8), apex
(1.5), descent (1) and hang time (2) as relative errors. Hang time was included
deliberately: carry alone is degenerate — a model can be too draggy and too
lifty at once and still land the right distance, but it cannot also match the
time it took. Adding hang time to the objective is what forced the
speed-dependent drag term into existence, and it is the single change that most
improved the fit.

The turf parameters were fitted separately, against the tour carry-to-total
deltas, with the ball–turf friction pinned to Penner's measured 0.40 rather
than fitted, so the spin-to-turf coupling stays physical.

## 7. Layer 6 — cross-model agreement

`ShotOptimizer`'s optimal launch and spin windows were written from published
coaching and club-fitting guidance, with no knowledge of this simulation. They
are an independent model of the same physics. If the two agree, that is much
stronger evidence than either alone.

They mostly do. Best carry reachable from inside the optimizer's driver window,
against the best reachable anywhere:

| Club speed | Shortfall inside the window |
|---|---|
| 115 mph | 0.2% |
| 100 mph | 0.6% |
| 85 mph | 2.9% |

The carry ridge is very broad — at 170 mph ball speed, a 13° launch is within
0.33% of the best carry available at *any* launch angle — so comparing the
location of the two models' optima is meaningless. Comparing how much distance
each leaves on the table is not.

**The 85 mph disagreement is real and is not fitted away.** This model puts the
carry-maximising launch for a slow swing at roughly 20–23°, above the 11–15°
the optimizer recommends, worth about 5 yards of carry. Both can be defended:
high launch genuinely does pay for slow swings, and a fitter's window is
constrained by what a player can actually deliver with a driver. It is recorded
in the test with the measured number so that a refit that changes it shows up
as a deliberate decision rather than a silent drift.

## 8. Layer 7 — validating against your own shots

Everything above establishes that the model is self-consistent and matches
*tour* data at *sea level* in *ISA* air with *no wind* on *fairway* turf.
Your range is none of those things. This is the layer only you can run.

**Procedure.**

1. Pick one club you hit consistently — a 7-iron is ideal, a driver has the
   most variance.
2. On a range with marked distances (or with a laser to a fixed target), hit
   10–15 shots, discarding obvious mishits.
3. Record the app's carry for each and pace or laser the actual pitch marks.
   Compare **medians**, not means: one thin shot ruins a mean.
4. Repeat for a second club at a very different speed and launch — a driver and
   a wedge bracket the range well.

**Reading the result.**

| Symptom | Likely cause | What to change |
|---|---|---|
| Every club long or short by a similar % | Air density: altitude, heat, humidity | `_airDensity` in `shot_trajectory.dart` |
| Long clubs off, short clubs fine (or vice versa) | Drag/lift balance across spin ratios | `dragPerSpin` / `liftHalfSpin` |
| Carry fine, total wrong | Turf | The `GroundModel` preset |
| Everything short into one direction | Wind — not modelled at all | Nothing; test on a calm day |

Air density is the correction that matters most and is the easiest to get
right, because it is not a fitted parameter but a measurable property:
ρ ≈ 1.225 × (288.15 / T) × exp(−elevation / 8435) with T in kelvin and
elevation in metres. Denver in summer is roughly 0.98 kg/m³ — about 8% less
drag, and a driver carries roughly 10 yards further. If you play consistently at
altitude, that one constant is worth more than any amount of coefficient
tuning.

**Re-validating after a change.** Run
`flutter test test/features/launch_monitor/domain/entities/` and expect all 120
tests green. Layers 1–4 must not move at all — they are physics, not
calibration. If a coefficient change breaks a sensitivity test, the change is
wrong regardless of what it did to the reference table.

---

## 9. Known limitations

Stated plainly, because a model whose limits are undocumented gets trusted
where it shouldn't be.

- **No wind.** The largest un-modelled effect outdoors, and easily worth ±20
  yards on a driver. The app has no wind input, so there is nothing to model
  from.
- **Fixed atmosphere.** Sea level, 15 °C, dry. See above for the correction.
- **One ball.** Coefficients are for a modern multi-layer tour ball. Range
  balls fly meaningfully shorter — mostly lower spin and higher drag — and
  nothing here accounts for that.
- **Turf is a guess.** Bounce and roll depend on moisture, grass length, thatch
  and slope, none of which are knowable from a BLE packet. Roll should be read
  as "about this far, on this kind of surface", not as a measurement. The
  surface is fixed to fairway; the other presets exist but are not yet
  user-selectable.
- **Flat, level ground.** No slope, so no downhill release or uphill check.
- **Spin decay is a single exponential** with a 24 s constant, independent of
  speed. Real decay depends on Reynolds number.
- **The device's own numbers win where it has them.** A device-reported roll
  overrides the simulated one; apex likewise. The simulation only fills gaps.
- **Systematic residuals.** Driver ~5% short, 5-iron ~6% long, as tabulated
  above.

## 10. Adding a validation test

The bar for this suite: a test belongs here if it could fail for a reason other
than "someone changed a number". Prefer, in order —

1. a closed-form comparison,
2. an invariant (symmetry, bound, conservation),
3. a monotonic or single-peaked sweep,
4. agreement with a model built independently of this one,
5. a reference data point.

The last is the weakest and the suite already has enough of them.
