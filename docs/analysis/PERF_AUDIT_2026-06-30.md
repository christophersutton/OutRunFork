# Performance Audit — MoveFeet (OutRunFork)

Date: 2026-06-30
Branch: `dev` (worktree clean at start)
Method: Static (Axiom-style) source analysis. No Instruments / device run in this pass.
Scope: SwiftUI view-body anti-patterns + general Swift hot paths, focused on the reported
Settings→Timeline / delete → timeline-rebuild slowness.

> Relationship to the prior audit (`docs/AXIOM_AUDIT_FINDINGS.md`, 2026-06-21): that pass was on the
> pre-fork `OutRun/…` tree. Its closed items — cached/locked formatters, concrete-size map-image cache,
> single shared live-stats timer, map render logical suspension, async HealthKit/CoreStore queries,
> privacy manifest — were re-checked against the current `MoveFeet/…` tree and are **still current**. They
> are **not** re-reported here. This audit only adds findings that are live in the current tree.

---

## Executive summary

The earlier "tab switch hung ~1s" symptom was largely mitigated by making the timeline read-model a
kept-alive singleton (`WorkoutStore.shared`), so reselecting Timeline no longer rebuilds snapshots. The
**remaining** hot-path problem is real and matches the "delete was fast but timeline rebuild was slow"
observation:

- **`WorkoutSnapshot.init` fires a Core Data to-many relationship fault per workout, on the main actor,
  and `WorkoutStore.rebuild()` does this for the entire library on every database change.** The recent
  `hasRouteData = workout._routeData.count > 0` change removed a per-element array allocation but **did not**
  remove the underlying relationship fault — it is still O(workouts) SQL faults on the main thread per
  mutation. This is the top finding (HIGH).

Everything else is secondary: a non-incremental full rebuild (MEDIUM), stats aggregation recomputed in
`body` with multiple O(n) passes (LOW–MEDIUM), and a multi-pass detail-snapshot build (LOW, off-main).

---

## Verified hot-path findings

### FINDING 1 — Per-workout route relationship fault during synchronous main-actor timeline rebuild
- **Severity:** HIGH
- **Confidence:** High (mechanism confirmed in CoreStore source)
- **Where:**
  - `MoveFeet/Models/Data/Snapshots/WorkoutSnapshot.swift:58` — `self.hasRouteData = workout._routeData.count > 0`
  - `MoveFeet/Models/Data/Store/WorkoutStore.swift:46-57` — `rebuild()` (loops all monitor objects building snapshots)
  - `MoveFeet/Models/Data/Store/WorkoutStore.swift:36-39` + `:63-64` — observer rebuilds on every `listMonitorDidChange` / `listMonitorDidRefetch`
  - `MoveFeet/Models/Data/DataModels/Versions/OutRunV4.swift:130` — `_routeData = Relationship.ToManyOrdered<…>`
  - CoreStore proof: `Pods/CoreStore/Sources/Relationship.ToManyOrdered.swift:357` (`endIndex → nativeValue.count`) → `:257-275` (`nativeValue` getter does `object.getValue(forKvcKey:)`, i.e. a KVC relationship access)

- **Why it matters:**
  `_routeData` is a Core Data ordered to-many relationship. `RelationshipContainer.ToManyOrdered` is a
  `RandomAccessCollection`; its `.count` resolves to `nativeValue.count`, and `nativeValue` performs a KVC
  read of the `"routeData"` relationship. On a faulted `Workout` that **fires the relationship fault**: a
  SQL round-trip that realizes the ordered set of route-sample object references for that workout. There is
  no `SELECT COUNT(*)` short-circuit here.

  `WorkoutStore.rebuild()` runs on `@MainActor` and rebuilds **every** snapshot:
  - once on first load, and
  - on **every** `listMonitorDidChange` / `listMonitorDidRefetch` — i.e. every insert, update, **delete**,
    or import of any single workout.

  So deleting one workout cascades to a monitor change, which re-faults `_routeData` for **all remaining
  workouts** on the main thread. For a real library (hundreds of workouts, thousands of GPS points each)
  this is hundreds of synchronous SQL faults + ordered-set realizations on the main actor — the
  "CoreStore delete was fast, WorkoutStore/timeline rebuild was slow" symptom, precisely.

- **Why the recent fix didn't resolve it:**
  `workout.hasRouteData` (old) → `!self.routeData.isEmpty` → `_routeData.value` → `nativeValue.map { cs_fromRaw }`
  faulted the relationship **and** allocated a Swift array of wrapper objects for every route sample.
  `workout._routeData.count` (new) skips the `.map`/array allocation (a genuine win for large routes) but
  still calls `nativeValue` → **same fault**. The expensive part (the SQL fault, on the main actor, ×N) is
  unchanged.

- **Key leverage — the guard is barely needed:**
  The only consumer of `snapshot.hasRouteData` is `WorkoutTimelineRow.loadRouteImageIfNeeded()`
  (`MoveFeet/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift:139`), which uses it to avoid enqueuing a map
  request for routeless workouts. But `WorkoutMapImageManager` **already** determines route presence
  asynchronously off the main thread: `execute(…)` → `executeNextInQueue()` →
  `DataManager.asyncLocationCoordinatesQuery(…)` runs inside `dataStack.perform(asynchronous:)` and returns
  `.noRouteData` (→ `completion(false, nil)`) when there is no route
  (`MoveFeet/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift:131-141`;
  `MoveFeet/Models/Data/DataManager+Query.swift` `asyncLocationCoordinatesQuery`). So today the app pays a
  **guaranteed main-thread fault for every workout** to avoid a cheap **off-main** no-op enqueue for only
  the routeless ones — a bad trade.

- **Fix direction (pick one; ordered easiest → most durable):**
  1. **Drop `hasRouteData` from `WorkoutSnapshot`** and remove the row guard. Let
     `WorkoutTimelineRow` always call `WorkoutMapImageManager.execute`; routeless workouts resolve to
     `(false, nil)` off-main and simply render no thumbnail. Removes **all** main-actor route faults.
     Cost: routeless workouts each enqueue one cheap async coordinate query (off-main). For a mostly-routed
     library this is negligible; if undesired, combine with (2).
  2. **One batched presence query.** During an async snapshot build, run a single
     `queryAttributes`/grouped fetch over `WorkoutRouteDataSample` keyed by `_workout` to get the
     `Set<UUID>` of workouts that have ≥1 route sample, then stamp `hasRouteData` from that set. One query
     instead of N faults. (Requires moving snapshot construction off the synchronous main path — see
     Finding 2.)
  3. **Denormalize** a stored `_hasRouteData: Bool` (or `_routeSampleCount: Int`) on `Workout`, written in
     `saveWorkouts`/`updateWorkout` (`MoveFeet/Models/Data/DataManager.swift`). Requires a V5 schema +
     migration, but makes the timeline read free forever and survives future call sites.

- **Suggested measurement (validate before/after):**
  - Wrap `WorkoutStore.rebuild()` with `os_signpost` (or `OSSignposter`) logging `objects.count` and elapsed
    ms. Reproduce: open Timeline with a seeded library of ~200 routed workouts, then delete one. Expect main
    -thread `rebuild()` to drop from hundreds of ms / ~1s to <5 ms.
  - Instruments → **SwiftUI** + **Time Profiler** (Release): trigger a delete; in the main-thread stack look
    for `getValue(forKvcKey:)` / `_PFFault` / `-[NSManagedObject willAccessValueForKey:]` frames under
    `WorkoutStore.rebuild` → `WorkoutSnapshot.init`. They should disappear after the fix.

---

### FINDING 2 — Whole-array snapshot rebuild on every monitor change (no incremental diff)
- **Severity:** MEDIUM
- **Confidence:** High
- **Where:** `MoveFeet/Models/Data/Store/WorkoutStore.swift:46-57` (`rebuild()`), driven by `:36-39` / `:63-64`

- **Why it matters:**
  Independent of Finding 1, `rebuild()` reconstructs the **entire** `[WorkoutSnapshot]` (17 scalar `.value`
  reads × N workouts) and reassigns `workouts` on every single-row insert/update/delete. The scalar reads
  themselves are cheap on the monitor queue, but: (a) it is O(N) work for an O(1) change, and (b) replacing
  the whole `@Observable` array invalidates the full `ForEach` identity set in `WorkoutTimelineView`, doing
  more SwiftUI diffing than necessary. `CoreStore.ListMonitor` already provides granular
  `didInsertObject` / `didDeleteObject` / `didUpdateObject` / `didMoveObject(_:indexPath:)` callbacks.

- **Fix direction:** Maintain `workouts` incrementally from the granular `ListObserver` callbacks (insert /
  remove / replace / move at index), instead of a single coarse "rebuild everything" closure. At minimum,
  sequence this **after** Finding 1 so the per-change cost is already cheap; incremental updates then become
  a polish rather than a hang fix.

- **Suggested measurement:** Signpost `rebuild()` invocation count + duration during a multi-workout
  HealthKit import; confirm it runs once per changed object and scales with total library size, not change
  size.

---

### FINDING 3 — `StatsSummary` recomputed in `body` with multiple O(n) passes
- **Severity:** LOW–MEDIUM (small N today; scales with workout history)
- **Confidence:** Medium
- **Where:**
  - `MoveFeet/Views/SwiftUI/Stats/StatsView.swift:62` — `let summary = StatsSummary.make(from: store.workouts, period: period, referenceDate: Date())` inside `content` (a `body`-evaluated property)
  - `MoveFeet/Views/SwiftUI/Stats/StatsSummary.swift:163-189` (`make`), `:233-249` (`yearMonthBuckets` = 12× full `windowed.filter`), `:252-261` (`allYearBuckets`), `:289-340` (`buildRecords` = 4× `filter`+`max` over **all** snapshots), `:266-278` (`buildTypeBreakdown`)

- **Why it matters:**
  `StatsSummary.make` runs on **every** `body` evaluation of `StatsView` — not just on period/metric
  changes, but on any re-render (e.g. presenting the record/detail sheet via `selectedWorkout`, parent
  invalidation, the unit-refresh token). Each call does many separate passes: `yearMonthBuckets` filters
  the windowed array 12 times; `.all` records do 4 independent `filter`+`max` scans over the full history;
  plus totals reduces and a `Dictionary(grouping:)`. The in-file comment ("rebuilt in body … stays cheap")
  holds for small libraries, but it is recomputed on unrelated re-renders and uses N passes where one
  grouping pass would do.

- **Fix direction:**
  - Memoize the summary keyed by `(period, store.workouts.count or identity, distanceUnit)` — or compute it
    in a small `@Observable` stats model updated when `store.workouts` changes — so opening a sheet doesn't
    recompute aggregates.
  - Collapse the per-bucket `filter` scans into a single grouping pass (bucket workouts by day/week/month/
    year in one traversal), and gather all four records in one pass.

- **Suggested measurement:** Instruments → **SwiftUI**, *Long View Body Updates* lane on `StatsView` while
  toggling period/metric and opening a record tile; check `StatsSummary.make` self-time in Time Profiler on
  a large seeded history.

---

### FINDING 4 — `WorkoutDetailSnapshot` makes 4–5 passes over route samples and double-reads `_speed`
- **Severity:** LOW (per-open, runs off-main in a transaction — not a hang)
- **Confidence:** Medium
- **Where:** `MoveFeet/Models/Data/Snapshots/WorkoutDetailSnapshot.swift:104-138`
  - `routeCoordinates` (compactMap), `altitudeSeries` (compactMap), `speedSeries` (compactMap),
    `validSpeeds`/`topSpeed` (`map` + `filter` + `max`), `heartRateSeries` (map)
  - `_speed.value` is read twice (`:124` speedSeries and `:136` validSpeeds); `_timestamp.value` read 3×

- **Why it matters:** Built once per detail open inside `dataStack.perform` (correctly off the main actor),
  so it is **not** a UI hang. But for long routes (thousands of faulted samples) it walks the sample array
  ~4× and re-reads faulted KVC properties multiple times, adding avoidable latency to detail-screen
  presentation.

- **Fix direction:** Single loop over `routeSamples` accumulating coordinates + altitude/speed series +
  running max speed; single loop over `heartRateSamples`. Read each `_x.value` once.

- **Suggested measurement:** Signpost `DataManager.workoutDetailSnapshot(for:)` build duration for a workout
  with ~5k route samples before/after; expect a meaningful drop in time-to-detail for long routes.

---

## Speculative / checked-and-cleared (not action items)

- **`MainTabView` legacy `content` switch** (`MoveFeet/Views/SwiftUI/Shell/MainTabView.swift:101-107`):
  rebuilds the selected tab's view on each switch for < iOS 26, but `WorkoutStore.shared` is a kept-alive
  singleton, so no snapshot rebuild occurs on tab switch. Not a hot path. (iOS 26 native `TabView` keeps all
  tabs instantiated — also fine.)
- **`NumberFormatter()` in `EditWorkoutState.editableString` (`:114`) and `OnboardingState.editableString`
  (`:118`)**: one-shot, cold form-seed paths (not in `body`, not in a loop). Negligible; intentionally
  grouping-free for round-trip correctness. No change recommended.
- **`UIScreen.main.bounds` in `ORBaseBanner` (`:275-276`)**: legacy banner sizing, cold path, not the
  timeline/map sizing the prior audit fixed. Not a perf concern.
- **`CustomMeasurementFormatting` / `CustomDateFormatting`**: still use shared, lock-guarded cached
  formatters in the current tree — no per-call allocation in the timeline row formatting path. Confirms the
  prior audit's fix is intact.

---

## Prioritized quick wins

1. **Remove the main-actor route fault (Finding 1).** Smallest viable change: drop `hasRouteData` from
   `WorkoutSnapshot` + the row guard, relying on the already-async map route query. Eliminates the
   delete/rebuild hang. *(HIGH impact, low effort.)*
2. **Single-pass `WorkoutDetailSnapshot` build (Finding 4).** Local, off-main, no API change. *(Low effort.)*
3. **Memoize `StatsSummary` so it isn't recomputed on sheet presentation / unrelated re-renders
   (Finding 3).** *(Low effort, low risk.)*

## Larger investigations

1. **Incremental `WorkoutStore` updates from granular `ListMonitor` callbacks (Finding 2)** — replace the
   coarse full rebuild with insert/delete/update/move handling.
2. **Decide the durable route-presence strategy (Finding 1, option 2 vs 3):** batched presence query vs a
   denormalized `_hasRouteData` column with a V5 migration. The denormalized column is the most robust and
   also lets the timeline avoid touching route data entirely; weigh against migration cost/coverage (the
   prior audit already flags thin historical-migration test coverage).
3. **Whole-library aggregation strategy for Stats** as history grows (single-pass bucketing; possibly a
   cached stats model shared with any future widgets).

## Suggested validation harness (applies to Findings 1–4)

- Add `OSSignposter` intervals around `WorkoutStore.rebuild()`, `StatsSummary.make`, and
  `DataManager.workoutDetailSnapshot(for:)`, logging input counts.
- Seed a Release build with a large library (≈200–500 workouts, mixed routed/routeless, multi-thousand-point
  routes) and profile with the **SwiftUI** + **Time Profiler** + **Hangs/Hitches** template:
  - Delete a workout → watch the main thread for KVC relationship-fault frames under `rebuild()` (Finding 1).
  - Toggle Stats period/metric and open a record → watch *Long View Body Updates* on `StatsView` (Finding 3).
  - Open a long-route workout detail → measure snapshot build time (Finding 4).
- Target: main-thread `rebuild()` < 5 ms regardless of library size; no relationship-fault frames on the
  main thread during a delete.

---

*No production code was modified in this audit. Nothing committed or pushed.*
