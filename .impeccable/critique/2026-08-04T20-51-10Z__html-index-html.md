---
target: html landing page (analyse this html)
total_score: 25
max_score: 32
na_heuristics: 7,10
p0_count: 0
p1_count: 2
timestamp: 2026-08-04T20-51-10Z
slug: html-index-html
---
Method: dual-agent (A: design-review subagent · B: detector subagent). Browser overlay unavailable — one-shot headless shell only, no mutable session; detector ran via CLI.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Form confirms; mobile measured-strip overflow has zero scroll affordance |
| 2 | Match System / Real World | 4 | Gearhead vocabulary pitch-perfect; "Apex 29 yds" (golfers expect feet) is the one flinch |
| 3 | User Control and Freedom | 2 | Submit disables permanently (typo unrecoverable); no mobile nav at all |
| 4 | Consistency and Standards | 3 | Static chips (PGA 90%, Orbit, MP4) carry full button affordance but do nothing |
| 5 | Error Prevention | 3 | type=email + required only; browser-default validation |
| 6 | Recognition Rather Than Recall | 4 | Truth-badge legend taught in hero, reused everywhere — exemplary |
| 7 | Flexibility and Efficiency | n/a | Single-action Persuade surface |
| 8 | Aesthetic and Minimalist Design | 4 | Dense but earned; 8.5–10px type flirts with the floor |
| 9 | Error Recovery | 2 | No inline validation; locked post-submit state blocks correction |
| 10 | Help and Documentation | n/a | The page is a datasheet; footer covers obligations |
| **Total** | | **25/32** | **Good (78%) — drag is form states + responsive breakage** |

## Design Specificity Verdict

LLM assessment: genuinely authored — the § sections, MEASURED/SIMULATED/REFERENCE badges, mono field labels, hexdump and Data classes table are load-bearing expressions of this product's epistemology; another product could not wear the page unchanged. Residual skeleton sameness (left-copy/right-visual hero, alternating sections, centered close) sits under the datasheet costume. Missed character: assets/clubs/ photography unused; the Windows-first differentiator buried at §07.

Deterministic scan: 1 advisory finding total (em-dash-overuse, 23 in body text; ~6 live in comments/meta, the rest largely label-separator usage judged mostly benign). No color, font, layout or antipattern rules fired — the detector corroborates the craft floor. No overlay: no mutable browser session available.

## Overall Impression

A credible, characterful page whose honesty system (measured vs simulated) doubles as its persuasion engine. The weaknesses are not aesthetic: they're responsive breakage on the two most truth-critical elements (measured strip, spec table) and form states that dead-end a real visitor.

## What's Working

1. Truth badges as persuasion — admitting "carry is simulated" buys more trust with this audience than any accuracy claim; taught in hero, restated per section, formalized in §08.
2. Honest recreations over fake screenshots — the app's real tokens, "EXAMPLE DATA" captions, footer disclaimer; sharper than compressed screenshots and fabricates nothing.
3. Copy priced in yards from H1 to §05 (−6 yds carry, 24-yd gap, −9 yds recoverable) — the audience's actual currency.

## Priority Issues

- [P1] Measured strip breaks at 640–960px — nowrap values collide across cells at 768; at 390 four of five items hide behind unindicated scroll. The honesty centerpiece is the first responsive casualty. Fix: reflow to 2-col grid below 960px, drop nowrap, never hide core content in invisible overflow. → /impeccable adapt
- [P1] §08 spec table's Class column clips off-screen at 390px — the badge column is the table's point; descriptions wrap into towers. Fix: stack rows (parameter+badge line, description beneath) at small widths. → /impeccable adapt
- [P2] Email input focus effectively invisible — .notify input:focus overrides the global ring with a 39%-alpha 1px border; the page's most important control has its weakest focus state. Fix: 2px accent outline or box-shadow ring on :focus-visible. → /impeccable polish
- [P2] Submit is a dead end — button disables permanently; typo unrecoverable; placeholder message reads as a broken promise to a real visitor. Fix: keep field editable with inline confirmation; treat endpoint wiring as a ship gate. → /impeccable harden
- [P3] False-affordance chips (Trackman/PGA, Tracer/Orbit, Both/DTL/FO, export row) styled as live controls. Fix: flatten to labels or caption "controls shown for illustration". → /impeccable clarify

## Persona Red Flags

Jordan (first-timer): "SIM" 8.5px tag unexplained — plausibly read as "simulator"; the strip that would teach it is the element that vanishes on small screens; clicks PGA 90% chip, nothing happens; submit message admits the page isn't wired.
Riley (stress tester): invalid submits fall to browser bubbles; valid submit locks the form — can't test a second address; input focus nearly undetectable; 768px collision reproduces instantly.
Casey (mobile): form is high and thumb-friendly (best served), but zero navigation (links hidden, no menu), one-fifth of the measured strip visible, and the clipped spec table is the last thing seen before the close.

## Minor Observations

- §05 arithmetic: flagged gap is 24 yds but the unflagged 3W→HY gap is 25 yds — a gearhead will notice.
- No OG/Twitter meta, no favicon — a promo page will unfurl as a bare link.
- Google Fonts is render-blocking on a page selling "works offline"; self-host DM Sans/Mono.
- Accent-semantics wobble: hero's biggest accent number (Carry 248) is a simulated value.
- prefers-reduced-motion coverage is thorough — genuinely well done.
- ⚠ glyph lacks aria pairing; footer wordmark isn't a home link.
- Detector's em-dash advisory: worth a pass over prose sentences only; label-separator uses are the page's voice.

## Questions to Consider

1. Windows-first is the pillar no competitor can copy — what would the page be if "The official app doesn't run on a PC; this one was built there" were the second sentence a visitor reads?
2. Would one real photograph (a wedge on the mat beside the Omni, from assets/clubs/) ground the all-SVG datasheet — or puncture its recreation purity?
3. If accent strictly means "your shot", should a simulated carry ever wear it — or does the page need a convention the app would then have to honor too?
