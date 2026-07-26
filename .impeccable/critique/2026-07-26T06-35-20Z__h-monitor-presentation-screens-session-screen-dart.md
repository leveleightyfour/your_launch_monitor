---
target: session_screen
total_score: 21
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
timestamp: 2026-07-26T06-35-20Z
slug: h-monitor-presentation-screens-session-screen-dart
---
Method: dual-agent (A: design-review sub-agent · B: detector sub-agent)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Device-state signals are 10–12px dots at 2–3 m viewing distance; on disconnect the battery/arm/ball chips silently vanish; status dot is a no-op button |
| 2 | Match System / Real World | 3 | Golf vocabulary excellent; `gps_fixed` for "arm detection" and `bolt` for test shot are opaque metaphors |
| 3 | User Control and Freedom | 2 | "Abandon Session" is one-tap destruction with no undo; Android back gesture bypasses the finish dialog (no PopScope); no session rename at save |
| 4 | Consistency and Standards | 3 | Coherent dark language, but three different view-picker idioms and bare GestureDetectors mixed with Material buttons |
| 5 | Error Prevention | 1 | "Edit Shots" button wired to clearShots; abandon adjacent to primary action; summary sheet dismissable without saving |
| 6 | Recognition Rather Than Recall | 2 | Club filter set in drawer silently filters Tiles/Table/Club with no visible indicator; DispersionTab keeps a second unsynced filter |
| 7 | Flexibility and Efficiency | 3 | Real power features (split panes, CSV, bulk edit) but zero keyboard shortcuts on the Windows target |
| 8 | Aesthetic and Minimalist Design | 3 | Restrained and data-forward; undermined by pervasive 9–11px raw text that bypasses the theme's own type tokens |
| 9 | Error Recovery | 1 | ErrorBanner prints raw exception strings, no dismiss, no retry, causes layout shift |
| 10 | Help and Documentation | 1 | One tooltip in the whole screen (long-press-only on touch); no guidance for the arm→detect→ready sequence |
| **Total** | | **21/40** | **Acceptable** |

## Design Specificity Verdict

**LLM assessment:** The component vocabulary is genuinely authored for this product — the four-state ball-ready indicator, capacitor chip, club-color coding, PGA-fluent wedge sort order, split-flap tiles. But the screen composition is category-generic analytics-dashboard IA: a 7-item tab strip over content panes that treats "standing at the mat between swings" identically to "reviewing at a desk." The default split view (table + dispersion, 11–12px mono rows) is a desk analyst's layout; the at-the-mat scene is served only if the user discovers Tiles. The brand's core "measured is sacred; simulated is honest" principle has zero visible presence on this surface.

**Deterministic scan:** The detector scanned **0 files** — its scannable set is HTML/CSS/JS-family and this surface is pure Dart (21 files, none scannable). The empty result is "nothing scannable," not "scanned clean"; it carries no signal about this screen. No false positives to assess.

**Visual overlays:** Skipped — native Flutter surface, no served web build, no browser automation applies.

## Overall Impression

The domain atoms are excellent and the between-swings loop is genuinely understood, but the frame around them is a generic dashboard that under-serves the product's own stated scene (tablet at the mat, glanced from address position), and two P0 safety hazards (a mislabeled destructive button, silent disconnect) undermine the trust the product depends on. The single biggest opportunity: make the screen itself answer "can I hit now?" and "did that record?" from 3 meters away.

## What's Working

1. **The between-swings loop is genuinely understood.** Auto-select of the newest shot, the phone drawer auto-closing on pick (with an in-code rationale), and 108pt split-flap tiles deliver "readable from the mat" in the one tab that honors it.
2. **The device-state ladder is real product design.** Capacitor → armed → ball detected → ball ready maps exactly to the Omni's physical workflow — no generic app has this. The concept is right; only its 12px rendering fails it.
3. **The ultra-wide three-panel layout** (pinned shot list + content + docked optimizer) is authored for the Windows sim-room scene, not a responsive afterthought — and the club sort logic shows writer-level golf fluency.

## Priority Issues

1. **[P0] "Edit Shots" wipes the entire session.** The shot-list footer button labeled "Edit Shots" fires `onClearShots` → `notifier.clearShots` — one tap empties every shot, no confirmation; the real edit mode hides behind an unlabeled checklist icon. **Why:** the label promises the opposite of what it does, on destructive data. **Fix:** bind the footer button to edit mode; if "clear all" is wanted, label it honestly and gate behind a confirm. **Suggested command:** /impeccable harden
2. **[P0] Mid-session disconnect is silent and unrecoverable in place.** Device chips conditionally disappear on disconnect, the only remaining signal is a 10px red dot inside a no-op button, and reconnection UI exists only on the session-list screen. The golfer keeps swinging; nothing records. **Fix:** persistent full-width banner — "Device disconnected — shots aren't being recorded. [Reconnect]" — with the device picker invocable in place. **Suggested command:** /impeccable harden
3. **[P1] Destructive finish flow.** "Abandon Session" one-tap-destroys adjacent to the primary button, no second confirm, no undo; back gesture bypasses the dialog entirely; abandoned drafts resurface later as blank-named ghost sessions. **Fix:** red confirm step with shot count, PopScope routing back-press through the finish dialog, and delete or explicitly surface recovered drafts. **Suggested command:** /impeccable harden
4. **[P1] Windows/accessibility non-operation.** Every control is a bare GestureDetector: no Semantics, no focus/keyboard traversal, no tooltips on icon-only buttons, 16–36px targets vs 48dp minimum. The Windows-desktop pillar is unusable by keyboard/screen-reader users and hostile to gloved fingers. **Fix:** IconButton/InkWell + Tooltip + Semantics throughout; 44–48px minimum targets. **Suggested command:** /impeccable audit
5. **[P2] "Measured is sacred; simulated is honest" is invisible.** Simulated carry/apex/run/offline render identically to device-measured ball speed/spin in every view. **Fix:** one consistent lightweight mark for simulated values, defined once in the theme. **Suggested command:** /impeccable clarify

## Persona Red Flags

**Alex (power user):** taps the status dot to reconnect — it does nothing; pane switching on a 27" monitor requires a modal bottom sheet (phone idiom); no keyboard shortcuts anywhere on Windows; drawer club rows set the *filter*, not the *active* club; can't rename the session at save.

**Sam (accessibility):** screen reader announces nothing actionable (no Semantics on any custom control); keyboard traversal impossible; ball state is color-only red-vs-green at 12px (deuteranopia collision); club identity is color-dot-only; 9–10px dimmed text below low-vision thresholds; the sole tooltip needs long-press on touch.

**Riley (stress tester):** 500 shots renders non-virtualized rows per club section (jank); the shot-count badge is a fixed 15px circle that clips at 3 digits; finishing with 0 shots saves an empty session; app-kill mid-session leaves a blank-named unresumable ghost in the session list; Tiles in both split panes mounts duplicate Hero tags (exception risk); Android back skips the finish dialog.

**The golfer mid-swing-rhythm (glove, club in hand, 2–3 m away):** default split's table rows unreadable at distance — must discover Tiles or fullscreen; the "am I clear to swing?" signal is a 12px dot invisible from address position; every actionable control is below glove precision; a mid-bucket disconnect means 10+ unrecorded balls before anyone notices.

## Minor Observations

- The simulate-shot bolt button sits among real device controls and injects synthetic shots into the real draft with no "simulated" marking.
- Offline math duplicated with hardcoded `3.14159` in shot_list_panel.dart vs `math.pi` in table_tab.dart — drift hazard.
- ErrorBanner insertion shifts the whole layout down.
- Capacitor indicator reuses a battery icon in orange next to the actual battery chip — two battery icons meaning different things.
- Session naming copy "Session - $dateStr" is un-designed; summary omits duration and the session's name; sheet is swipe-dismissable with no "not saved" feedback.
- Nav label "Split view" persists on phones where the split is a vertical stack.
- Theme defines a full token scale (headings, captions, spacing) that this screen almost entirely bypasses with raw size calls.

## Questions to Consider

1. The golfer's most important runtime question — "can I hit now?" — gets 12 pixels while the nav bar gets 56. What would this screen look like if the whole frame (a screen-edge glow, a background tint) were the ball-state indicator, legible from address position?
2. If "analysis ends in an action" is the product's reason to exist, why does a session end on "14 shots, 3 clubs" instead of the optimizer's one-line verdict — and why is the optimizer a dockable pane equal in rank to a data table rather than the finale?
3. This screen renders simulated carry next to measured ball speed with identical typography. Is the brand willing to visibly mark its own simulation as simulation in the live UI — the one place users form their trust — or only in the validation docs?
