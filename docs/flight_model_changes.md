# Flight model v2: contact and replay correctness

The aerodynamic coefficients are unchanged. The tour fixtures used to fit them
remain regression checks, not an independent accuracy measurement. There is no
new claim of improved carry accuracy.

## Behaviour changes

- Replay interpolates by sample timestamp. Ball, tracer, shadow and curtain end
  at the same simulation time, including irregular contact samples. Airborne
  replay remains real time, with ground replay compressed to at most 4 seconds.
- Restitution follows Penner's piecewise fit: the quadratic through 20 m/s,
  then 0.120, before applying the turf multiplier. See equations 5a–5b in
  [The run of a golf ball](https://doi.org/10.1139/p02-035).
- Every airborne ground contact interpolates position, velocity and spin back
  to touchdown and consumes the remaining step after applying the contact
  impulse. Turf and hazard lookups use that corrected contact location.
- Exact pre/post-contact samples expose total mechanical energy per unit mass,
  including rotational energy, for validation. Replay selects the post-contact
  state when samples share a timestamp.
- Invalid/non-finite launch data returns `FlightFailure.invalidInput`. Inputs
  outside the supported envelope (300 mph, 90 degrees vertical launch,
  30,000 rpm) are rejected. A still-airborne shot at the 20-second limit returns
  `FlightFailure.timeLimit`; it does not produce a fictitious touchdown.
- Device apex and roll are retained as raw data and exposed separately through
  `reportedApexHeight` / `reportedRollDistance`. All derived shot distances and
  the 3D path now use simulation values. The 3D stat bar labels the simulation
  and displays device comparisons when supplied. The integrator no longer
  accepts `measuredRollYds` or scales a simulated path to a device endpoint.

Existing sessions are currently recalculated from launch data when loaded.
This numerical update therefore changes their simulated ground results; raw
launch data and device reports are preserved. Persisting a versioned model and
atmosphere per shot requires a separate database migration and is not included.

## Verification

The tests cover irregular timestamps, exact tracer endpoints, contact event
state, step convergence, the restitution cutoff, invalid inputs, timeouts,
reported-value separation, and rotational as well as translational energy.
Spin sensitivity checks both sides of the optimum. Spin-back assertions require
actual backward motion; a separate high-spin stress fixture exercises a forward
hop followed by backward motion without presenting it as a measured shot.

Run:

```sh
flutter test test/features/launch_monitor/domain/entities/ test/features/launch_monitor/presentation/replay_timing_test.dart test/features/launch_monitor/presentation/flight_trails_test.dart test/features/launch_monitor/presentation/flight_3d_controls_test.dart
```

## Independent validation before aerodynamic calibration

`dart run tool/validate_flight.dart observations.json` compares observations
with the standard simulation and prints per-shot errors plus bias and RMSE for
carry, apex, descent, flight time and offline. It does not fit coefficients.

The JSON object must contain a nonempty `source`, a nonempty `conditions`, and
`shots`. Each shot requires `ballSpeed` (mph), `launchAngle` (degrees),
`launchDirection` (degrees), `spin` (rpm), and `spinAxis` (degrees). Include at
least one observed `carry` (yards), `apex` (yards), `descent` (degrees),
`flightTime` (seconds), or `offline` (yards, positive right).

Use individually paired launch/flight observations collected independently of
the tour fixtures. Keep a holdout set separate from any calibration set and
record source, ball type and atmospheric conditions. Reference shots generated
by another simulator measure cross-model agreement, not field accuracy.
The model still assumes sea-level dry air at 15 C with no wind; the tool records
both observed conditions and these assumptions without silently normalizing.

Only after this dataset exists should a Reynolds-number/spin-ratio coefficient
table be fitted. Atmosphere/wind inputs, ball profiles and versioned historical
simulation are follow-on work, not guessed calibration constants in this patch.
