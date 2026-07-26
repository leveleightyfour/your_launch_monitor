# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Deliberately **uniform brand-first** (user-confirmed): one custom design language on every OS — Android tablets, iPad, and Windows desktop — matching the current dark Material theme. Brand consistency outranks per-OS convention; do not introduce Cupertino/Fluent idioms per platform.

## Users

Square Golf Omni launch monitor owners — golfers practicing with the device, including the developer. Intended for public release to other Omni owners, not just personal use.

Primary usage scenes (user-confirmed):

- **Tablet propped at the hitting mat** — glanced at between swings, often from address position, hands on a club.
- **Windows PC in a home simulator room** — a desktop/laptop screen driving the session.

Phone-at-the-mat and couch review were explicitly *not* selected as primary scenes.

## Product Purpose

A companion app for the Square Golf Omni launch monitor. It connects to the device over BLE, records every shot into sessions, and turns raw launch numbers into analysis: dispersion patterns, simulated 3D ball flight, club gapping (My Bag), and a shot optimizer that diagnoses inefficiencies and estimates the distance they cost. Success is a golfer finishing a practice session knowing what to work on, with all their data on their own device.

## Positioning

All four pillars user-confirmed:

1. **Deeper practice analytics** than the official Square Golf app — shot optimizer, dispersion ellipses, PGA Tour benchmarks, physics-based 3D flight.
2. **Data ownership / offline** — shots live in a local Drift database; no account, no cloud dependency; CSV export built in.
3. **Platform reach** — runs where the official app doesn't, notably Windows desktop (dedicated `win_ble` adapter).
4. **Reverse-engineering heritage** — the app grew out of understanding and owning the Omni's BLE protocol (package name `omni_sniffer`; in-app protocol capture export). The protocol knowledge is first-party, not licensed.

## Operating Context

- The Omni measures the ball **at impact only** (ball speed, launch angle, launch direction, total spin, spin axis). Everything downstream — carry, apex, descent, curvature, roll, finish position — is simulated by the in-app `BallFlightModel` (see `docs/flight_model.md` and `docs/flight_model_validation.md`).
- A session: connect to the device over BLE, hit balls, each shot appears live; review happens between swings and at session end. Sessions are tagged, tied to clubs from My Bag, and revisitable from history.
- Hole setup (fairway/green geometry) contextualizes the 3D flight view.
- Domain layer units are fixed: **yards, mph, degrees**. Conversion to user preference (`UnitPrefs`) happens only at the presentation layer.
- Over-the-air updates ship via Shorebird code push.

## Capabilities and Constraints

- Flutter (Dart SDK ^3.9), Riverpod, go_router, Drift for persistence. BLE via `flutter_blue_plus` (iOS/Android) and `win_ble` (Windows) behind a shared adapter interface.
- Existing surfaces: app shell, live session screen with five analysis tabs (tiles, table, dispersion, club, 3D flight), session list/detail, My Bag, profile; shot optimizer side panel; device picker, hole setup controls, tag picker.
- PGA Tour launch-parameter profiles (TrackMan published averages) drive a test-shot generator producing realistic dispersion — inputs only; carry/offline come from the same physics as real shots.
- Terminology in use: shot, session, club, tag, carry/total/offline, dispersion, apex, descent angle, spin axis, smash factor era terms per `ShotOptimizer` diagnostics.
- **Undecided (do not invent):** distribution channel, pricing/licensing, and any public release timeline.

## Brand Commitments

- Display name: **"Your Launch Monitor"** (package id remains `omni_sniffer`).
- Dark-only custom Material theme with a user-selectable accent color (default teal `#2DD4B0`). The accent semantically means "your shot"; fixed environment colors (turf, sky, flagstick red) deliberately do not recolor with it.
- One uniform design language across all OSes (see Platform).

## Evidence on Hand

- Real club imagery: `assets/clubs/` (top and impact photos per club type).
- Engineering documentation: `docs/flight_model.md`, `docs/flight_model_validation.md`, `docs/shot_optimizer.md` — including known simulation limitations.
- PGA Tour benchmark data sourced from published TrackMan averages (`lib/features/launch_monitor/data/pga_sim_profiles.dart`).
- **Absent — never fabricate:** testimonials, customer counts, accuracy claims beyond what `flight_model_validation.md` supports, or any affiliation with Square Golf / TrackMan.

## Product Principles

1. **Readable from the mat.** Primary screens are glanced at arm's-length-plus on a tablet or across a sim room on a PC — key numbers must land in a glance between swings.
2. **Measured is sacred; simulated is honest.** Device-measured values and physics-derived values are different classes of truth; the product never blurs which is which.
3. **The golfer owns the data.** Local-first, exportable, inspectable — down to the raw BLE protocol captures.
4. **Analysis ends in an action.** Numbers exist to produce a prioritized, plain-language recommendation, not a data dump.
5. **One app, everywhere the golfer practices.** The same brand-first experience on Android, iPad, and Windows — platform is an implementation detail, not a design fork.
