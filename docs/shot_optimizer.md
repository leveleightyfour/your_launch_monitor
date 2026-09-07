# Shot feedback and equipment comparison

The optimisation tab supports shot review and controlled equipment comparisons.
It does not certify a fit or infer which untested shaft, head or adjustment to buy.
Carry, offline and landing outcomes come from `BallFlightModel.standard`; the
device supplies launch measurements, not the rest of the flight.

## Input eligibility

Each shot stores a versioned `ShotContext` with ball and club-speed provenance,
shot intent, objective and (during a comparison) an immutable setup snapshot.
The live BLE path requires valid speed, launch angles, spin and spin axis (or
valid backspin and sidespin components). Finite physical bounds and successful
flight integration are checked before feedback. Putter shots are outside scope.

Club speed inferred from ball speed / 1.45 is marked estimated. It must never
support a smash-factor diagnosis. Valid later club packets promote the source
to measured without losing the fitting context. Demo shots are explicitly
simulated: they can preview feedback but cannot count as fitting evidence.

Database schema 6 adds nullable `assessment_context` JSON to shots. Old rows,
unknown versions and damaged metadata remain unverified; no migration invents
measurement validity. Save, reload and club-packet updates preserve the snapshot.
CSV appends source, intent and full context columns (JSON distances are yards).

## Feedback calculations

- Stock-shot references distinguish club number and nominal wedge loft. Driver
  and mini-driver launch/spin windows interpolate continuously from 75–115 mph
  measured club speed. Other club windows are deliberately broad; they are not
  calibrated to actual head loft or an individual's delivery. Recorded equipment
  loft is descriptive and does not silently alter these reference equations.
- Partial shots do not receive stock launch, spin or smash targets. Unknown
  intent also suppresses stock targets. Strike and direction can still be reviewed.
- Low smash severity scales with the relative shortfall below the reference:
  medium initially, high above 10%, critical above 20%. Strike and low smash
  share one contact action. Low smash alone is not treated as proof of a mishit.
- The former spin-loft-to-rpm residual is removed: without speed, friction and
  empirical calibration it cannot support an inconsistent-delivery diagnosis.
- For stock drivers with a carry objective and at least 70 mph ball speed, a
  bounded joint search evaluates launch 8–22° and spin 1800–4200 rpm. It uses a
  2°/400 rpm grid and a local 1°/200 rpm refinement, at most 65 flights. Current
  ball speed, direction and spin axis stay fixed. The starting result is the
  current flight, so the reported best cannot be worse. A gain is shown only
  at 3 yd or more. This is a bounded model estimate, not a global optimum or
  guaranteed achievable gain. Results are cached per immutable shot and club.
  Native-platform session reports run in a worker isolate; selecting another
  shot reuses the report for that unchanged session rather than blocking the UI.
- No diagnostic yard penalties are added together. The one potential carry gain
  is the difference between two outcomes from the same flight model. Smash
  recovery is not also credited. Attack angle supplies conditional context only.
- High-spin driver guidance correctly notes that low-face contact can add spin;
  it does not recommend striking lower to reduce spin.
- Start-line tolerance uses atan(offline tolerance / max(carry, 20 yd)). Modelled
  landing outside the corridor gets directional feedback even if face and path
  match. Signed face-to-path is supporting evidence, not a handedness assumption.
- Approach objectives assess target carry (±max(3 yd, 5%)), the chosen landing
  angle and lateral tolerance rather than maximising distance. Actual stopping
  still depends on landing speed, spin, ball and green conditions.

The UI says “Available checks passed”, never “optimal”. It exposes missing
measurements and provisional references. Session summaries group by club and
intent, report assessed counts, carry variability and measured-smash counts,
and do not average unrelated clubs or sum overlapping distance losses.

## Comparison protocol

1. Select a club, stock/partial intent and carry, accuracy or approach objective.
   Record ball, lie and environment, lateral tolerance, and an approach target
   and minimum descent where relevant. Use the same conditions for both setups.
2. Record name, head, shaft, loft setting and length for A and B; optional notes
   capture other differences. Review the configuration before starting.
3. Alternate A/B in short blocks, selecting the setup before each shot. Retain
   ordinary mishits. At least 10 eligible measured shots per setup and three
   switches are required in each round. Changing active club pauses recording
   for that comparison. Saved shots retain the setup in use at capture time.
4. Review counts, exclusions, mean carry, sample SD, absolute offline, descent,
   landing speed and landing spin. Use fresh shots in the confirmation phase.
   An advantage must repeat in both phases before the stronger verdict appears.

Objective loss is negative carry, absolute lateral error, or Euclidean distance
from the approach target. Positive improvement means loss(A) − loss(B). The
sampling margin is `2.3 * sqrt(variance(A)/nA + variance(B)/nB)`; 2.3 is a
conservative two-sided small-sample multiplier for n ≥ 10. The interval assumes
independent representative shots; serial dependence and selective deletion can
invalidate it. It is **not** uncertainty in the device or flight model. Both
zero-variance samples are rejected as evidence requiring verification.

A candidate advantage needs improvement minus margin > 2 yd. Additional guards:
carry gains cannot increase mean absolute offline beyond the corridor or have
an upper-bound offline degradation > 10% of its width; accuracy gains cannot
have an upper-bound carry loss > 5 yd; approach gains need at least 80% of
candidate shots above minimum descent and mean absolute offline inside tolerance.
These are provisional product thresholds, not empirically validated fitting rules.
Incompatible objectives, clubs, intent, conditions or setup specifications block
comparison. Simulated and unverified shots are counted as excluded.

## Verification and calibration limits

Regression tests cover validity, partial shots, contact severity, direction,
joint-search consistency, approach intent, comparison eligibility, confirmation,
metadata persistence and UI flow. A same-model search agreeing with a finer
same-model grid checks implementation consistency only.

Before claiming individual fitting accuracy, collect independent measured flight
outcomes across speeds, clubs, strike patterns and balls. Split calibration and
holdout players/sessions before tuning. Report signed error and spread for carry,
lateral landing, descent, landing speed and spin, including failure rates. Test
whether A/B decisions repeat on the holdout sessions and agree with observed
flight, turf interaction and player constraints. Predefine practical thresholds
and assess uncertainty coverage; do not widen tests after seeing failures.

See [flight validation](flight_model_validation.md) and
[flight changes](flight_model_changes.md). UI follows `DESIGN.md`, `PRODUCT.md`,
`flutter_best_practices.md` and `flutter_ui_guide.md`: app tokens, Material/Lucide,
Riverpod form state, progressive setup/review and responsive scrolling.
