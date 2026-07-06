# Shot Optimizer

The shot optimizer analyses each recorded shot against club-specific optimal
windows, diagnoses inefficiencies, estimates the distance they cost, and turns
them into prioritised, actionable recommendations. This document explains the
logic end to end.

**Code map**

| Layer | File | Responsibility |
|---|---|---|
| Domain | `lib/features/launch_monitor/domain/entities/shot_optimizer.dart` | `ShotOptimizer` engine, `OptimalRanges`, `Diagnostic`, `Recommendation`, `ShotAnalysis`, `Severity` |
| Application | `lib/features/launch_monitor/application/shot_optimizer_providers.dart` | Riverpod providers: per-shot analysis + session-wide summary |
| Presentation | `lib/features/launch_monitor/presentation/widgets/shot_optimizer_panel.dart` | `ShotOptimizerPanel` side panel UI |
| Tests | `test/features/launch_monitor/domain/entities/shot_optimizer_test.dart` | Unit tests for ranges, diagnostics, recommendations |

All distances inside the domain layer are **yards** and speeds are **mph**.
Conversion to the user's preferred units (`UnitPrefs`) happens only at the
presentation layer.

---

## 1. Entry point

```dart
ShotAnalysis analyze(ShotData shot, ClubType clubType, {String? clubId})
```

`analyze` runs four steps:

1. **Diagnostics** — compare the shot's metrics against optimal windows.
2. **Recommendations** — map each diagnostic to a coaching action.
3. **Optimal carry / carry gap** — estimate what the swing *could* carry and
   how far short the shot fell.
4. **Summary** — a one-line, human-readable verdict.

Putter shots are excluded entirely — putts are not "optimized".

The club context comes from two inputs:

- `clubType` — the broad category (`wood`, `miniDriver`, `hybrid`, `iron`,
  `wedge`, `putter`), derived from `Club.type`.
- `clubId` — the specific club (`'dr'`, `'7i'`, `'sw'`, `'56deg'`, …), used
  where the category alone is too coarse (driver speed bands, iron spin rule,
  wedge lofts). Note the driver's `ClubType` is `wood`; driver-specific logic
  keys off `clubId == 'dr'`.

## 2. Optimal ranges (`OptimalRanges`)

`OptimalRanges.getRange(clubType, metric, clubSpeed:, clubId:)` resolves the
optimal `(min, max)` window for a metric. Resolution order:

### 2.1 Driver — speed-aware windows

Optimal launch and spin for a driver depend on swing speed: slower swings need
more launch and spin to keep the ball airborne; faster swings need less to
avoid ballooning. Club speed is bucketed into three bands:

| Band | Club speed | Launch angle | Spin rate | Smash factor |
|---|---|---|---|---|
| Slow | < 90 mph | 11–15° | 2,500–3,200 rpm | 1.45–1.65 |
| Moderate | 90–105 mph | 10–14° | 2,200–2,800 rpm | 1.45–1.65 |
| Fast | ≥ 105 mph | 9–13° | 2,000–2,600 rpm | 1.45–1.65 |

### 2.2 Iron spin — club-number rule

Optimal iron spin ≈ **1,000 rpm × club number**, with a ±500 rpm window
(e.g. 7-iron → 6,500–7,500 rpm). If the club number can't be parsed, a safe
fallback of 5,000–7,500 rpm is used.

### 2.3 Wedge spin

Named wedges use fixed windows:

| Wedge | Window (rpm) |
|---|---|
| PW | 8,500–10,500 |
| GW | 9,000–11,000 |
| SW | 9,500–11,500 |
| LW | 10,000–12,000 |

Degree wedges (`50deg` … `64deg`) scale with loft:
`target = 5,000 + 100 × loft`, clamped to 9,000–11,500 rpm, with a ±1,000 rpm
window. So a 56° wedge targets 10,600 rpm (window 9,600–11,600).

### 2.4 Flat ranges — everything else

| Club type | Launch angle | Spin rate | Smash factor |
|---|---|---|---|
| Mini driver | 10–15° | 2,200–3,000 rpm | 1.45–1.65 |
| Wood (fairway) | 14–20° | 2,500–3,600 rpm | 1.40–1.60 |
| Hybrid | 16–26° | 3,000–4,200 rpm | 1.35–1.55 |
| Iron | 14–22° | (club-number rule) | 1.35–1.50 |
| Wedge | 24–40° | (loft rule) | 1.20–1.45 |
| Putter | 1–6° | 0–500 rpm | 1.0–1.8 |

## 3. Diagnostics

Each check produces a `Diagnostic` with the measured value, the optimal
window, a `Severity` (`critical` → `high` → `medium` → `low`), likely root
causes, and — where a sensible model exists — `estimatedYardsLost`. The
final list is sorted most-severe first.

Checks are organised in tiers, roughly "biggest distance levers first":

### Tier 1 — Energy transfer (smash factor)

Smash factor = ball speed ÷ club speed. Below the window is **critical** —
it means energy is being left on the table at impact (off-centre strike,
dirty face, ball mismatch). Above the window is flagged **low** severity
(usually a sensor artefact rather than a real problem).

Distance lost is modelled physically: the smash deficit times club speed is
the lost *ball speed*, and each mph of ball speed is worth roughly:

| Club type | Carry yards per ball-speed mph |
|---|---|
| Wood / mini driver | 1.9 |
| Hybrid | 1.7 |
| Iron | 1.5 |
| Wedge | 1.0 |

Example: a driver swing at 100 mph with smash 1.30 vs a 1.45 floor loses
`0.15 × 100 × 1.9 ≈ 28 yards`.

### Tier 2 — Launch conditions

- **Launch angle**: flagged whenever outside the window. Severity scales
  with deviation: > 5° out is **critical**, > 3° **high**, else **medium**.
  Distance lost ≈ 2 yards per degree of deviation.
- **Spin rate**: flagged only when more than **10% outside** the window
  (spin measurements are noisy). Severity: > 25% out **critical**, > 15%
  **high**, else **medium**.
- **Spin loft mismatch** (needs `dynamicLoft` and `angleOfAttack`): spin
  loft = dynamic loft − attack angle. Expected spin ≈ spin loft × a per-club
  factor (woods 186, hybrids 250, irons 342, wedges 380 rpm/degree). If the
  measured spin deviates from the prediction by more than 15%, the delivery
  is inconsistent (strike location / shaft lag / wrist hinge) — flagged
  **medium**.

### Tier 3 — Delivery

- **Path–face alignment** (needs `swingPath` and `faceAngle`): a gap > 5°
  between path and face creates curvature and costs distance. > 10° is
  **critical**, else **high**. Distance lost ≈ 1.5 yards per degree of gap.
- **Attack angle** (needs `angleOfAttack`), club-aware:
  - **Driver / mini driver** (teed): any *negative* attack angle is flagged
    (optimal +3 to +5°). Below −3° is **high**, else **medium**.
    Distance lost ≈ 2 yards per degree down.
  - **Ground clubs** strike with a descending blow, deepening as clubs get
    shorter:

    | Club type | Optimal window |
    |---|---|
    | Fairway wood | −4.0 to +0.5° |
    | Hybrid | −4.5 to −0.5° |
    | Iron | −5.0 to −2.0° |
    | Wedge | −7.0 to −3.0° |

    Shallower than the window ("picking") or more than 2° deeper than it
    ("digging") is flagged **medium**.

### Tier 4 — Impact location

Needs `horizontalImpact` / `verticalImpact` (mm from centre). The radial
miss is converted to inches; misses > 0.5″ are flagged (> 0.75″ is
**high**), at ≈ 5 yards lost per inch off-centre.

## 4. Recommendations

Each diagnostic maps to at most one `Recommendation` — an action id, a
coaching description, the metrics it would improve, a priority (1 = do this
first), and an expected carry gain (carried over from the diagnostic's
estimated loss). Duplicates are removed by action id and the list is sorted
by priority.

| Diagnostic | Action | Priority |
|---|---|---|
| Low smash factor | `improve_center_contact` | 1 |
| Low launch | `raise_dynamic_loft` | 1 |
| High launch | `lower_dynamic_loft` | 1 |
| Off-centre impact | `optimize_strike_location` | 1 |
| High spin | `reduce_spin` | 2 |
| Low spin | `increase_spin` | 2 |
| Path–face gap | `improve_face_path_alignment` | 2 |
| Negative driver attack angle | `hit_up_on_driver` | 2 |
| Shallow attack angle (ground club) | `strike_down_through_the_ball` | 2 |
| Steep attack angle (ground club) | `shallow_the_attack_angle` | 2 |
| Spin loft mismatch | `stabilize_delivery` | 3 |

The UI shows the top three.

## 5. Optimal carry and carry gap

Optimal carry is a coarse "what should this swing speed produce" model —
club speed × a carry-per-mph multiplier derived from tour averages:

| Club | Yards per mph of club speed |
|---|---|
| Driver (`dr`) | 2.6 |
| Mini driver | 2.5 |
| Fairway wood | 2.35 |
| Hybrid | 2.2 |
| Iron | 1.9 |
| Wedge | 1.4 |

The **carry gap** (optimal − actual, floored at 0) is only reported when at
least one diagnostic is out of range. On a clean shot the model's error would
otherwise masquerade as "potential gain", so it is suppressed.

## 6. Session summary

`sessionOptSummaryProvider` re-analyses every shot in the session and
aggregates:

- shot count, average carry, average smash factor,
- total count of critical diagnostics,
- **top issue** — the most frequently out-of-range metric and how many shots
  it appeared on,
- **total estimated yards lost** across all flagged diagnostics.

The panel shows the top issue with its frequency and the cumulative distance
lost, converted to the user's units.

## 7. Known limitations / future ideas

- The carry and yards-lost models are linear rules of thumb, not a flight
  model; they are meant for *ranking* problems, not exact prediction.
- `ShotData.carry` is itself an estimate until the device protocol delivers a
  measured carry, so the carry gap inherits that error.
- Diagnostics are per-shot; consistency analysis (e.g. strike-pattern or
  smash-factor dispersion across a session, per-club trends) would be a
  natural next layer on top of the existing session aggregation.
- Optimal windows are static defaults. Letting users tune windows per club
  (fitting context, altitude, ball model) would make the diagnostics more
  personally accurate.
