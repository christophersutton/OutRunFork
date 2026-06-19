# OutRun SwiftUI Migration — Handoff (start of Phase 4)

> Pick this up in a fresh session. Read this top-to-bottom before touching code. It captures the
> architecture, conventions, tooling, and gotchas established in Phases 0–3 so Phase 4 lands cleanly.

## TL;DR

OutRun is a UIKit GPS workout tracker being migrated to modern Swift/SwiftUI **incrementally
(strangler-fig)** — leaf SwiftUI screens are hosted in the existing UIKit shell; the shell flips to a
SwiftUI `App` last. **Maps, the live-recording screen, the ORBanner system, and CoreStore stay UIKit/AS-IS**
(bridged). Toolchain: **Xcode 26.3, iOS 17 deployment floor, Swift 5 language mode** (explicit `@MainActor`,
not project-wide strict concurrency yet).

- Repo: `/Users/chrissutton/wavelength/OutRunFork`, branch `swiftui-rewrite`, baseline commit `45db21d "early phases"`.
- **Done & committed: Phases 0, 1, 2, Phase 3 core (Settings), and Phase 4 detail screen (4.1–4.3).** All build-green; verified on simulator.
- **Next: Phase 4 remainder** — EditWorkout SwiftUI port (4.4) + onboarding rewrite (4.5); then **Phase 5** (timeline → SwiftUI).

## Phase 4 — workout detail screen: DONE (commits `6b4d213`, `aa3a6b6`, `d8af6b6`, `ab068d6`)

Verified on simulator (timeline → detail; charts; full-screen map; actions menu; no crash). Adversarially
reviewed (3 skeptics → verify): the CoreStore queue-correctness claim **held**; one real off-main `@State`
bug was found and fixed (`@MainActor` on the view).

- **4.1 `WorkoutDetailSnapshot`** (`OutRun/Models/Data/Snapshots/WorkoutDetailSnapshot.swift`) — immutable value
  type: scalar stats + `[CLLocationCoordinate2D]` route + `[WorkoutChartPoint]` altitude/speed/HR series.
  Built **inside `dataStack.perform`** via raw `_x.value` (never the main-marshaling public accessors). Facade:
  `DataManager.workoutDetailSnapshot(for: UUID?) async -> WorkoutDetailSnapshot?` (single-resume continuation).
- **4.2 `WorkoutDetailView`** (`OutRun/Views/SwiftUI/WorkoutDetail/`: `WorkoutDetailView`, `…Support`, `…Charts`)
  replaces `WorkoutViewController`. Renders **real** tiles (old screen's tiles were never bound → showed `--`).
  Formats via `StatsHelper`/`CustomMeasurementFormatting`/`CustomDateFormatting` + `UserPreferences` units.
  Actions menu bridges to `ExportManager`/`EditWorkoutController`/`HealthStoreManager`/`DataManager.deleteObject`;
  route tap presents the (now full-bleed) UIKit `WorkoutMapViewController`. Entry points rewired: both
  `WorkoutViewController()` sites (`WorkoutListViewController.didSelectRowAt`, `EditWorkoutController.showWorkoutController`)
  now push `NavigationStack { WorkoutDetailView(workoutID:) }`. Presenter via `topMostViewController()` (keyWindow).
- **4.3 DGCharts → Swift Charts** — `WorkoutDetailCharts.swift` is now the **only** `import Charts` (Apple's).
  The `Charts` pod (DGCharts 4.1.0, module name `Charts` — collided with Apple's, so removal + adoption had to
  land together) is gone from the Podfile (`pod install` ran). Deleted the dead UIKit detail stack:
  `WorkoutViewController`, `{Distance,Speed,Time,Energy,Route,Text}StatsView`, `StatsView`, `WorkoutHeaderView`,
  `LabelledDiagramView`, `BigStatView` (each verified zero live referrers; `LabelledDataView`/`StatView`/
  `SmallStatView` STAY — used by the live recording screen). Stripped the always-empty diagram from
  `WorkoutMapViewController` (map is full-bleed now). Added `scripts/remove_files_from_target.rb`.
- **Bonus fixes** (latent bugs hidden by the never-rendered legacy charts): chart x-axis sign
  (`startDate.distance(to: timestamp)`), `topSpeed` (`max(by: >)` returned the min).
- **Known low-pri nit (left as-is):** under a *pace* speed unit, 0 m/s samples drop from the speed chart
  (infinite pace; `.monotone` interpolation bridges the gap). Reviewer deemed it a defensible design choice.

### Phase 4 remainder / next

- **4.4 EditWorkout** is currently **bridged to the existing UIKit `EditWorkoutController`** (functional). The
  SwiftUI `Form` port (per the plan below) is still TODO.
- **4.5 Onboarding** (`SetupViewController`) — not started.
- **`WorkoutStats`/`WorkoutStatsSeries`/`queryWorkoutStats` are now unused** (only the snapshot path remains).
  Safe to delete in a later cleanup; left in place for now.

## Strategy / scope decisions (locked with the product owner)

- **iOS 17 floor** (unlocks @Observable, NavigationStack, Swift Charts, SwiftUI Map). Confirmed.
- **Pragmatic end-state (Phases 0–5):** SwiftUI for all data-browsing screens; keep UIKit shell, maps,
  live-recording, banners. (Phase 6 SwiftUI-`App` shell flip is *out of scope* unless revisited.)
- **Don't fix bugs in code we're going to replace.** We only fixed regressions on code that *stays*
  (live recording stays UIKit → fixed; detail screen is being replaced → its old bugs were left/reverted
  and get fixed *properly* by the rewrite).
- **No piecemeal shipping** — there is no user value in intermediate states; optimize for the long-term result.
- **Verification cadence:** build-green after every change; **full simulator click-through only at phase gates**
  (simulator interaction is slow). Use subagents for mechanical bulk; adversarially verify load-bearing claims.

## What's done (Phases 0–3)

**Phase 0 — regression fixes (live recording stays UIKit, so these are permanent):**
- `NewWorkoutViewController` was gutted by the incomplete Rx→Combine migration (no subscriptions, empty action
  closure). Re-wired to Combine: live stat tiles, status→action-button/readiness, camera follow, route polyline,
  start/pause/stop via a `PassthroughSubject`, stop-and-save. Verified recording end-to-end on sim.
- `LiveStats` timer fix: `Timer.publish(every:1, on:.main, in:.common).autoconnect()` (was a never-connected
  `Timer.TimerPublisher` in `.default` mode → duration/calories were frozen).
- `Publisher.asBackgroundPublisher()` (`OutRun/Extensions/Combine/Publisher.swift`): replaced per-call
  `qos:.background` + `.subscribe(on:)` with a single shared `qos:.userInitiated` `receive(on:)` queue.
  **The old `.subscribe(on:)` broke `combineLatest`** of multiple background publishers (duration/speed/energy
  never emitted). If you touch reactive plumbing, remember this.
- `LabelledDataView.value` setter added (used by the live screen tiles).
- Localization: added `"Error" = "Error";` to `Base.lproj/Localizable.strings` — `LS["Error"]` was returning the
  literal `"NIL"` (the LS not-found sentinel) as the title of **7 error alerts app-wide**.
- Deleted orphaned `WorkoutBuilder+LiveUpdates.swift`.

**Phase 1 — foundations:**
- iOS 17 floor: Podfile + app target + UnitTests target all `17.0`; `pod install` ran. (Pods sub-targets still
  show their own minimums 9–13 → harmless warnings; **TODO cleanup:** add a Podfile `post_install` hook to set
  all pod targets to 17.)
- **Data-seam keystone** (the most important thing in the codebase now):
  - `OutRun/Models/Data/Snapshots/WorkoutSnapshot.swift` — immutable value type built from a `Workout`.
  - `OutRun/Models/Data/Store/WorkoutStore.swift` — `@MainActor @Observable` store observing the CoreStore
    `ListMonitor` and republishing `[WorkoutSnapshot]`. SwiftUI consumes **values, never live CoreStore objects.**

**Phase 2 — SwiftUI beachhead:**
- `OutRun/Extensions/SwiftUI/Color+Theme.swift` — `Color.orAccent/.orPrimary/.orSecondary/.orBackground/.orForeground`
  (bridge `Color(uiColor: .accentColor)` etc.; the `or` prefix avoids clashing with generated asset symbols).
- `OutRun/Extensions/SwiftUI/UIViewController+SwiftUI.swift` — `presentSwiftUI(_:)` / `pushSwiftUI(_:)` (wrap in
  `UIHostingController`; SwiftUI side dismisses via `@Environment(\.dismiss)`).
- `PolicyView`, `ChangelogView` (replace `PolicyViewController`/`ChangeLogViewController`; all call sites rewired).
- `RouteMapView` — `UIViewRepresentable` over `MKMapView`; Coordinator owns `rendererFor` (accentColor, lineWidth 8).
  **Use this for all route rendering. Do NOT use SwiftUI `Map`** — the route needs a custom `MKPolylineRenderer`.

**Phase 3 core — Settings → SwiftUI (verified on sim):**
- `OutRun/Views/SwiftUI/Settings/`: `SettingsState` (`@MainActor @Observable`, mirrors `UserPreferences`,
  loads in `init`, writes back in `didSet`), `SettingsView` (main, 7 sections, `NavigationStack`+`Form`),
  `UnitSelectionView` (generic, ×5 units), `StandardWorkoutTypeView`, `GPSAccuracyView`, `ContributorsView`.
- `TabBarController` Settings tab now hosts `UIHostingController(rootView: SettingsView())` directly.

## CRITICAL: the CoreStore threading rule (read before the detail screen)

CoreStore objects (`Workout`, route samples, etc.) are **thread-confined**. Reading a `Value.Required`/relationship
**off its designated queue traps** at runtime: `Value.Required.swift:124: Fatal error — accessed outside its
designated queue`. Two compounding facts in this codebase:
1. `Workout`'s scalar accessors use `threadSafeSyncReturn { ... }` which marshals to the **main** queue → they are
   only safe for **main-bound** objects (e.g. `ListMonitor` objects). A **transaction-bound** workout (from
   `dataStack.perform`) read through these accessors traps (it belongs to the transaction queue, not main).
2. `Workout`'s to-many relationship accessors (`routeData`, `pauses`, …) read raw `_x.value` on the *current* queue.

**Rules for Phase 4:**
- Build value snapshots (`WorkoutSnapshot` and a new detail snapshot) **on the object's own queue** — for
  `ListMonitor` objects that's main; for a fresh fetch use `DataManager.dataStack.fetchExisting(_:)` to get the
  **main-context** object, or read inside the `perform` transaction using raw `_x.value` accessors (not the
  main-marshaling public ones).
- **SwiftUI views must hold snapshots, never `Workout`/CoreStore objects.**
- This is *why* the old `WorkoutViewController` detail screen crashed once saving worked — `queryWorkoutStats`
  passed a transaction-bound workout to `WorkoutStats` (main-marshaling reads) and the lazy `*OverTime` chart
  series captured a dead transaction workout. The Phase-4 rewrite fixes this by snapshotting.

## Build / run / verify

```bash
cd /Users/chrissutton/wavelength/OutRunFork

# Build (the gate after every change)
xcodebuild -workspace OutRun.xcworkspace -scheme OutRun -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -configuration Debug build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# Install + launch on the (already-booted) iPhone 16 Pro sim
SIM=D6C217FB-9E68-4CA2-B9FC-A5202C44A667   # `xcrun simctl list devices booted` to reconfirm
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/OutRun.app" -maxdepth 6 -type d | head -1)
xcrun simctl install "$SIM" "$APP" && xcrun simctl launch "$SIM" de.tadris.OutRun   # bundle id: de.tadris.OutRun
xcrun simctl io "$SIM" screenshot /tmp/shot.png   # then Read the png

# Simulated GPS for live recording (Features ▸ Location ▸ Freeway Drive equivalent):
xcrun simctl location "$SIM" start --speed=3 --interval=1 <lat,lon> <lat,lon> ...
```

**Simulator notes / gotchas:**
- The booted sim runs iOS 18.x; deployment floor is 17 — fine.
- **`idb_gesture` (swipe) HANGS ~5 min** in this environment (it still scrolls, but blocks). Avoid; prefer
  tapping known coordinates from `idb_describe` (the a11y tree gives point coords; device is 402×874 pt @3x).
- `idb_find_element` often returns 0 matches for SwiftUI Form rows — use `idb_describe` `operation:all` and tap
  by `centerX/centerY`.
- **Core Motion is unavailable on the simulator** → the live-recording screen shows a (correct) "motion & fitness
  permission" alert; this is a sim limitation, not a bug. Recording still works.
- Crash diagnosis: `xcrun simctl launch --console-pty` captures the Swift fatal-error line; for a backtrace,
  `simctl launch --wait-for-debugger` + `xcrun lldb --batch -p <pid> -o continue -o "thread backtrace all"`.

## Adding new files (REQUIRED — project is objectVersion 51, explicit file refs)

New `.swift` files must be registered in `project.pbxproj`. Use the committed helper with **fastlane's** gem path
(homebrew Ruby lacks `rexml` that `xcodeproj` needs; fastlane's libexec bundles both):

```bash
cd /Users/chrissutton/wavelength/OutRunFork
FL=$(ls -d /opt/homebrew/Cellar/fastlane/*/libexec | head -1)
GEM_HOME="$FL" GEM_PATH="$FL" /opt/homebrew/opt/ruby/bin/ruby scripts/add_files_to_target.rb \
  OutRun.xcodeproj OutRun  OutRun/Path/To/NewFile.swift  [more files...]
```
(`scripts/add_files_to_target.rb` adds file refs to the OutRun target's source build phase + group. Idempotent.)

## Phase 4 plan (onboarding + workout detail)

> **Status:** steps 1–3 (detail screen + Swift Charts) are **DONE** — see the "Phase 4 — workout detail screen:
> DONE" section near the top. Steps 4 (EditWorkout SwiftUI port) and 5 (onboarding) remain. The original plan
> is preserved below for reference.

Highest value = the **workout detail screen** (proves the data seam, fixes the crash class, brings Swift Charts).

1. **Extend the data seam with a detail snapshot.** Add `WorkoutDetailSnapshot` (value type) carrying everything
   the detail screen shows: the scalar stats (distance/steps/ascend/descend/durations/speeds/energy as already
   computed by `WorkoutStats`), the **route coordinates** `[CLLocationCoordinate2D]` (for `RouteMapView`), and the
   **chart series** as plain `[(x: Double, y: Double)]` value arrays (NOT CoreStore samples) for altitude/speed
   (and heart rate if present). Build it inside one `dataStack.perform` (or off a `fetchExisting` main object),
   reading raw `_x.value` on the correct queue. Add an `async` `DataManager` facade method returning it.
   - Reference the old logic: `WorkoutStats` (`OutRun/Models/Workout/Stats/WorkoutStats.swift`) and
     `DataManager.querySectionedMetrics` / `asyncLocationCoordinatesQuery` (`DataManager+Query.swift`).
2. **`WorkoutDetailView` (SwiftUI)** replacing `WorkoutViewController`: ScrollView/VStack of stat tiles, the
   route via `RouteMapView(coordinates:)` (tap → push the full-screen UIKit `WorkoutMapViewController` via
   `pushSwiftUI`/bridge, or a SwiftUI wrapper), share/edit/delete actions. Open it from the timeline.
3. **DGCharts → Swift Charts.** Replace `LabelledDiagramView` (the only DGCharts user) with SwiftUI `Chart`
   (`LineMark(x:y:)`) fed by the snapshot's value series. After both chart sites are gone, **remove the `Charts`
   pod from the Podfile** and `pod install`.
4. **EditWorkout** (Phase 3 leftover, entry from detail): port `EditWorkoutController` to a SwiftUI `Form`
   (Type picker [running/walking/cycling only], Distance, Steps, Start Date, Duration wheel, Race toggle,
   Comment editor; Save validates `distance != nil && duration != 0 && start+duration <= now`; save path calls
   `DataManager.saveWorkout`/`updateWorkout` + optional HealthKit sync). Spec details in git history of this file's
   author or re-read `EditWorkoutController.swift`.
5. **Onboarding rewrite** (`SetupViewController`, 572 lines — hand-rolled `UIScrollView` pager): rewrite as
   SwiftUI `TabView(.page)` / step state machine reusing SwiftUI form rows + permission rows. Gate behind
   `UserPreferences.isSetUp`. Larger and more isolated — can come after the detail screen.

## Backlog (after Phase 4)

- **Phase 5** — timeline → SwiftUI `List`/`ForEach` backed by `WorkoutStore` (already built!). Rows render the
  route as a **static `MKMapSnapshotter` image** (`WorkoutMapImageManager`), never a live map. Add
  `fetchBatchSize`/prefetch tuning. Empty state = `ContentUnavailableView`. **WorkoutListSort** popover (Phase 3
  leftover) lands here as a SwiftUI sheet binding to the list view-model (in-memory, not UserPreferences).
- **Phase 3 leftovers:** EditWorkout (now in Phase 4), Debug screen (hidden dev, low priority), and 3 action
  placeholders left in `SettingsView` — "Import from Apple Health" (push UIKit `HKImportListController` via bridge),
  "Create Backup" / "Import Backup Data" (need a presenting `UIViewController` → wire via the bridge/host).
- **Cleanup:** delete now-dead UIKit files once nothing references them — `PolicyViewController`,
  `ChangeLogViewController`, `SettingsViewController` + the `SettingsModel`/`Setting*` DSL +
  `ClearSettingsViewController`/`DebugController` (after Debug is ported or dropped). Pods `post_install` deployment
  target normalization. Consider `MetricKit`/SF Symbols polish.
- **Concurrency hardening (later):** flip project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + Approachable
  Concurrency, then per-target `SWIFT_STRICT_CONCURRENCY`; replace CombineExt relays with native Combine subjects.

## Conventions cheat-sheet

- Theme: `Color.orAccent/.orPrimary/.orSecondary/.orBackground/.orForeground`.
- Localized strings: `LS["Key"]` (global). Verify keys exist in `Base.lproj/Localizable.strings`.
- Present/push SwiftUI from UIKit: `someVC.presentSwiftUI(MyView())` / `.pushSwiftUI(MyView())`.
- New `@Observable` view models: `@MainActor @Observable final class`, `@ObservationIgnored` for non-UI stored props.
- Route maps: `RouteMapView(coordinates:)`. Map snapshots for lists: `WorkoutMapImageManager`.
- iOS 17 SDK only — no iOS 18/26-only APIs (e.g. `Button(role: .close)` does NOT compile against the 17 floor).
- After adding files: run the `add_files_to_target.rb` helper, then build-green before moving on.

## Axiom skills (reference playbooks, read on disk — not registered as runnable skills)

`~/.claude/plugins/marketplaces/axiom-marketplace/axiom-codex/skills/` — relevant: `axiom-mapkit`,
`axiom-uikit-bridging`, `axiom-swiftui-architecture`, `axiom-swift-modern`, `axiom-audit-core-data`,
`axiom-combine-patterns`. They informed the decisions above; consult for detail.
