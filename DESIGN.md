# Design

<!-- Documents the identity already established in lib/shared/theme.dart.
     The app is the visual authority; every other surface (including the
     html/ landing page) inherits from here. -->

## World

Instrument-grade dark UI. The app reads like a precision measurement device:
near-black grounds, hairline borders, one vivid accent that means exactly one
thing — **your shot**. Everything else stays quiet so numbers land in a glance
from the hitting mat.

## Color

| Role | Value | Notes |
|---|---|---|
| Background | `#0C0C10` | page/app ground |
| Surface | `#12151E` | panels |
| Card | `#1A1A24` | raised elements, chips |
| Border | `#1E1E28` / `#2A2A32` | hairline / emphasized |
| Accent | `#2DD4B0` (user-selectable in-app) | "your shot" — data, primary actions. Tints via alpha: 20/22/30/60/100 of 255 |
| Text | `#FFFFFF` / `#9C9C9C` muted / `#848484` dimmed | |
| Severity | `#EF4444` critical · `#F59E0B` warning · `#60A5FA` info | fixed, never accent-derived |
| Turf/scene | greens `#2C4732`–`#50805A`, pin `#D9483B` | fixed environment colors; never recolor with accent |

Rules: the accent is semantic, not decorative — it marks the golfer's own data
and the primary action, nothing else. Severity and environment hues never
follow the accent.

## Type

- **DM Sans** carries everything. Weights 400 (body), 600 (headings, w600 is
  the app's "bold"), 800 (stat values only, with tabular figures).
- **DM Mono** for measurement, protocol, and machine-ish labels — data, never
  costume.
- Scale (minor third): 24 heading / 20 subheading / 16 body / 14 label /
  12 caption.
- Metric readout trio: `statLabel` 11px w700 tracked 1.2 uppercase muted,
  `statValue` w800 tabular-nums tight, `statUnit` 11px italic dimmed. Every
  metric everywhere uses this trio.

## Spacing & shape

8pt grid (8/16/24/32/48/80). Hairline 1px dividers over drop shadows; radius
8–12px on panels and chips; chips are low (30px) with 1px borders, accent
border + accent-subtle fill when active.

## Truth vocabulary

Measured (device), simulated (flight model) and reference (published data) are
different classes of truth. Surfaces that mix them must say which is which —
in-app via copy and docs, on marketing surfaces via MEASURED / SIMULATED /
REFERENCE badges (accent / info-blue / dimmed).

## Motion

One authored moment per surface, exponential ease-out, from visible defaults.
In-app: split-flap digit rolls on stat tiles. Landing page: the hero readout
"arrives" (values rise, dispersion dots pop, tracer draws). Always honor
reduced-motion.
