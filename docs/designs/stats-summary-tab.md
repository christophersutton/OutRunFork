# Stats / Summary Tab — v1 Design Note

**Status:** First-pass implementation.
**Author:** Design agent
**Date:** 2026-06-29

## Context & Scope

MoveFeet's only history surface is the Timeline list (`WorkoutTimelineView`). The ask was for a
dashboard that goes *beyond* the list — charts and aggregates for distance, time, counts and trends —
as a new app tab. This note records what was built for v1 and why, plus follow-ups.

Constraints honored:
- Reads only `WorkoutStore.shared` value snapshots (`[WorkoutSnapshot]`); no CoreStore access from SwiftUI.
- Works in **both** tab paths: iOS 26 native `TabView`/`Tab` and the legacy `CustomTabBar`.
- Reuses existing scaffolding (`StatTile`, `StatTileGrid`, `StatSectionView`, `WorkoutStatFormat`,
  `Workout.WorkoutType.sfSymbolName`) and app theme colors (`Color.orAccent/orForeground/...`).
- Swift Charts (already used by `WorkoutDetailCharts`) for the trend bar chart — no new dependency.

## What Shipped (v1)

New tab **"Stats"** (`chart.bar.fill`), placed between Timeline and the new-workout action. The screen is a
vertical scroll of four sections, scoped by a top **period picker**: **Week · Month · Year · All**.

1. **Totals** (period-windowed) — 2×2 tile grid:
   - Workouts (count), Distance (sum), Active Time (sum), Calories (sum; `--` when none recorded).
   - These four were chosen because three of them (count/distance/time) are always present in a snapshot
     (non-optional), so the grid never shows holes; calories is the one expected-but-optional metric.

2. **Trend** — Swift Charts bar chart with a **Distance / Active Time** toggle. Buckets adapt to the period
   so the x-axis stays readable instead of cramming raw days:
   - Week → 7 daily bars · Month → weekly bars · Year → 12 monthly bars · All → one bar per calendar year.
   - Distance bars are converted to the user's distance unit; time bars are in hours. Empty windows show an
     inline "No workouts this week" message instead of a blank rectangle.

3. **Type Mix** (period-windowed) — one row per workout type present, with the type's SF Symbol, count +
   distance, and a proportional accent bar (share of the most-travelled type). Surfaces the running /
   walking / hiking split this fork cares about without a pie chart.

4. **All-Time Records** — tappable tiles: Longest Distance, Longest Time, Biggest Climb, Fastest Average.
   Records are deliberately **all-time** (not period-scoped) so they read as achievements. Each tile opens
   the existing `WorkoutDetailView` via the same sheet pattern the timeline uses. Fastest Average ignores
   efforts under 1 km to avoid noise, and is formatted through `WorkoutStatFormat.speed`, so it respects the
   user's speed/pace unit preference.

### States
- **Loading** (`!store.isLoaded`): centered `ProgressView`.
- **No history at all**: `ContentUnavailableView("No Stats Yet", …)`.
- **Empty period**: totals show zeros, trend/type-mix show inline empty copy. Records remain (all-time).

## Architecture

- `StatsSummary` (`Views/SwiftUI/Stats/StatsSummary.swift`) — a **pure value-type** aggregation built from
  `[WorkoutSnapshot]` + a `StatsPeriod` + an injected `referenceDate` (deterministic/testable). All math in
  raw units (metres / seconds); unit conversion + formatting happen at the view layer. O(n) over the
  snapshot array (one element per workout).
- `StatsView` (`Views/SwiftUI/Stats/StatsView.swift`) — the screen + private chart / row / tile subviews.
  Rebuilds the summary in `body`; cheap because the snapshot array is small. Mirrors the timeline's
  unit-refresh-on-appear trick so distance strings update when the user changes units.

## Metrics Rationale (short)

Picked a coherent "history dashboard" over a kitchen-sink: **totals** answer "how much have I done", the
**trend** answers "am I trending up/down", **type mix** answers "what kind of training", and **records**
add a light achievement hook. One period control drives the first three so the screen reads as a single
lens, not four disconnected widgets.

## Follow-ups / Risks for Review

- **Localization:** new user-facing strings (section titles, period labels, record names) are English
  literals in code; only the tab title was added to the strings table (`Base.lproj`, key `TabBar.Stats`,
  inherited by all languages via LS fallback). Externalize the rest if this ships.
- **Legacy tab-bar balance:** the hand-built bar now holds Timeline + Stats on the left and Settings on the
  right, with the floating "+" over the centre gap — slightly asymmetric. Side padding is removed so the
  centered action has room on compact phones. A designer may still want to rebalance or add a bundled Stats
  glyph asset (currently an SF Symbol).
- **Default period** is Month (balances recency vs. likelihood of data). Reconsider if onboarding users land
  on an empty-ish Week.
- **Calendar bucketing** uses `Calendar.current` (week start, week-of-month). Cross-timezone history uses the
  absolute `startDate`; day grouping could drift from the timeline's stored `dayIdentifier` labels in edge
  cases. Acceptable for v1.
- **No unit tests** added for `StatsSummary`. It was designed to be testable (injected `referenceDate`); a
  follow-up test target addition would lock in bucketing/records behavior.
- **Pace vs. speed label:** "Fastest Average" avoids choosing between pace and speed while the value follows
  the user's speed unit preference.
- Future ideas: streaks / consistency (days active per week), week-over-week deltas on the totals tiles,
  goals, per-type filtering of the whole dashboard, tappable bars → that day/week's workouts.
