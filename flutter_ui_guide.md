# Flutter UI Design Guide

> A consolidated reference synthesised from UI/UX design books for use across Flutter projects.
> Organised by concept. Grows with each source added.

**Sources**
- *Practical UI* (2nd ed.) — Adham Dannaway
- *Making Design Decisions* — Tommy Geoco

---

## Table of Contents

1. [Design Fundamentals](#1-design-fundamentals)
   - 1.10 [Lightweight Decisioning Chain](#110-a-lightweight-decisioning-chain)
   - 1B. [Less Is More](#1b-less-is-more)
   - 1C. [Cognitive Psychology Reference](#1c-cognitive-psychology-reference)
   - 1D. [Nielsen's Usability Heuristics](#1d-nielsens-usability-heuristics)
2. [Design Systems & Tokens](#2-design-systems--tokens)
3. [Colour](#3-colour)
4. [Typography](#4-typography)
5. [Spacing & Layout](#5-spacing--layout)
6. [Components](#6-components)
7. [Accessibility](#7-accessibility)
8. [Copywriting & Content](#8-copywriting--content)
9. [Forms](#9-forms)
10. [Mobile-Specific](#10-mobile-specific)

---

## 1. Design Fundamentals

### 1.1 Always Have a Reason

Every design decision should have a logical rationale — not just aesthetic preference. Being able to articulate *why* a decision was made makes design faster, more defensible, and easier to review. Objective logic beats subjective opinion in design discussions.

### 1.2 Minimise Usability Risk

Evaluate every design choice for the risk that someone might struggle with it. Common risk areas include:

- Thin or low-contrast text (looks sleek, hard to read for many)
- Icons without labels (looks clean, risky for users with cognitive impairments)
- Coloured heading text (can be confused with links)

If something is vague or unclear, simplify it before investing in usability testing.

### 1.3 Minimise Interaction Cost

Interaction cost = the sum of physical and mental effort required to complete a task. Every tap, scroll, read, wait, and decision adds to this cost. Aim to keep it as low as possible.

**Key strategies:**

- **Keep related actions close** (Fitts's Law: closer + larger targets are faster to reach). Minimum touch target size: **48×48pt**.
- **Reduce distractions** — animated banners, pop-ups, and unnecessary visuals pull attention away from the task.
- **Minimise choices** (Hick's Law: more options = slower decisions). Highlight recommended or popular options to accelerate decisions.

**Flutter note:** Use `InkWell` / `GestureDetector` with appropriate `padding` to ensure touch targets meet 48pt. Use `ListTile` minLeadingWidth and `minVerticalPadding` consciously.

### 1.4 Minimise Cognitive Load

Cognitive load is how much mental effort an interface demands. Reduce it by:

- Removing unnecessary styles, information, and decisions
- Breaking complex content into smaller, clearly grouped chunks
- Using familiar, conventional design patterns
- Maintaining visual consistency — similar things should look and behave similarly
- Creating a clear visual hierarchy so importance is immediately obvious

**Example:** Break long forms into multiple steps rather than presenting everything at once.

### 1.5 Use Common Design Patterns (Jakob's Law)

People spend most of their time on *other* apps. Stick with patterns they already know — accordions, bottom sheets, tab bars, pull-to-refresh. Building on existing mental models reduces cognitive load and interaction cost.

Only deviate from convention when the unique value of the product demands it.

### 1.6 The 80/20 Rule (Pareto Principle)

Roughly 80% of users use 20% of features. 80% of complaints come from 20% of issues. Design for the common case first. Optimise for the tasks most users will do most often, rather than spending time on rare edge cases.

### 1.7 Be Consistent

Consistency means similar elements look and work similarly — both within your product and compared with platform conventions. Define guidelines and stick to them:

- Use one colour for all interactive elements
- Use sentence case throughout
- Left-align buttons and body text
- Be concise and use plain language everywhere

**Flutter note:** Use `ThemeData` to enforce consistency globally. Define `TextTheme`, `ColorScheme`, `ButtonTheme`, and `InputDecorationTheme` once and reference them throughout.

### 1.8 Clearly Indicate Interaction States

Every interactive element must change its appearance when interacted with, so users understand what's tappable and what state it's in. There are 5 states to design for:

| State | Trigger |
|---|---|
| **Default / enabled** | Element is interactive but not yet interacted with |
| **Hover** | Cursor placed over the element (desktop/web) |
| **Press / active** | Element is currently being pressed |
| **Focus** | Keyboard navigation has selected the element |
| **Disabled** | Element is not currently interactive |

**Flutter note:** Use `MaterialState` / `WidgetState` properties on `ButtonStyle`, `InputDecorationTheme`, etc. to define each state. `InkWell` handles press states automatically via ripple. For focus, ensure `FocusNode` and visible `focusColor` are configured.

### 1.9 Be Consistent with Platform Guidelines

Follow iOS (Human Interface Guidelines) and Android (Material Design) conventions unless usability testing shows a specific pattern fails for your users. Familiar patterns across platforms reduce learning time and prevent confusion.

Common conventions to follow: underlined text links, checkbox as a square with tick, input fields as rectangles with a label above, radio buttons as circles.

**Flutter note:** Use `CupertinoWidgets` for iOS-specific screens where platform parity matters, or use `adaptive` constructors (e.g. `Switch.adaptive`) to automatically respect platform conventions.

### 1.10 A Lightweight Decisioning Chain

When facing a UI decision under time pressure, run through this three-step chain of command in order. Each step provides a fallback when the next is unavailable.

| Priority | Source | What it means |
|---|---|---|
| **1 — Institutional knowledge** | Your information scaffold: psychology, usability principles, established design systems, accessibility guidelines | Start here. This is the accumulated baseline of what is known to work in human-computer interaction. It's your fastest path to a defensible default. |
| **2 — Customer familiarity** | Competitor patterns, market-adjacent products your users know (e.g. operating systems, Google Sheets), your own existing app patterns | Overrides institutional knowledge when users are demonstrably accustomed to a different convention. Familiarity reduces risk in the absence of data (see Jakob's Law, §1.5). |
| **3 — User research** | Interviews, surveys, analytics, instrumentation | The most contextually relevant source. When available, it overrides both of the above. |

**How to use it:** Start at level 1. If level 2 contradicts it and you have reason to believe your users are familiar with a specific pattern, apply level 2. If level 3 data is available, let it have the final word. When in doubt, move fast and treat the decision as a bet you'll validate later — slow decisioning has a real cost.

**Good enough is a feature.** The goal of this chain isn't to find the perfect answer — it's to find the *minimum necessary clarity* to proceed. A decision made at level 1 that ships today beats a theoretically superior decision made at level 3 next month.

---

## 1B. Less Is More

> A dedicated set of simplification principles that apply across every area of UI design.

### Remove Unnecessary Information

Every element you add competes with existing elements, increasing cognitive load. Ask whether each element has a logical reason to exist. Quick checks:

- Remove repeated elements (e.g. if a section heading already provides context, don't repeat it inside each list item)
- Avoid unneeded introductory phrases and filler words
- Reveal less important information gradually (progressive disclosure)

### Remove Unnecessary Styles

Avoid lines, colours, backgrounds, and animations that don't convey information. Purely decorative styles that add no meaning increase cognitive load and introduce usability risk:

- Decorative colours on list items can imply meaning where there is none
- Coloured, underlined headings can be mistaken for links
- Decorative icons near headings can be mistaken for buttons
- Competing visual prominence across icons creates attention overload

**Avoid style trends.** Trendy visual styles (glassmorphism, neumorphism) often fail contrast and hierarchy requirements. Minimal styles that highlight quality content age better. If you experiment with visual trends, verify they still meet WCAG contrast requirements.

### Links — Not Everything Needs Underline + Colour

In body text, links should be coloured and underlined for accessibility. But some components already feel interactive through other cues (cards with images, navigation tabs, raised containers). For these, removing the underline/colour treatment simplifies the interface without losing clarity.

Also: styling a link with both brand colour *and* underline can make it too visually prominent, disrupting the visual hierarchy. In dense UI (like a list of users), underline alone may be sufficient.

### Progressive Disclosure

Show users only what they need to complete the current task. Reveal additional information on demand. This reduces cognitive load and speeds up decision making — at the cost of a small number of extra interactions.

**Flutter patterns:**
- `ExpansionTile` / `ExpansionPanel` for collapsible content
- Conditional field display triggered by a `Checkbox` or `Switch`
- Bottom sheets and dialogs for secondary actions
- Showing only a summary with a "See more" control

### Minimalism ≠ Simplicity

A minimal interface (fewer elements) is not automatically a simple one. Removing too much can leave users confused. Labels, selected states, and action visibility are critical — don't sacrifice them for aesthetics.

Red flags of false minimalism:
- Unlabelled tabs or icons (users can't tell what they do)
- Insufficient contrast on selected state (users can't tell what's selected)
- Actions hidden in a `...` menu when space exists to show them
- Icon-only navigation with no labels

### Make Important Content Visible

People don't use what they can't see. If something matters, show it. If space constraints force you to hide it, make it *discoverable*:

- Expose the edge of off-screen cards so users know they're there (horizontal scroll hint)
- Don't put primary actions behind a `...` overflow menu if there's room to surface them
- Navigation links are more effective visible than hidden behind a hamburger menu

**Flutter note:** Use `PageView` or horizontal `ListView` with `clipBehavior: Clip.none` and visible next-card peeking to signal scrollability.

### Design for the Smallest Screen First

Start at the smallest screen size. Constraints force you to prioritise — only what's essential survives. The result is a simpler, more focused design that scales up gracefully, rather than a dense layout that can't scale down.

### Reduce Choice to Speed Up Decisions (Hick's Law)

Four strategies for reducing choice complexity:

1. **Remove choices** — every option should earn its place. Fewer form fields, fewer nav items, fewer CTAs all reduce friction.
2. **Group or categorise** — let users decide between a small number of categories before drilling into a larger set. Use tabs, segmented controls, or section headers.
3. **Break into steps** — multi-step flows (wizards, steppers) let users focus on one decision at a time. Complex navigation menus can be broken into levels.
4. **Recommend** — surface popular or common choices to accelerate decisions (suggested searches, pre-selected defaults, recommended plan highlighted).

**Flutter note:** Use `Stepper` widget for multi-step flows. Use `TabBar`/`TabBarView` for category-based navigation. Use `SearchDelegate` or `Autocomplete` for search suggestions.



---

## 1C. Cognitive Psychology Reference

> A quick-reference catalogue of psychological models relevant to UI and interaction design. Grouped by the cognitive function they relate to. Use these to justify design decisions, spot patterns in competitor products, and reduce reliance on subjective debate.
>
> **Source:** *Making Design Decisions* — Tommy Geoco (synthesised from Benson, Weinberg, Yablonski, Benoni & Lavallee)

### Filtering — Reducing Information Overload

These models describe how the brain filters noise and decides what to pay attention to.

| Model | Definition | Flutter relevance |
|---|---|---|
| **Aesthetic-Usability Effect** | Visually attractive products are perceived as more usable, even if they aren't. First impressions affect trust. | Invest in polish on first-seen screens (onboarding, home). A rough-looking launch screen undermines confidence in reliability. |
| **Anchoring** | Users fixate on the first piece of information they see and use it as a reference point for everything after. | Lead with the most favourable metric, price, or framing. The first item in a list or card disproportionately shapes interpretation of the rest. |
| **Banner Blindness** | Users habitually ignore elements that look like ads or unrelated promotions. | Avoid styling important system messages or CTAs like banners. If it looks promotional, it will be skipped. |
| **Center-Stage Effect** | Users direct more attention to items placed in the centre of a layout. | Place primary actions and key information centrally. Use this deliberately for empty states, onboarding illustrations, and featured content. |
| **Cognitive Load** | The mental effort required to process, understand, and act on information. Higher load → more errors, frustration, and abandonment. | Reduce forms to the minimum fields needed. Break dense screens into sections. Avoid excessive animations competing for attention. |
| **Hick's Law** | Decision time increases with the number of available options. | Limit navigation items, filter options, and button counts. Recommend a default or highlight a popular option. |
| **Nudging** | Subtle visual or positional cues steer users toward a desired action without removing other options. | Pre-select a recommended plan tier. Use visual weight on the "confirm" path over the "cancel" path. |
| **Progressive Disclosure** | Reveal information gradually as users need it, rather than all at once. | Use `ExpansionTile`, bottom sheets, and detail pages. Surface primary data first; hide secondary data behind a tap. |
| **Tesler's Law** | Every system has an irreducible level of complexity — it can only be moved, not eliminated. Simplifying one part often shifts complexity elsewhere. | If a feature is complex by nature, absorb that complexity in the implementation rather than exposing it in the UI. Don't simplify by hiding necessary controls — simplify by writing better logic. |
| **Von Restorff Effect** | Items that visually stand out from their surroundings are noticed and remembered. | Use a single accent colour, badge, or size increase to draw attention to the single most important action on a screen. Avoid using this technique on multiple elements — the effect cancels out. |
| **Decoy Effect** | The presence of a third, clearly inferior option makes one of the other two options look more attractive. | Useful in pricing pages: a "decoy" middle tier can make the premium tier look like better value. |

### Sense-making — Assigning Meaning to Information

These models describe how the brain groups, connects, and interprets what it perceives.

| Model | Definition | Flutter relevance |
|---|---|---|
| **Jakob's Law** | Users expect new products to behave like products they already use. Familiarity reduces cognitive load. | Model new flows on established patterns (tabs, bottom nav, pull-to-refresh, swipe to dismiss). Only deviate when the unique value demands it. |
| **Law of Common Region** | Elements enclosed in a visible boundary are perceived as a group. | Use `Card`, rounded containers, or background fills to group related fields (e.g. a form section). A border implies membership. |
| **Law of Proximity** | Elements placed close together are perceived as related. | Space closely-related items (e.g. label + input) tightly. Use generous gaps between unrelated sections. This is the first tool for grouping — before colour or borders. |
| **Law of Prägnanz** | The brain simplifies complex shapes into the simplest recognisable form. | Use clear, simple icon shapes. Avoid overly complex illustrations that take effort to decode. Users will simplify what they see — design so the simplified version is still correct. |
| **Law of Similarity** | Elements that look alike are perceived as related. | Use consistent colour, size, and shape for elements of the same type. Inconsistency implies different meaning even when none was intended. |
| **Law of Uniform Connectedness** | Elements connected by visible lines, arrows, or shared colour are perceived as related. | Use connecting lines in flow diagrams, shared background fills in grouped settings, or consistent icon colour within a category. |
| **Occam's Razor** | When multiple explanations exist, the simplest is most likely correct. Prefer clarity over complexity. | Favour straightforward layouts. If a design requires explanation to be understood, simplify it. |
| **Social Proof** | Users look to others' behaviour and opinions to guide their own decisions. | Surface ratings, review counts, "X people are using this", or testimonials near conversion points. |

### Recall — What the Brain Chooses to Remember

These models describe how memory affects design decisions and long-term user experience.

| Model | Definition | Flutter relevance |
|---|---|---|
| **Miller's Law** | The average person can hold ~7 items (±2) in short-term working memory at once. | Limit navigation items, filter categories, and list options to 5–9. Group items if more are needed — chunking reduces working memory load. |
| **Peak-End Rule** | Users remember an experience based on its most intense moment and its final moment, not the average. | Make onboarding delightful. Make the success/completion state memorable. A rough middle is forgiven if the end is great. Invest disproportionately in first-run and key completion moments. |
| **Picture Superiority Effect** | Images are remembered more reliably than words. | Use illustrations and iconography for key concepts, error states, and empty states. A well-chosen illustration communicates faster and is recalled better than a text explanation. |
| **Serial Position Effect** | Items at the beginning and end of a list are remembered better than items in the middle. | Put the most important navigation items at the start and end of a tab bar or list. The middle items are least likely to be noticed or recalled. |
| **Zeigarnik Effect** | Users think about and remember uncompleted tasks more than completed ones. Incompletion creates cognitive tension. | Use progress indicators, streaks, and "resume where you left off" patterns. An incomplete form or onboarding flow stays active in a user's mind and motivates return. |

### Efficiency — Acting Quickly Under Uncertainty

These models describe how the brain makes decisions when time or information is limited.

| Model | Definition | Flutter relevance |
|---|---|---|
| **Decision Fatigue** | The quality of decisions deteriorates after many decisions have been made. Users become more likely to pick defaults or abandon entirely. | Keep late-form steps simple. Don't front-load a flow with complex decisions. Put the hardest choices early when mental energy is highest. |
| **Default Bias** | Users tend to stick with the default option, perceiving it as the recommended or safest choice. | Set defaults thoughtfully — they are the most frequently chosen option whether you intend them to be or not. Use pre-selection to reduce friction on common choices. |
| **Doherty Threshold** | User productivity and engagement increase when a system responds in under 400ms. Delays above this break the sense of flow. | Target <100ms perceived response for all interactions. Use `CircularProgressIndicator` for anything over 400ms. Skeleton loading states prevent perceived latency on data fetches. |
| **Goal-Gradient Effect** | Motivation to complete a task increases as users get closer to finishing it. | Show progress indicators in multi-step flows. Mark completed steps visibly. The closer to the end, the more you can ask of the user. Consider "rewarding" early progress to create artificial momentum (e.g. a profile completeness bar starting at 30%). |
| **Hyperbolic Discounting** | Users heavily prefer smaller, immediate rewards over larger, delayed ones. | Offer something of immediate value at sign-up before asking users to invest in setup. Trial features with instant access outperform gated features with future promises. |
| **IKEA Effect** | Users place higher value on things they have helped to create or configure. | Personalisation, setup flows, and user-generated content all increase perceived value and retention. Let users configure — even superficially — to build ownership. |
| **Investment Loops** | Users who have invested time or effort in a product are more likely to continue using it. | Encourage early micro-investments: adding data, setting preferences, completing a profile. Each investment raises the cost of leaving. |
| **Pareto Principle** | 80% of outcomes come from 20% of effort. Most user impact comes from a small number of features. | Identify the top-used features and optimise them first. Don't spread effort evenly. Track which flows are used most and make those the smoothest. |
| **Planning Fallacy** | People systematically underestimate how long tasks will take. | Build conservative time estimates into scheduled processes. If you show an ETA, err generous. |
| **Priming** | Exposure to one stimulus influences how users respond to a subsequent one. | The content, language, and imagery a user sees before a key action influences their decision. Use imagery of success, ease, or social proof immediately before a conversion moment. |
| **Second-Order Effects** | A design change in one part of a system often creates unintended consequences elsewhere. | Before shipping a pattern change, map downstream effects: does changing button placement break existing muscle memory? Does adding a feature create a new navigation depth problem? |
| **Sunk Cost Effect** | Users continue investing in something they've already spent time/effort on, even when it's not working well. | Progress indicators, investment in data entry, and partially completed flows all make users more likely to complete — even if the flow is long. |
| **Weber's Law** | The noticeable difference between two stimuli is proportional to the original stimulus. Small changes to large values are less perceptible. | Subtle design updates to familiar screens may go unnoticed — which is often desirable for non-breaking changes. For deliberate redesigns, make the change significant enough to register. |

---

## 1D. Nielsen's Usability Heuristics

> A checklist of 10 principles for evaluating and designing usable interfaces. Use during ideation to guide initial structure, and during review to identify usability problems. These are guidelines, not strict rules.

| Heuristic | What it means | Flutter check |
|---|---|---|
| **Keep users informed** | Always tell users what's happening. Show loading states, confirm actions, display progress. | Use `CircularProgressIndicator`, `SnackBar` confirmations, and `Stepper` progress. Never leave a user waiting without feedback. |
| **Use familiar language** | Speak the user's language. Avoid technical jargon. Follow real-world conventions in labelling and organisation. | Review all copy with a non-technical reader. Match terminology to what your user calls things, not what the codebase calls them. |
| **Give users control** | Let users undo, redo, and exit. Don't trap them in flows with no way back. | Use `Navigator.pop()` reliably. Provide undo after destructive actions (e.g. swipe-to-delete + undo `SnackBar`). |
| **Be consistent** | Same words, same actions, same visual patterns mean the same thing throughout. | Enforce via `ThemeData`. Define and follow conventions for button placement, colour usage, and terminology. |
| **Prevent errors** | Design so mistakes are difficult to make. Confirm before destructive actions. | Use confirmation dialogs before deletes. Disable submit until required fields are valid. Show constraints before users violate them. |
| **Make information easy to find** | Users shouldn't need to memorise information from one screen to apply it on another. Keep context visible. | Show a summary of earlier choices when asking for later ones. Don't hide key labels after a field is filled. |
| **Be efficient** | Expert users should be able to move fast. Support power-user shortcuts and customisable frequent actions. | Consider swipe actions, long-press shortcuts, and keyboard navigation on desktop. Don't force all users through the same slow path. |
| **Keep the design simple** | Every element should earn its place. Remove anything that doesn't communicate something the user needs. | Regularly audit screens for elements that can be removed, condensed, or deferred via progressive disclosure. |
| **Help users fix errors** | Error messages should be plain language, explain what went wrong, and suggest how to fix it. | Validation messages should be specific ("Password must be at least 8 characters") not generic ("Invalid input"). Position errors close to the relevant field. |
| **Provide help** | When help is necessary, it should be easy to find, task-focused, and concise. | Tooltips, contextual info icons, and inline hints cover most cases. Full help docs are a last resort, not a first. |

---

## 2. Design Systems & Tokens

A design system is a set of predefined options and guidelines that lets you make design decisions efficiently and consistently. Build it in 3 steps: **set predefined style options → create reusable modules → define usage guidelines**.

### 2.1 Colour Tokens

Define a small, purposeful colour palette rather than picking ad-hoc. A practical structure:

| Token | Role |
|---|---|
| `brand` | Primary brand colour — buttons, links, active states |
| `textStrong` | High-emphasis body text |
| `textWeak` | Secondary / supporting text |
| `strokeStrong` | Borders on interactive elements (inputs, checkboxes) |
| `strokeWeak` | Dividers, subtle separators |
| `fill` | Light background fills for cards, inputs |

Use the brand colour exclusively for interactive elements so users learn what's tappable.

**Flutter note:** Map these to `ColorScheme` properties. Use `Theme.of(context).colorScheme.primary` etc. rather than hardcoded hex values.

### 2.2 Typography Tokens (Type Scale)

Define font sizes, weights, and line heights once and reuse. A practical scale using a ~1.2 ratio:

| Token | Size | Line Height | Weight |
|---|---|---|---|
| `heading1` | 40pt | 48pt | Bold |
| `heading2` | 32pt | 40pt | Bold |
| `heading3` | 24pt | 32pt | Bold |
| `heading4` | 20pt | 28pt | Bold |
| `body` (Small) | 16pt | 24pt | Regular |
| `caption` (Tiny) | 14pt | 20pt | Regular |

**Flutter note:** Define these in `TextTheme` within `ThemeData`. Use `Theme.of(context).textTheme.headlineLarge` etc. Avoid hardcoded `fontSize` values in widgets.

### 2.3 Spacing Tokens

A limited spacing scale prevents arbitrary values and keeps layouts consistent:

| Token | Value |
|---|---|
| `spaceXS` | 8pt |
| `spaceS` | 16pt |
| `spaceM` | 24pt |
| `spaceL` | 32pt |
| `spaceXL` | 48pt |
| `spaceXXL` | 80pt |

Space elements based on their relationship — closely related elements use smaller gaps, less related elements use larger gaps. This creates visual grouping without needing explicit dividers.

**Flutter note:** Define as `const` values in a `AppSpacing` class. Use `SizedBox` or `EdgeInsets` referencing these constants rather than magic numbers.

### 2.4 Shadow Tokens

Two shadow options are generally sufficient:

- **Raised** — for cards and elevated surfaces
- **Overlay** — for modals, bottom sheets, and popovers

**Flutter note:** Define in `ThemeData.shadowColor` and reuse via `BoxDecoration` or `Material` elevation.

### 2.5 Border Radius Tokens

Three values handle most cases:

| Token | Value | Use |
|---|---|---|
| `radiusS` | 8pt | Small elements (chips, badges, inputs) |
| `radiusM` | 16pt | Cards, buttons |
| `radiusL` | 32pt | Large containers, bottom sheets |

### 2.6 Modular Component Architecture

Build components bottom-up:

1. **Atoms** — smallest units: buttons, avatars, text fields, icons
2. **Molecules** — combinations: avatar + text row, input + label
3. **Organisms** — larger components: cards, list items, modal dialogs
4. **Templates** — page-level layouts assembled from organisms

The same small component (e.g. an avatar) should be reusable across many larger components. This mirrors Flutter's widget composition model naturally.

### 2.7 Usage Guidelines

A design system without guidance is incomplete. Document at minimum:

- Which colour to use for interactive elements
- How to handle text casing (sentence case everywhere)
- Button alignment conventions (left-align in most cases)
- When to use which button weight (primary / secondary / tertiary)
- Copywriting tone and style rules

### 2.8 Reference Design Systems

These publicly documented design systems are worth consulting when looking for established patterns, naming conventions, or accessibility guidance. They are built and maintained by large teams with serious resources, and collectively serve billions of users.

| System | Owner | Particularly worth referencing for |
|---|---|---|
| **Material Design** | Google | Motion principles, dark theme, elevation system, colour roles |
| **Fluent** | Microsoft | Downloadable design toolkits, density patterns for data-heavy UIs |
| **Human Interface Guidelines** | Apple | iOS/iPadOS/macOS conventions, keyboard shortcuts, gesture patterns |
| **Carbon** | IBM | Data visualisation colour rules, accessibility in complex UIs |
| **Polaris** | Shopify | Token naming conventions, UX writing standards |
| **Workbench** | Gusto | Broad component library with good real-world examples |
| **Primer** | GitHub | Accessibility section, inclusive design patterns |

**How to use these:** When designing a new pattern, spend 5 minutes checking how two or three of these systems handle it. You're not copying — you're cross-referencing institutional knowledge. Patterns consistent across multiple mature systems are lower-risk bets.

**Flutter note:** Material Design maps directly to Flutter's widget system. `ThemeData` in Flutter is essentially a partial implementation of the Material Design spec. Where Material's documentation is more detailed than Flutter's, it still applies as the design intent behind what Flutter's widgets render.

---

## 3. Colour

### 3.1 Sufficient Contrast — WCAG 2.1 AA (Current Standard)

Contrast is the perceived brightness difference between two colours, expressed as a ratio (1:1 to 21:1). Meet WCAG 2.1 Level AA as a minimum:

| Element Type | Minimum Ratio |
|---|---|
| Small text (18px or less) | **4.5:1** |
| Large text (24px+ regular, or 18px+ bold) | **3:1** |
| UI components (form borders, icons, checkboxes) | **3:1** |
| Decorative elements (no meaning conveyed) | No requirement |

Common failures to watch for:
- Close/dismiss icon contrast below 3:1
- Secondary/supporting text below 4.5:1
- Input field border contrast below 3:1
- Placeholder text below 4.5:1
- Button background vs white label text below 4.5:1
- Link text below 4.5:1

**Flutter note:** Validate colours using tools like [contrast-ratio.com](https://contrast-ratio.com) or the [Accessible Colors](https://accessible-colors.com) site before setting them in `ColorScheme`. The Flutter Accessibility Scanner can flag issues post-build.

### 3.2 APCA — The Improved Contrast Model (WCAG 3 Draft)

APCA (Accessible Perceptual Contrast Algorithm) fixes key limitations of WCAG 2. Unlike WCAG 2 ratios, APCA scores are directional (text vs background matters) and font-size aware.

**APCA thresholds:**

| Score | Use case |
|---|---|
| **Lc 90** | Preferred for body text (14px+ regular) |
| **Lc 75** | Minimum for body text (18px+ regular) |
| **Lc 60** | Minimum for other text (24px+ regular or 16px+ bold) |
| **Lc 45** | Minimum for large text (36px+ regular or 24px+ bold) and UI elements |
| **Lc 30** | Absolute minimum for placeholder text, disabled button text |
| **Lc 15** | Minimum for non-text elements |

Key APCA insight: white text on a coloured button can *pass* APCA while failing WCAG 2, and vice versa. APCA is more accurate to human perception. APCA also handles dark-background interfaces correctly, where WCAG 2 often produces false passes.

**Recommendation:**
- Personal/new projects: use APCA
- Commercial projects with legal compliance requirements: use WCAG 2.1 AA as the baseline, but try to pass APCA as well for optimal results

### 3.3 Don't Rely on Colour Alone

Never use colour as the *only* indicator of meaning (e.g. red = error). Always pair with an icon, label, or pattern so colour-blind users aren't excluded.

### 3.4 Colour for Interactive Elements

Apply the brand colour consistently to all interactive elements: buttons, text links, active tabs, toggles. This teaches users what's tappable. Avoid using the brand colour on non-interactive elements like decorative headings.



---

## 4. Typography

### 4.1 Typeface Classifications

A **typeface** is a set of related fonts sharing a common design style. A **font** is a specific variation within that typeface (e.g. weight or size). There are five main classifications:

| Classification | Character | Best used for |
|---|---|---|
| **Sans serif** | No decorative tails; clean, modern | UI body text, labels, headings — the default safe choice |
| **Serif** | Decorative tails/feet; traditional, formal | Brand headings, editorial contexts; avoid for small UI text |
| **Script** | Handwriting-based; low legibility | Large display headings only; never body text |
| **Display** | Decorative and varied; high character | Large headings only; too complex for small sizes |
| **Monospaced** | Fixed-width characters | Code blocks, numeric tables where alignment matters |

### 4.2 Use a Single Sans Serif Typeface

For most apps, use **one sans serif typeface** throughout. Three reasons:

**Legibility:** Sans serif letterforms are the most clearly distinguishable at small sizes. Since the primary job of UI text is to communicate clearly, legibility takes priority over personality.

**Neutrality:** Sans serif typefaces don't project a strong mood or personality. This means the typeface won't clash with most brand identities, content stays the focal point, and there's far less risk of an unsuitable choice.

**Simplicity:** More typefaces = more cognitive load = more inconsistency in application. One typeface with two weights is a complete, maintainable system.

**Flutter note:** Set `fontFamily` in `ThemeData`. Use the `google_fonts` package for broad typeface access. When in doubt, the platform's default system font (SF Pro on iOS, Roboto on Android) is a safe, fast-loading, well-tested choice.

**Tips for choosing a sans serif:**
- Sort font directories by popularity and start there — popular typefaces are popular because they work
- Look for typefaces available in at least Regular and Bold weights (more weights = higher quality signal)
- Prefer higher x-height (taller lowercase letters) and more generous letter spacing — these improve legibility at small sizes
- Ensure the typeface supports all languages your app needs
- Look for OpenType support for better cross-platform rendering

### 4.3 Optional Second Typeface for Headings

As you gain confidence, you can introduce a second typeface for headings only — never for body text. Since it only appears at large sizes, legibility at small sizes is not a concern.

Different typeface styles evoke different feelings. Use this to reinforce brand personality:

| Style | Mood conveyed |
|---|---|
| Sans serif | Neutral, minimal, modern |
| Serif | Traditional, established, classic |
| Rounded sans serif | Fun, soft, playful |
| Casual script | Personal, handmade |
| Formal script | Formal, feminine, elegant |
| Light/thin sans serif | Chic, modern, luxurious |

**Rule:** Never use more than two typefaces in a single interface. If in doubt, stick with one.

### 4.4 Font Weights — Regular and Bold Only

Limit yourself to **regular** and **bold** weights only. Using additional weights (thin, light, medium, semibold, extra bold) adds visual noise, makes consistent application harder, and slows down the design process.

Usage:
- **Bold:** headings and any text that needs emphasis
- **Regular:** body text, labels, captions, metadata
- Semi-bold is acceptable as a substitute for bold if bold feels too heavy for a particular typeface

**Flutter note:** Set `FontWeight.w700` (bold) and `FontWeight.w400` (regular) in your `TextTheme`. Avoid `FontWeight.w300`, `w500`, `w900` etc. unless there's a specific, intentional reason.

### 4.5 Type Scale

Rather than picking font sizes ad hoc, build a **type scale** — a set of sizes generated by multiplying a base size by a fixed ratio. This produces sizes that feel visually balanced together.

**Recommended starting point (Minor Third — ratio 1.200):**

| Token | Size | Line Height | Weight |
|---|---|---|---|
| `displayLarge` / H1 | 40pt | 48pt | Bold |
| `displayMedium` / H2 | 32pt | 40pt | Bold |
| `headlineMedium` / H3 | 24pt | 32pt | Bold |
| `titleMedium` / H4 | 20pt | 28pt | Bold |
| `bodyLarge` | 16pt | 24pt | Regular |
| `bodySmall` / caption | 14pt | 20pt | Regular |

**Choosing a scale:**
- **Small scales** (e.g. Major Second, ratio 1.125): more subtle size differences, better for dense dashboards and tool UIs
- **Large scales** (e.g. Perfect Fifth, ratio 1.500): dramatic size differences, better for marketing sites and simple content apps
- For mobile apps, a Minor Third (1.200) or Major Third (1.250) is a good default
- Consider using a smaller scale on mobile if your desktop scale causes text to wrap awkwardly

Round all sizes to the nearest whole number. Aim for line heights divisible by 4 so text aligns cleanly to a 4pt vertical grid.

**Flutter note:** Define the scale in `ThemeData.textTheme` using the Material 3 `TextTheme` tokens. Never hardcode `fontSize` values directly in widgets — always reference the theme.

### 4.6 Body Text Size

Make long-form body text **at least 18pt**. Users read from roughly arm's length away on all device types. Text that looks fine while designing at a desk often feels small in real use. 14pt is too small for comfortable sustained reading; 18pt is where readability meaningfully improves for most typefaces.

**Flutter note:** Set `bodyLarge` in `TextTheme` to at least 18pt for reading-heavy screens. You may use 16pt for denser UI contexts (settings, forms) but increase it for article or content views.

### 4.7 Line Height

Line height is the vertical distance between two lines of text. It's expressed as a multiplier of the font size.

**Rules:**
- **Body text:** minimum **1.5× (150%)** — a 1.6× multiplier is a good working default
- **Headings:** decrease line height as size increases. A 24pt heading does not need the same 1.6 multiplier as 16pt body text — the physical gap between lines would be too large
- Target line heights divisible by 4 where possible (helps with vertical grid alignment)

| Context | Recommended line height |
|---|---|
| Body (16–18pt) | 1.5–1.6 |
| Subheading (20–24pt) | 1.3–1.4 |
| Heading (28–40pt) | 1.1–1.2 |

**Additional factors:** longer lines need taller line height; darker/heavier typefaces need taller line height; typefaces with larger optical size need taller line height.

**Flutter note:** Set `height` in `TextStyle` (this is the Flutter line height multiplier). E.g. `TextStyle(fontSize: 16, height: 1.6)`. Define these in `TextTheme` rather than per-widget.

### 4.8 Line Length

Ideal line length for comfortable reading is **40–80 characters per line** (including spaces). Shorter lines cause the eye to return too frequently; longer lines make it hard to track from the end of one line to the start of the next.

**Don't stretch text to fill the full screen width.** On tablet and desktop layouts especially, constrain text column width explicitly. Align the constrained column to the left or centre of the available space.

**Flutter note:** Use `ConstrainedBox(constraints: BoxConstraints(maxWidth: 640))` to cap text column width on wider screens. Inside `Column` layouts, wrap the text widget rather than letting it expand unconstrained via `Expanded`.

### 4.9 Text Alignment

See Section 5.8 for the full alignment rules. Brief typography-specific notes:

- Always left-align body text and multi-line content
- Baseline-align mixed-size text sitting in the same row (e.g. a large price next to a small unit label)
- Centre alignment is only appropriate for very short standalone labels (empty states, marketing headlines); never use it for paragraph text

**Flutter note:** Use `CrossAxisAlignment.baseline` with `textBaseline: TextBaseline.alphabetic` on `Row` widgets to baseline-align mixed-size text.

### 4.10 Letter Spacing

- **Large display/heading text:** slightly reduce letter spacing (tighten) — large text with default tracking can feel loose and disconnected
- **Small UI text (captions, labels):** default or slightly increased spacing is fine
- **ALL CAPS text:** always increase letter spacing — all-caps text with normal spacing is difficult to read

**Flutter note:** Use `letterSpacing` in `TextStyle`. Negative values tighten, positive values open up the spacing. Define in `TextTheme` entries rather than per-widget.



---

## 5. Spacing & Layout

> *(Detailed layout guidelines to be populated from full Chapter 4 content)*

### 5.1 Group Related Elements

Elements that belong together should be spaced more closely than elements that don't. Use proximity to create visual grouping before reaching for borders or dividers.

**Rule:** Spacing *within* a group should be smaller than spacing *between* groups.

### 5.2 Visual Hierarchy

Not all information is equally important. A clear visual hierarchy guides users through a screen in the intended order, reduces cognitive load, and improves aesthetics.

**Six levers for creating hierarchy:**

| Lever | How to use it |
|---|---|
| **Size** | Make important elements larger — title > subtitle > body > caption |
| **Colour** | Use brighter, richer, or higher-contrast colour for prominent elements |
| **Contrast** | Style key elements differently from surrounding content so they stand out |
| **Spacing** | Surround important elements with more white space — space = importance |
| **Position** | Place important elements at the top or first in a horizontal row |
| **Depth** | Elevate important elements with shadow so they appear closer to the user |

**The Squint Test:** Squint at your layout until it blurs. The most important elements should still be the most obvious. Alternatively, step back from the screen or zoom out. If everything looks equally weighted, the hierarchy is too flat. If the test fails, increase the contrast between your most and least important elements.

**Step-by-step approach to building hierarchy in any screen:**

1. Group related content into logical sections
2. Within each section, order elements by importance
3. Order the sections themselves by importance — most important at the top
4. Apply size/weight/colour variations within each section based on element importance
5. Introduce icons where they aid scanability and align with conventions (Jakob's Law)
6. Apply the Squint Test

**Practical section-by-section hierarchy checklist** (e.g. a booking/product card):

- **Primary info** (name, location, rating): Large bold name using `textStrong`. Smaller `textWeak` for secondary details like location. Star icons for ratings (conventional and scannable).
- **CTA section** (price + action button): Pin to bottom of screen with a shadow — always visible and within thumb's reach. Make the price large and bold (it's the *last* item the eye sees; the **Serial Position Effect** means users best remember first and last items). Use a filled primary button for the action.
- **Detail attributes** (metadata like specs): Use unfilled outline icons in a `strokeStrong` colour to reduce icon dominance. Apply `textWeak` to labels to visually balance them with the icons.
- **Body text** (description, long-form): Remove redundant labels (e.g. "Description:") when the content is obviously descriptive. Use `textWeak` at regular weight — it should be the quietest region on the screen.

**Using depth (elevation) for hierarchy:**

Shadows and background colour shifts create a perception of layers. Elements that appear raised feel closer and more prominent. Use elevation purposefully:
- A sticky bottom CTA bar with a shadow feels persistently accessible and high-priority
- An elevated app bar signals that navigation is always reachable above scrolling content
- Cards with a subtle shadow feel interactive and separate from the page background
- Modals and sheets sit at the highest elevation, signalling they demand immediate attention

Elevation = prominence. The most important UI regions should sit highest in the visual stack.

**Flutter note:** Use `Material` with `elevation`, or `BoxDecoration` with `BoxShadow`. Map to `ElevatedButton` (primary CTA), `Card` (medium elevation), flat `Container` (lowest). Use `Theme.of(context).textTheme` for typographic hierarchy and `ColorScheme` tokens for colour-based hierarchy. For the sticky CTA bar pattern, use `Scaffold.bottomNavigationBar` slot or a `Stack` + `Positioned` widget with a `BoxShadow`.

### 5.3 The Box Model

Every UI element is a rectangle with four layers radiating outward: **Content → Padding → Border → Margin**.

- **Content** — the actual text, image, or child widget
- **Padding** — space between the content and the border (inner breathing room)
- **Border** — the stroke around the element's edge
- **Margin** — space between this element and neighbouring elements

The key insight is that an interface is made up of nested rectangles. Spacing is applied in layers: the innermost elements get the smallest spacing, and it grows progressively as you move outward. This creates natural visual structure without needing explicit dividers.

**Flutter note:** In Flutter, `Container` provides `padding` (inner) and `margin` (outer). `BoxDecoration` handles borders and background. `SizedBox` and `Padding` widgets control spacing without a visual container. Understand that Flutter's box model matches this pattern closely.

### 5.4 Design at 1×, Use Points (pt)

Points (pt) are the correct unit for UI design. On a standard screen, 1pt = 1px. On a high-density @2x screen, 1pt = 4 physical pixels (2×2). On @3x, 1pt = 9 physical pixels. Always specify values in points — they scale automatically to match the screen's pixel density.

**Flutter note:** Flutter uses logical pixels, which are equivalent to points. All Flutter layout values (`double` in `EdgeInsets`, `SizedBox`, etc.) are in logical pixels. Never think in raw pixels — Flutter handles density-appropriate rendering automatically.

### 5.5 Predefined Spacing System (8pt Grid)

Rather than picking spacing values by eye, define a small fixed set of t-shirt-sized spacing options in multiples of 8. This is called the **8pt grid system**:

| Token | Value | Typical use |
|---|---|---|
| `spaceXS` | 8pt | Tightest: space between icon and label, tag internal padding |
| `spaceS` | 16pt | Space between list items, standard component internal padding |
| `spaceM` | 24pt | Card internal padding, content within sections |
| `spaceL` | 32pt | Column gaps, spacing between major content blocks |
| `spaceXL` | 48pt | Generous section breathing room |
| `spaceXXL` | 80pt | Major vertical section separation (especially on web/tablet) |

**Why 8?** Most screen sizes are divisible by 8. It provides enough granularity without endless options. For very detail-dense UIs, you can use 4pt increments.

**The rule for which token to use:** Match the spacing to the relationship. Elements that are closely related get smaller gaps (XS/S). Elements that are less related get larger gaps (M/L/XL). Sections that are entirely separate get the largest gaps (XXL).

**Benefits of a predefined spacing system:** less variation, better consistency, and faster decision-making — because the number of choices is constrained.

**Practical spacing rules to document in your project:**
- Card internal padding: `spaceM` (24pt)
- Column gaps: `spaceL` (32pt)
- Major section separation: `spaceXXL` (80pt) on web/tablet, reduce proportionally on mobile
- When in doubt between two options, choose the larger one — more white space is nearly always better

**Flutter note:** Define as `const` values in an `AppSpacing` class. Reference these throughout your widget tree via `SizedBox(height: AppSpacing.m)` or `EdgeInsets.all(AppSpacing.s)`. Never use magic numbers.

### 5.6 White Space

White space is the empty area between and around elements — padding, margins, line spacing, and gutters. It is an active design tool, not wasted space.

**Benefits of generous white space:**
- Makes groupings and hierarchy more visible (tight spacing obscures both)
- Creates a perception of quality, clarity, and sophistication
- Reduces cognitive load by giving the eye natural places to rest

**The rule:** When in doubt, increase spacing to the next token up. If you were considering `spaceXS`, try `spaceS`. The cost of over-spacing is rare; the cost of under-spacing is very common.

Use the Squint Test to check white space: if you blur your vision and can't easily distinguish between groups of elements, increase the spacing between them.

**Flutter note:** Padding inside components is controlled by the `padding` parameter on most widgets, or by wrapping with `Padding`. Between components, use `SizedBox` with named spacing tokens. For `ListView` items, use `itemExtent` or wrap each item with consistent `Padding`.

### 5.7 12-Column Grid

A 12-column grid is the standard structure for aligning major interface elements. It consists of three parts:

**Columns:** The 12 vertical regions that content aligns to. Columns have flexible widths (percentage-based) so they adapt to screen size. On large screens, use all 12. Reduce to 4 columns on mobile. A component can span multiple columns — e.g. 3 cards side-by-side each span 4 columns on desktop, then stack to full-width on mobile.

**Gutters:** The fixed-width empty spaces between columns. Their purpose is to separate columns, not to contain content. Keep gutters narrower than columns. Scale gutter width with screen size — e.g. `spaceL` (32pt) on desktop, `spaceS` (16pt) on mobile.

**Margins:** The empty space to the left and right of the 12 columns, preventing content from hitting screen edges. Scale with screen size — e.g. `spaceXXL` (80pt) on desktop, `spaceS` (16pt) on mobile.

**Key rule:** The 12-column grid structures *major layout containers only*. Smaller elements *inside* those containers use your predefined spacing tokens, not the column grid.

**Why 12?** 12 divides evenly into 1, 2, 3, 4, 6, and 12, giving you the most layout flexibility. It also aligns with most front-end development frameworks.

**Flutter note:** Flutter doesn't have a native column grid system, but you can implement one with `Row` + `Expanded` using `flex` values proportional to column spans, or `GridView.builder` with a fixed `crossAxisCount`. For responsive grids, use `LayoutBuilder` with breakpoints and switch between column counts. The `flutter_staggered_grid_view` package offers more control for complex grid layouts.

### 5.8 Text Alignment

**Left-align almost everything.** Left-aligned text provides a consistent vertical anchor — the eye returns to the same left edge at the end of each line, making reading faster and less effortful. This principle extends beyond text: icons, labels, and other elements that accompany text should also align to the same left edge as the text next to them.

**Baseline alignment for mixed-size text in a row.** When two or more text elements of different sizes appear side by side (e.g. a large price and a small unit label), align them to the *baseline* (the invisible line text sits on), not the vertical centre. Baseline alignment keeps the text visually connected; centre alignment makes smaller text appear to float.

**Centre alignment is acceptable only for short standalone labels** — empty states, marketing banners, card titles in isolation. It becomes increasingly problematic for body text or any text that runs to more than one or two lines.

**Avoid mixing alignments within a single component.** If a card starts with a centre-aligned heading but has left-aligned body text below it, the eye must constantly reorient. Pick one alignment for a component and apply it consistently.

**Flutter note:** Use `TextAlign.left` (the default) for all body text. Use `crossAxisAlignment: CrossAxisAlignment.baseline` with `textBaseline: TextBaseline.alphabetic` on `Row` to achieve baseline alignment for mixed-size text. Avoid `CrossAxisAlignment.center` when rows contain text of different sizes.

### 5.9 Keep Related Actions Close (Fitts's Law)

Fitts's Law states that the time needed to reach a target is determined by its size and its distance from the starting point. Larger and closer targets are faster to reach. Applied to UI: reduce interaction cost by placing actions physically close to the element they operate on, and by making interactive targets large enough to tap accurately.

**Practical implications:**
- Place a dismiss/close button at the same position as the trigger that opened the element — users shouldn't have to reposition their finger to close something they just opened
- Left-align menu items and make them full-width with generous vertical padding — users don't need to aim precisely at small text
- Use bordered or visually contained list items to communicate the full tappable area, so users can tap anywhere within the item rather than having to be precise
- Small savings per interaction add up quickly when interactions are repeated across a session

Minimum touch target: **48×48pt** for any interactive element, even if the visible hit area appears smaller. Use padding to extend the tappable area.

**Flutter note:** Wrap small tappable elements in `InkWell` or `GestureDetector` with enough `padding` to reach 48pt. Use `ListTile` (which has generous built-in tap targets) for list items. Consider using `MaterialTapTargetSize.padded` in `ThemeData` to pad button targets globally.

### 5.10 Design for Edge Cases — Unbreakable Interfaces

Design for the worst case, not the average case. Components must handle long text, large numbers, missing data, and unusual combinations without breaking or hiding important information.

**Key rules:**
- Never design with unrealistically short placeholder text. Test with the longest realistic content.
- Prefer reflowing content (wrapping to multiple lines) over truncating. Only truncate when essential information remains visible.
- If you must truncate, crop in the middle rather than the end when items would otherwise look identical (e.g. "Document De…Chapter 3" is more differentiable than "Document De…" × 3 items)
- Use flexible widget sizing (`Flexible`, `Expanded`, `FittedBox`) rather than fixed sizes that clip content
- Test your UI with accessibility text scaling enabled — system font size increases can break fixed layouts

**Flutter note:** Use `Text` with `overflow: TextOverflow.ellipsis` only as a last resort, and pair it with `maxLines`. Prefer `Flexible(child: Text(...))` inside `Row` to allow wrapping. Test with `MediaQuery.textScaleFactor` at 1.5× and 2.0×.

### 5.11 Rule of Thirds for Photos

When displaying photos in your UI, centred compositions often feel rigid and static. The Rule of Thirds produces more dynamic, visually engaging images.

**How it works:** Mentally divide the photo into a 3×3 grid (3 columns, 3 rows). The four intersection points of those grid lines are the focal points. Position the main subject — a person's eyes, a key object, the horizon — at one of these four points rather than the centre.

**When this matters in app UI:**
- Hero images and banners: off-centre subjects feel more natural than centred ones
- Profile photos / avatars at large sizes: crop with the face at an upper focal point rather than perfectly centred
- Horizontal (landscape) photography: align the horizon with the upper or lower horizontal grid line rather than the midpoint
- Action shots: the off-centre framing amplifies the sense of motion already present in the image

**Flutter note:** Use `Image` with `fit: BoxFit.cover` and `alignment: Alignment(-0.3, -0.3)` (or similar offset values) to shift the focal point within the crop frame, rather than always defaulting to `Alignment.center`.

---

## 6. Components

### 6.1 Buttons

#### The 3 Button Weights

Define 3 button weights with distinct visual treatments to communicate the relative importance of actions. These styles are familiar, accessible, and have a clear visual hierarchy that does not rely on colour alone.

| Weight | Role | Visual Style |
|---|---|---|
| **Primary** | The single most important action on a screen | Filled rectangle with rounded corners, brand colour fill, white text |
| **Secondary** | Supporting or equal-importance actions | Outlined rectangle, no fill, brand colour text and border |
| **Tertiary** | Least important or destructive actions to de-emphasise | Transparent background, underlined brand colour text (text link style) |

**Secondary button pitfalls to avoid:**
- Don't use a solid fill of a second colour — it will conflict with the primary button visually
- Don't use a light grey fill or outline — it looks like a disabled state
- Don't make the secondary button visually similar to the primary — it collapses the hierarchy

**Tertiary button notes:**
- Always underline the text — colour alone is insufficient for colour-blind users to identify it as interactive
- Tertiary buttons are ideal for destructive actions you want to de-emphasise (e.g. "Remove" in a list)

**Flutter note:** Map to `ElevatedButton` (primary), `OutlinedButton` (secondary), `TextButton` (tertiary). Style all three globally via `ThemeData.elevatedButtonTheme`, `ThemeData.outlinedButtonTheme`, `ThemeData.textButtonTheme`. Never set button colours per-widget.

#### Button Accessibility Requirements (WCAG 2.1 AA)

| Element | Minimum contrast ratio |
|---|---|
| Button shape (fill or border) against page background | **3:1** |
| Button text against button background | **4.5:1** |
| Between two adjacent buttons of different weights | **3:1** |

Common failures: light grey secondary fills (below 3:1 against white), white text on mid-tone coloured fills, tertiary border outlines below 3:1.

**Hierarchy must not depend on colour alone.** A colour-blind user must be able to distinguish primary from secondary from tertiary using shape, weight, and style alone — not just by their hue.

#### Use a Single Primary Button Per Screen

The primary button signals "this is the most important action here." Multiple primary buttons on the same screen compete for attention and undermine the hierarchy — if everything is highlighted, nothing is.

**Rules:**
- Max 1 primary button per screen or card
- If actions have genuinely equal importance (e.g. "Report" / "Don't report"), use two secondary buttons — don't bias toward one
- In a list where the same action repeats per row (e.g. a "Follow" button for each user), use secondary — the repetition itself signals importance

#### Use Tertiary Buttons for Destructive Actions

Reduce the visual prominence of destructive actions by styling them as tertiary buttons. A red primary "Delete" button pulls far too much attention and competes with the intended primary action.

**Important:** don't colour the initial destructive action red — red draws attention, which is the opposite of what you want before a user has confirmed. Red is appropriate only in the confirmation dialog itself.

#### Try to Avoid Disabled Buttons

Disabled buttons are problematic: they offer no explanation for why they're unavailable, are invisible to keyboard users, and their low contrast makes them hard to see for users with low vision.

**Preferred alternatives:**

1. **Enable and validate on submit** — keep the button always enabled; show inline error messages when the user submits with incomplete fields. This is the most accessible and informative pattern.
2. **Remove unavailable actions** — hide the action entirely and provide a message explaining why it's unavailable.
3. **Lock icon on regular buttons** — replace disabled styling with a padlock icon on an otherwise normal button. Works especially well for paywalled premium features.

**If you must use disabled buttons,** mitigate the issues by:
- Adding a message directly below the button explaining why it's disabled and what the user needs to do
- Adding a tooltip that appears on hover/press explaining the same
- Ensuring the button remains keyboard-focusable so assistive technology users can trigger the tooltip

**Flutter note:** Avoid passing `null` to `onPressed` to disable. Instead keep the button enabled and perform validation in the handler. If you must disable, wrap in a `Tooltip` widget and use `GestureDetector` to intercept taps on the disabled state to show a `SnackBar` explaining why.

#### Button Alignment

**Desktop / tablet / forms:**
- Left-align buttons, ordered left-to-right from most important to least important
- Rationale: English is read F-pattern (left-to-right, downward); right-aligned buttons can be missed on large screens and by screen magnifier users; placing the most important button first reduces interaction cost

**Dialog boxes:**
- Left-align for consistency with forms (preferred for Windows-style apps)
- Right-align is acceptable for small dialogs if your platform convention favours it (e.g. macOS-style), as long as hierarchy is still clear — pick one and be consistent

**Multi-step forms:**
- Keep the primary "Next" button left-aligned (consistent with rest of the form)
- Place the "Back" button as a tertiary button at the top-left of the form — not at the bottom competing with "Next". This avoids accidental back-navigation after completing fields, and mirrors the back-button convention on mobile and browsers.

**Exception:** For single-field patterns (search bar, email subscribe), attaching the primary button to the right edge of the field is acceptable and conventional — it saves space and visually ties the action to the input.

**Mobile:**
- Stack buttons vertically, most important at top
- Make all buttons full-width — this supports both left-handed and right-handed one-handed use

**Flutter note:** Use `Column` with `CrossAxisAlignment.start` for left-aligned button groups. For full-width mobile buttons, use `SizedBox(width: double.infinity, child: ElevatedButton(...))`. For the back button in multi-step flows, use a `TextButton` with a leading arrow icon placed in the `AppBar` or above the form heading.

#### Ensure Button Text Describes the Action

Button labels must be meaningful when read out of context. Screen reader users often jump directly between buttons and links without reading surrounding text.

**Formula:** Verb + Noun → "Save post", "Delete article", "Start workout", "Update payment details"

**Never use:** "OK", "Submit", "Yes", "Click here" — these are meaningless out of context.

#### Button Target Size

- Minimum **48×48pt** for all interactive elements — aligns with the 8pt grid and slightly exceeds the WCAG 44pt recommendation
- Separate adjacent buttons by at least **8pt** to avoid mis-taps
- For small visual elements (close icons, filter chips), extend the tappable area beyond the visible bounds — the visual doesn't need to be 48pt, but the hit area must be
- Consider indicating the expanded tap area visually (e.g. a subtle background highlight) to reduce user uncertainty

**Flutter note:** Use `ElevatedButton` / `OutlinedButton` — they default to the minimum size defined in `ThemeData.buttonTheme.minWidth` and `minHeight`. Set these globally: `ButtonStyle(minimumSize: MaterialStateProperty.all(Size(48, 48)))`. For small icon buttons, wrap in `SizedBox(width: 48, height: 48, child: IconButton(...))`.

#### Balance Icon and Text Pairs

When combining icons with text labels (in buttons or nav bars), match their visual weight:

- Use icons and text with **similar stroke weight** — a thin-outline icon paired with bold text looks unbalanced
- Match the **icon size** to the text size — an oversized icon dominates and reduces text readability
- If the icon is inherently larger or heavier than the text, **reduce its contrast** (use `strokeWeak` colour rather than `textStrong`) to visually equalise the pair

**Flutter note:** In `NavigationBar` / `BottomNavigationBar`, use `selectedIconTheme` and `unselectedIconTheme` to control icon size and colour. For `ElevatedButton.icon`, set `iconSize` within `ButtonStyle` and use a complementary icon stroke weight from your icon library.

#### Add Friction to Destructive Actions

A destructive action is one that cannot be undone or causes permanent harm (deleting data, cancelling a subscription, removing access). Calibrate friction to the severity of the action:

| Friction level | Severity | Pattern |
|---|---|---|
| **Initial** | Any destructive action | Style as tertiary (low prominence), don't colour red |
| **Light** | Low severity (e.g. delete a draft) | Confirmation dialog: "Delete message? / Delete message / Cancel" |
| **Moderate** | Medium severity (e.g. delete published content) | Red confirmation dialog with warning icon and message explaining consequences |
| **Heavy** | High severity (e.g. delete account) | Red dialog + checkbox that must be checked before the button enables |
| **Undo** | Any severity | Offer an "Undo" action post-completion (e.g. in a `SnackBar`) |

**Flutter note:** For confirmation dialogs, use `showDialog` with `AlertDialog`. For undo patterns, use `ScaffoldMessenger.of(context).showSnackBar` with an action button. For heavy-friction checkboxes, use a `StatefulWidget` to gate the destructive button's `onPressed`.

---

### 6.2 Forms

#### Single Column Layout

Always stack form fields in a single column. Multi-column form layouts save space but create significant usability problems:

- **Multi-column layouts** require a zigzag eye path and leave users unsure of field order, which increases cognitive load and error rates
- **Screen magnifier users** see only a small portion of the screen at a time and will miss fields in a second column
- The interaction cost of a single-column form is lower — users move downward in a straight line with consistent momentum

**Exception:** Short, closely related fields (e.g. credit card expiry date and CVC) can be placed side by side within the single-column layout when their relationship is clear and they're small enough to remain contained within the column width.

If form length is a concern, break the form into multiple steps rather than adding columns.

**Flutter note:** Use `Column` with `crossAxisAlignment: CrossAxisAlignment.start` for all form fields. For the side-by-side exception, use a `Row` with `Expanded` children inside the column.

#### Stack Labels Above Inputs

Labels must always appear directly above their input field — never to the left and never inside the field as placeholder-only text.

**Why labels-to-the-left fails:**
- Creates a zigzag eye path from label to field, increasing interaction cost
- Labels may wrap on smaller screens if long, making them harder to read
- Right-aligning the label reduces the zigzag but creates a jagged left edge, making labels hard to scan

**Why floating/inline placeholder-only labels fail:**
- Placeholder text disappears on focus — users must remember what the field requires while typing
- Placeholder contrast is typically insufficient (WCAG requires 4.5:1 even for placeholder)
- Many screen readers do not read placeholder text as a label

**Correct pattern:** Stack the label text immediately above the field input with a small consistent gap (~4–8pt). Both label and input are visible simultaneously in a single eye focus.

**Flutter note:** Use `TextFormField` with `InputDecoration(labelText: 'Email')` — the `labelText` floats to the top on focus, but the label is always visible. Avoid using `hintText` as a substitute for `labelText`. Set `floatingLabelBehavior: FloatingLabelBehavior.always` if you want the label always visible above the field rather than animating.

#### Stack Checkboxes and Radio Buttons Vertically

Stack selection options vertically rather than arranging them in a horizontal row. Vertical stacking clearly separates each option, reduces the risk of selecting the wrong one, and is more accessible.

**Flutter note:** Use `RadioListTile` and `CheckboxListTile` for vertical option lists — they provide the correct touch targets and spacing automatically. For horizontal layouts (where you've made an intentional design decision), use `Row` with `Expanded` children, but only for 2–3 short options maximum.

#### Minimise the Number of Fields

Every additional field is a reason for a user to abandon the form. Only ask for information that is strictly essential to delivering the service.

**Checklist before adding a field:**
- Is this data actually needed at this stage?
- Can it be inferred or derived from other data?
- Can it be collected later, after the user has already committed?
- If removed, does the service still function?

More fields also means more development time, more validation logic, more error states to design, and more data to store and protect.

#### Mark Optional Fields

Assume all fields are required by default and only flag exceptions. Add "(optional)" to the label of any field that is not required — don't use asterisks on required fields (this convention is commonly misread or ignored).

Label format: `Mobile number (optional)`

Never use an asterisk legend ("* required fields") at the bottom of a form — users reach this explanation only after already being confused.

**Flutter note:** Append `" (optional)"` to the `labelText` string for optional `TextFormField` instances. Exclude these fields from `Form` validation logic.

---

## 7. Accessibility

### 7.1 Target Standard

Aim to meet **WCAG 2.1 Level AA** as a minimum. This is the internationally recognised accessibility standard and a legal requirement in many jurisdictions.

### 7.2 Contrast Requirements

- Normal text: **4.5:1** minimum contrast ratio against background
- Large text (18pt+ or 14pt+ bold): **3:1** minimum
- UI component borders (inputs, checkboxes): **3:1** minimum

### 7.3 Colour Blindness

- Never use colour as the sole indicator of state or meaning
- Underline text links so they're distinguishable from plain text for colour-blind users
- Use icons alongside colour cues for status indicators (error, warning, success)

### 7.4 Touch Targets

Minimum touch target size: **48×48pt** for any interactive element. This applies even if the visible element is smaller — use padding to expand the tappable area.

**Flutter note:** Wrap small tappable elements in a `GestureDetector` or `InkWell` with sufficient `padding`. The `MaterialTapTargetSize` enum in `ThemeData` controls button minimum sizes globally.

### 7.5 Screen Readers

- All interactive elements need descriptive semantic labels
- Icons without visible labels must have tooltip/semantic labels
- Headings, images, and buttons must be meaningfully labelled

**Flutter note:** Use `Semantics` widget to add accessible labels. Use `excludeSemantics` for purely decorative elements. Test with TalkBack (Android) and VoiceOver (iOS).

### 7.6 Screen Magnifiers

Screen magnifier users see only a small portion of the screen at a time. Design implications:
- Left-align buttons and important actions (screen magnifier users often read left-to-right linearly)
- Don't spread related actions far apart horizontally
- Ensure important content isn't hidden off-screen when zoomed

### 7.7 Accessibility Is Good UX

Accessible design benefits everyone. High contrast aids outdoor readability. Large touch targets help users in motion. Clear labels help non-native language users. Good accessibility = good usability.

---

## 8. Copywriting & Content

> *(Detailed copywriting guidelines to be populated from full Chapter 6 content)*

### 8.1 Core Principles

- **Be concise** — every word should earn its place
- **Use plain language** — write for your least technical user
- **Use sentence case** — not Title Case or ALL CAPS for UI text
- **Front-load text** — put the most important information first
- **Use the inverted pyramid** — lead with conclusions, follow with detail

### 8.2 Practical Rules

- Use numerals for numbers (use "3" not "three" in UI)
- Avoid full stops (periods) on short UI labels and button text
- Avoid abbreviations and acronyms unless universally known
- Keep text length consistent across similar elements (e.g. card descriptions)
- Text links must describe their destination — avoid "click here"
- Write clear, specific error messages that tell users what went wrong and how to fix it
- Use vocabulary consistently — don't alternate between "save" and "store"

---

## 9. Forms

> Synthesised from *Practical UI* (2nd ed.) Ch.8 — Forms (pp.338–369). Flutter notes added throughout.

### 9.1 Avoid Optional Fields — Use Opt-Ins Instead

Optional fields add complexity and cognitive load. Where possible, eliminate them entirely using progressive disclosure: ask the user to opt in first (e.g. a checkbox), then reveal the associated field only if they do.

**Example:** Instead of "Mobile number (optional)", show a checkbox labelled "Receive updates via text message". Only display the mobile number field once it is checked. Users who don't want updates never see the field.

**Flutter note:** Drive this with a `bool` state variable bound to a `Checkbox` or `Switch`. Use `AnimatedSize` or `Visibility(maintainState: false)` to reveal the conditional field smoothly.

### 9.2 Mark Both Required and Optional Fields

Always mark both required and optional fields — don't leave either ambiguous. This is especially important for accessibility (screen reader users, cognitive disabilities).

**Guidelines:**
- Required fields: mark with an asterisk `*` or the word `(required)`
- Optional fields: mark with the word `(optional)` in the label
- Include a legend at the top of the form: "Required fields are marked with an asterisk *"

**Why asterisk-only on required isn't enough on its own:** Instructions at the top of a form are often skipped as users scan. Marking both states inline (per-field) means the label alone is always self-explanatory.

**Why the "all required unless marked optional" approach fails:** This relies on users reading the instruction — which they often don't. Inline labelling is safer.

**Situations where you can skip marking required fields:**
- No optional fields exist anywhere in the product
- Short, familiar forms (login, single-field newsletter subscribe) — the requirement is implied
- One-question-per-screen flows where context is provided
- Usability testing confirms users don't need it

**Flutter note:** Append `" *"` or `" (required)"` directly to `labelText` in `InputDecoration`. Append `" (optional)"` for optional fields. Keep this consistent across the app via a helper or theming convention.

### 9.3 Avoid Red Asterisks

Don't colour asterisks red. Red is widely associated with errors and validation failures. A red asterisk on an empty, untouched field implies an error state before the user has done anything wrong.

Use the default text colour (or slightly muted) for asterisks.

### 9.4 Match Field Width to the Intended Input

Field width communicates to the user how much content is expected. A full-width field for a 4-character postcode implies a much longer answer than needed, increasing cognitive load.

**Rules:**
- Set field width to match the typical or maximum length of the expected input
- Don't uniformly set all fields to the same width for visual tidiness
- If input length varies, size for the most common or longest case

**Examples:**
- Postcode (AU): 4 characters — use a narrow field
- CVC: 3–4 characters — use a narrow field
- Card number: 16 digits — use a medium-width field
- Name on card: wider field appropriate

**Flutter note:** Use `SizedBox(width: ...)` or `constraints` on `TextFormField` to limit width, or use `Expanded` with `flex` ratios in a `Row` (e.g. expiry date + CVC side by side). Avoid setting `maxLength` alone — it doesn't change visual width.

### 9.5 Stick with Conventional Form Field Styles

Follow Jakob's Law: use the form field patterns people already know. Unconventional styles create ambiguity about what is interactive, what is filled, and how to interact.

**Common mistakes:**
- Underline-only fields (no visible border box) — look like plain text, not editable
- Labels inside the field at the same size as user input — field looks pre-filled
- Removing the circular affordance from radio buttons — behaviour becomes unclear
- Removing the square affordance from checkboxes — same problem

**If customising controls:** Retain the iconic visual elements (circle for radio, square for checkbox, bordered rectangle for text input) even if the size, colour, or animation changes. These visual cues are what users use to understand the control's behaviour.

**Flutter note:** Use `OutlineInputBorder` rather than `UnderlineInputBorder` for most contexts — the bordered box is more universally recognisable. If using Material 3, `filled: true` on `InputDecoration` can work well but must maintain sufficient border contrast. Never remove `CheckboxListTile`'s checkbox or `RadioListTile`'s radio indicator.

### 9.6 Display Hints Above Form Fields

Helper text (hints) that explains what a field requires should appear **above** the input, not below it. Hints placed below:
- Get covered by the on-screen keyboard on mobile
- Get covered by browser autofill dropdowns
- Appear after the user has already focused the field (too late to prevent errors)

**Placement order:** `Label → Hint → Input field`

**Visibility:** Don't hide hints in tooltips or info icons unless the information is truly supplementary. If the hint is needed to complete the field correctly, it must be visible at all times.

**Flutter note:** Use `InputDecoration(helperText: '...')` with caution — it appears below the field (standard Material behaviour). For above-field hints, add a `Text` widget manually between the label and the `TextFormField`, wrapped in a `Column`. Alternatively, include the hint as part of a custom label widget.

### 9.7 Don't Use Placeholder Text as a Label

Placeholder text (hint text inside the field) should never serve as the sole label for a field.

**Problems:**
- Disappears as soon as the user starts typing — they must remember what the field is for
- Can make the field look pre-filled, causing users to skip it
- Has insufficient contrast by default (WCAG requires 4.5:1 even for placeholder)
- Not reliably announced by screen readers as a label

**Form label tips:**
- Always display a short, descriptive label above the field
- Add a hint below the label if more context is needed
- Avoid placeholder text in most cases — use it only for genuinely supplementary format examples
- Avoid instructional verbs in labels: "Enter email" and "Type your email" are redundant — the field itself implies entry

**Acceptable placeholder use:** Single-field contexts like search bars — where the field is self-evident from context. Even then, ensure contrast ratio of the placeholder text is at least 4.5:1 and include an accessible `semanticsLabel`.

**Flutter note:** Use `labelText` (not `hintText` alone) in `InputDecoration`. Set `floatingLabelBehavior: FloatingLabelBehavior.always` to keep the label permanently visible above the field rather than using the animate-on-focus behaviour.

### 9.8 Keep Labels Close to Their Fields

Labels that are spaced far from their corresponding input create visual ambiguity — it becomes unclear which label belongs to which field. This increases eye movement and interaction cost.

**Rule:** The gap between a label and its input should be noticeably smaller than the gap between two fields. A common ratio: `4pt` label-to-field gap, `32pt` field-to-next-label gap.

**Benefit:** When label and field are visually grouped, the eye can treat them as a single unit, reducing the total number of fixation points when scanning the form.

**Flutter note:** In a `Column` of form fields, apply consistent spacing using `SizedBox(height: 4)` between label and field, and `SizedBox(height: 24)` (or similar) between each field group.

### 9.9 Prefer Radio Buttons Over Dropdowns (≤10 Options)

For selections with roughly 10 or fewer options, radio buttons are almost always preferable to dropdowns.

**Why dropdowns are problematic:**
- High interaction cost — require multiple taps (open → scroll → select → close)
- Can look pre-filled and get accidentally skipped
- Options are hidden — users can't scan or compare without opening

**Why radio buttons win:**
- Single tap interaction
- All options visible simultaneously for easy comparison
- Clearly communicate that exactly one option can be selected

**Exception:** Space is genuinely at a premium — a dropdown is acceptable in this case.

**Flutter note:** Use `RadioListTile<T>` for vertical radio lists. Give each option a `value` and bind to a `groupValue` state variable. For a custom look, build radio rows manually with `Radio<T>` but keep the circular visual indicator intact.

### 9.10 Use Autocomplete for Long Dropdowns

When a dropdown list is very long (e.g. country, occupation, city), replace it with an autocomplete / predictive search field. Users type characters and matching suggestions appear inline — far faster than scrolling a list of 200+ items.

**Design tips for autocomplete:**
- Best suited for fields where users know what they're looking for (country, product name, article)
- For unfamiliar long lists (occupation), break into two smaller dependent dropdowns (e.g. Industry → then Occupation)
- Limit visible suggestions to ~10 to avoid choice paralysis
- Bold the matched characters within each suggestion to help users differentiate options quickly

**Flutter note:** Use `Autocomplete<T>` widget (available in `flutter/material.dart`). Provide an `optionsBuilder` that filters the list based on the typed value. Use `optionsViewBuilder` for custom suggestion list styling. Bold matched text using `RichText` with `TextSpan`.

### 9.11 Use Steppers for Small Numeric Inputs

For selecting small integer values (quantity, number of guests, item count), a stepper (− / + buttons flanking a value) is significantly better than a dropdown.

**Interaction cost comparison (2 adults, 1 child, 1 infant):**
- Dropdowns: ~6 taps + 3 scroll interactions
- Steppers: 4 taps

**Stepper design tips:**
- Minimum button target: **48×48pt**
- Place buttons horizontally (− on left, + on right) — this gives more space between them, reducing accidental taps
- Use `−` and `+` symbols — not up/down arrows or chevrons, which are associated with dropdowns/accordions
- Disable the − button at the minimum value (e.g. 0 or 1) — don't allow negative values
- Steppers are not suitable for large number ranges (e.g. selecting a year) — use a text field or picker instead

**Flutter note:** Build a custom `StepperField` widget using a `Row` with two `IconButton` (or custom button) widgets and a `Text` displaying the current value. Wrap each button in a `SizedBox(width: 48, height: 48)` minimum. Manage the value with `useState` or a Riverpod `StateProvider<int>`.

### 9.12 Checkboxes vs Toggle Switches

Both are suitable for binary (on/off) options where the default is off. Choose between them based on when the action takes effect.

| Control | Use when |
|---|---|
| **Checkbox** | The user must press a submit button before the option takes effect |
| **Toggle switch** | The option takes immediate effect without a submit action |

**Checkbox guidelines:**
- Use for opt-in choices within a form that's submitted as a whole (e.g. "Receive news and special offers" on a registration form)
- Label must describe what happens when *checked*
- A single standalone checkbox is appropriate; for multiple related choices, use a checkbox group

**Toggle switch guidelines:**
- Use for settings that apply immediately (e.g. dark mode, annual/monthly billing toggle on a pricing page)
- Label must describe what happens when the switch is *on*
- Never use a toggle where a confirmation step is required — use a checkbox + submit instead

**Flutter note:** Use `Checkbox` / `CheckboxListTile` for form opt-ins. Use `Switch` / `SwitchListTile` for immediate-effect settings. Both use the same `value` / `onChanged` pattern. Set `activeColor` to your brand primary colour via `ThemeData`.

### 9.13 Use Positive Phrasing for Checkboxes

Checkbox labels should always describe what *will* happen when the box is checked — never what *won't* happen.

**Test:** Replace the checked checkbox with the word "yes". If the resulting sentence is contradictory or confusing, you're using negative phrasing.

- ❌ "Don't allow automatic updates" → "Yes, don't allow automatic updates" (contradictory)
- ✅ "Allow automatic updates" → "Yes, allow automatic updates" (clear)

### 9.14 Break Long Forms into Multiple Steps

Multi-step forms reduce cognitive load, improve completion rates, and reduce errors by letting users focus on one related group of questions at a time.

**Design tips:**
- Inform users upfront how many steps there are and what they'll need before starting
- Group 5–6 related questions per step, not 1 per step (avoid excessive granularity)
- Order from easiest to hardest — early wins motivate continued completion (Goal-Gradient Effect)
- Show a progress indicator — users feel more motivated as they approach the end
- Provide a review step before final submission — allow users to check and edit all answers
- After submission, show a clear success message and explain what happens next

**Flutter note:** Manage multi-step forms with a `PageView` (swipe-free, programmatically controlled) or `IndexedStack`. Store each step's form state separately. Use a custom `StepIndicator` widget (or `Stepper` widget) to show progress. Each step's `Form` should have its own `GlobalKey<FormState>` for independent validation.

### 9.15 Group Related Fields Under Headings

If a form can't be broken into steps, use section headings to visually group related fields. This makes a long form feel less overwhelming and easier to navigate.

**Example groupings for a registration form:**
- "Postal address" — street, suburb, state, postcode
- "Contact details" — email, mobile

**Flutter note:** Use `Text` with a `TextStyle` matching `titleMedium` / `titleSmall` from `ThemeData.textTheme`, followed by a `Divider` or simply extra top padding, to create a heading within a `Column`-based form. Consider using a `Card` per section for visual separation.

### 9.16 Ensure Form Field Borders Are High Contrast

Low-contrast field borders are one of the most frequent UI accessibility failures. Light grey borders on white backgrounds fail to meet the 3:1 contrast minimum required for UI components (WCAG 2.1 §1.4.11).

**Why it matters:** Users with low vision, those viewing on screens in bright conditions, or those on low-quality displays may be unable to perceive the field boundary — making the form unusable.

**Rule:** All interactive UI component borders (inputs, checkboxes, radio buttons, toggle switches, steppers, buttons) must have a contrast ratio of at least **3:1** against the adjacent background.

**Flutter note:** Use `OutlineInputBorder` with a `borderSide` colour that meets 3:1. Test with a contrast checker tool. In Material 3, the default border colours may not meet 3:1 on light backgrounds — override in `InputDecorationTheme`. Always check `enabledBorder`, `focusedBorder`, and `errorBorder` separately.

### 9.17 Form Validation Approaches

There are three validation strategies, ranging in complexity and user experience quality. Choose based on form complexity, development time, and the types of errors expected.

#### Approach 1 — Validate on Submit

Validate all fields when the user taps the submit button. The simplest implementation.

**Best for:** Simple forms with limited resources. Still a valid choice.

**On error, display:**
- A prominent error summary at the top of the form listing the number of errors and linking to each invalid field
- Inline error messages above each invalid field (not below)
- Red border + shaded background on invalid fields + an icon (never colour alone — for colour blindness)
- Do not disable the submit button pre-emptively

**Pros:** Simple to build; users can focus on completing the form without interruption.

**Cons:** Errors only appear after submit; users may face multiple errors at once and lose context.

**Flutter note:** Use `Form` + `GlobalKey<FormState>`. Call `_formKey.currentState!.validate()` in the submit handler. Errors appear inline via `validator` return strings in each `TextFormField`. For the error summary, conditionally render a banner widget at the top of the form.

#### Approach 2 — Validate on Field Blur (Inline / "On Blur")

Validate each field immediately after the user leaves it (moves focus away).

**Best for:** Forms with non-trivial field requirements that benefit from early feedback.

**Implementation notes:**
- Remove the error once the user corrects it (combine with approach 3 for this)
- Don't validate while the field is still focused

**Pros:** Immediate per-field feedback; users can fix errors while they still have context.

**Cons:** Can disrupt flow if users frequently switch between filling and correcting; harder to implement for groups of inputs (checkboxes).

**Flutter note:** Use `onEditingComplete` or `FocusNode` listeners. Attach a `FocusNode` to the field, listen for `hasFocus` changes, and trigger validation when focus is lost. Call `_fieldKey.currentState!.validate()` on blur.

#### Approach 3 — Validate Instantly as User Types

Validate after a short debounce delay once the user pauses typing.

**Best for:** Fields with specific format requirements (password strength, username availability).

**Implementation notes:**
- Introduce a debounce delay (~400–600ms) to avoid validating mid-word
- Particularly useful for showing live password strength indicators or username availability checks

**Pros:** Helps users work toward a valid answer in real time.

**Cons:** Premature error messages (if debounce is too short) can frustrate users. Most complex to implement.

**Flutter note:** Use `onChanged` on `TextFormField` with a `Timer` debounce. Cancel and restart the timer on each keystroke. On timer fire, run validation logic and call `setState` to update error state.

---

## 10. Mobile-Specific

> *(To be populated as mobile-focused books are added)*

### 10.1 Design for the Smallest Screen First

Begin design at the smallest target screen size. This forces prioritisation — only essential content and actions. Progressively enhance for larger screens.

### 10.2 Touch Target Sizes

Minimum **48×48pt** for all interactive elements. Be especially generous in areas of the screen that are harder to reach (bottom corners on large phones).

### 10.3 Primary CTA Button Placement

On mobile, the primary call-to-action button should be:
- At least **48pt tall** (minimum touch target)
- Positioned at the **bottom of the screen** for one-handed reachability
- Stretched to **full width** so both left- and right-handed users can reach it comfortably

**Flutter note:** Use a `SafeArea` + `Padding` wrapper at the bottom of the `Scaffold` body, or a `bottomNavigationBar` slot, to pin the CTA. Use `SizedBox(width: double.infinity)` on `ElevatedButton` to stretch it full width.

### 10.4 Icon Consistency

Choose a single icon style and stick to it throughout the app — either all outlined or all filled, never mixed. Mixing styles creates confusion: filled icons often signal "selected" or "active" state, so mixing filled and outlined icons in a neutral context misleads users.

Also ensure stroke weight is consistent across all icons in the set.

**Flutter note:** Use a single icon library (e.g. `Icons` from Material, or a custom icon font). If using `lucide_flutter` or similar, configure a consistent `strokeWidth` globally.



---

*Last updated: March 2026 — v1.9 (Added from Making Design Decisions: §1.10 decisioning chain, §1C full cognitive psychology reference (~30 models across 4 categories with Flutter notes), §1D Nielsen's 10 usability heuristics with Flutter checks, §2.8 reference design systems table. Practical UI Parts 1–10 remain complete.)*
