# OutRun SwiftUI Migration — Handoff (Phases 0–5 done; next: cleanup + Phase 6 shell flip)

> Pick this up in a fresh session. Read this top-to-bottom before touching code. It captures the
> architecture, conventions, tooling, and gotchas established across Phases 0–5. **Phases 0–5 are DONE
> (records below). The two remaining tasks — dead-code cleanup and the Phase 6 SwiftUI-`App` shell flip —
> are scoped, verified, and executable in the "Remaining work" section right below the TL;DR.**

## TL;DR

OutRun is a UIKit GPS workout tracker being migrated to modern Swift/SwiftUI **incrementally
(strangler-fig)** — leaf SwiftUI screens are hosted in the existing UIKit shell; the shell flips to a
SwiftUI `App` last. **Maps, the live-recording screen, the ORBanner system, and CoreStore stay UIKit/AS-IS**
(bridged). Toolchain: **Xcode 26.3, iOS 17 deployment floor, Swift 5 language mode** (explicit `@MainActor`,
not project-wide strict concurrency yet).

- Repo: `/Users/chrissutton/wavelength/OutRunFork`, branch `swiftui-rewrite`, baseline commit `45db21d "early phases"`.
- **Done & committed: Phases 0, 1, 2, Phase 3 core (Settings), ALL of Phase 4 (detail 4.1–4.3, EditWorkout 4.4, onboarding 4.5), and Phase 5 (timeline).** All build-green; verified on simulator.
- **The strangler-fig is essentially complete for data-browsing screens** — timeline, detail, settings, edit, onboarding, policy/changelog are all SwiftUI. What remains UIKit (by design): live recording (`NewWorkoutViewController`), maps, banners, CoreStore, and the app shell. **Next: leftovers/cleanup** (see Backlog) or the Phase-6 SwiftUI-`App` shell flip (out of scope unless revisited).

## ⭐ Remaining work (START HERE) — cleanup, then the Phase 6 App-shell flip

> Phases 0–5 are DONE (detailed records follow this section). Two things remain. Do **cleanup Phase A** first
> (quick, low-risk, fully verified), then the **Phase 6 shell flip**; cleanup **Phase B** falls out of the
> shell flip's Debug decision. Referrer analysis below was verified by grepping the whole repo (excluding Pods)
> on 2026-06-19 at branch `swiftui-rewrite` HEAD.

### 1. Dead-code cleanup (verified)

Each deletion must also remove the file's `PBXBuildFile`/`PBXFileReference`/`Sources` entries — use
`scripts/remove_files_from_target.rb` then `git rm` (see "Adding new files" for the gem invocation; the remove
script takes the same path). Build-green after each batch.

**Phase A — delete now (zero live referrers, confirmed):**
- `OutRun/Controllers/Settings/PolicyViewController.swift` — replaced by SwiftUI `PolicyView`.
- `OutRun/Controllers/General/ChangeLogViewController.swift` — replaced by SwiftUI `ChangelogView`.
- `OutRun/Controllers/Settings/ClearSettingsViewController.swift` — unreferenced `SettingsViewController` subclass.
- The dead **stats cluster** (one closed ring, no external callers): `OutRun/Models/Workout/Stats/WorkoutStats.swift`,
  `OutRun/Models/Workout/Stats/WorkoutStatsSeries.swift`, and the `queryWorkoutStats` **and** `querySectionedMetrics`
  methods in `OutRun/Models/Data/DataManager+Query.swift` (`queryWorkoutStats` has 0 callers; `querySectionedMetrics`'
  only caller is the dead `WorkoutStats`). Live stats come from `WorkoutDetailSnapshot` via `workoutDetailSnapshot(for:)`.
  - ⚠️ Most `WorkoutStats` grep hits are `LS["WorkoutStats.*"]` **localization keys** used by the live SwiftUI detail
    screen / timeline sort sheet — those are NOT the type; leave them. Confirm `WorkoutStatFormat`/`StatTileData`
    (used live by `WorkoutDetailView`) aren't orphaned before deleting.

**Phase B — BLOCKED behind one decision: port or drop `DebugController`.** The entire legacy "Setting DSL"
(~2,080 lines: `SettingsModel`/`SettingSection`/`SettingsViewController` + 11 `Setting*` cell subtypes + 2
protocols — a homegrown pre-SwiftUI way to declare UIKit settings tables as data) is kept alive by a **single
thread**: the 10-tap debug gesture in `TabBarController` opens `DebugController` (a `SettingsViewController`
subclass that still builds a `SettingsModel`). The live Settings tab is already SwiftUI (`SettingsView`/
`SettingsState`); `SettingsModel.main`/`.contributors` have **zero** callers. `DebugController` is the last user.

> **Recommendation: PORT `DebugController` to SwiftUI (don't drop it).** It's a hidden developer screen (reached
> by tapping the tab bar 10× while on Settings) showing read-only diagnostics — database disk size + entity row
> counts (`DataManager.diskSize`, `DataManager.fetchCount(of:)` for `Workout`/`WorkoutRouteDataSample`/
> `WorkoutEvent`/`WorkoutHeartRateDataSample`/`Event`), the map-image cache size + a **"Clear Cache"** button
> (`CustomImageCache.mapImageCache.diskSize` / `.clear { … }`), and `Config` flags (`isDebug`, `isRunOnSimulator`,
> `hasMobileProvision`, `hasSanboxReceipt`). The whole thing is ~60 lines of SwiftUI `List` rows + one button — a
> ~1-hour port that **keeps a useful support tool AND unblocks deleting ~2,080 lines of legacy UIKit** (vs. just
> dropping the tool). Access in the SwiftUI shell: a hidden `.onTapGesture(count: 10)` (e.g. on the Settings
> header) presenting the debug view as a `.sheet`. (Numbers it reads can be fetched in an `.task`.)

Once Debug is handled, delete as one unit: `DebugController.swift`, `SettingsViewController.swift`,
`SettingsModel.swift`, `SettingSection.swift`, all `OutRun/Models/Settings/Setting Models/*` subtypes,
`Protocols/Setting.swift` + `Protocols/KeyboardAvoidanceSetting.swift`, and the
`MeasurementUserPreference.setting(forTitle:)` method (its only caller is the dead `SettingsModel.main` — the type
itself stays, it's live via SwiftUI). Then prune orphaned `Settings.UnitPick.*` LS keys.

**Do NOT delete:** `NavigationController` (still used by the Debug push in `TabBarController`), `TabBarController`,
`DebugController` (live via the gesture), `HKImportListController` (the SwiftUI Settings "Import from Apple Health"
placeholder should bridge to it), and all live recording/map/banner UIKit (see Phase 6).

### 2. Phase 6 — flip the app shell to a SwiftUI `App`

**Current shell (what you're replacing):** single-window, **no scenes** (no `SceneDelegate`, no
`UIApplicationSceneManifest` in `Info.plist`). `@UIApplicationMain AppDelegate` (the only `@main` in the app) lazily
builds one `UIWindow`, runs `DataManager.setup` (Core Data migration → roots `ProgressViewController`), then roots
`TabBarController` if `UserPreferences.isSetUp` else `OnboardingLauncher.makeHostingController()`, runs
`checkPermissionStatus` (location→motion→health alerts), and presents `ChangelogView` when `lastVersion != Config.version`.
`TabBarController` (a `UITabBarController`) has 3 tabs — `UIHostingController(WorkoutTimelineView())`, a non-selectable
`PlaceholderController` (center slot), `UIHostingController(SettingsView())` — plus a **floating `+` button added as a
subview of `self.tabBar`** (tap → `NewWorkoutViewController`; long-press → `WorkoutTypeAlert` / manual `EditWorkoutForm`)
and a 10-tap debug gesture. Deployment is iOS 17 / Swift 5, iPhone-portrait only (`TARGETED_DEVICE_FAMILY = 1`).

**Target shape:**
```swift
@main struct OutRunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate   // keep DataManager.setup/migration/permission side-effects
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup { RootView().tint(.orAccent) }
        .onChange(of: scenePhase) { _, phase in
            // .background → WorkoutMapImageManager.suspendRenderProcess() + ApplicationStateObservation.stateChanged(to:.background)
            // .active     → resumeRenderProcess()                          + .foreground
        }
    }
}
```

**Re-homing checklist:**
- Remove `@UIApplicationMain`; keep the `AppDelegate` class via `@UIApplicationDelegateAdaptor`. **Gut its
  `didFinishLaunchingWithOptions` window-rooting** — move root selection, the permission re-check, and the changelog
  into `RootView`. Keep boot/migration as a `@MainActor @Observable` boot-state model (or a `.task` on `RootView`);
  the migration-progress UI (`ProgressViewController`) still needs a home.
- `RootView` gates on `UserPreferences.isSetUp` → `OnboardingView` vs the tab shell. **Onboarding completion: replace
  `OnboardingLauncher.finish()`'s `window.rootViewController = TabBarController()` swap with a SwiftUI state flip**
  (this is the one presenter that genuinely fights `WindowGroup`). Changelog → `.sheet`/`.fullScreenCover` gated on the
  `lastVersion` check; permission re-check → SwiftUI alerts with an "Open Settings" button (location→motion→health order).
- **Custom tab shell (the biggest fidelity risk):** SwiftUI `TabView` exposes no tab bar, so the in-bar floating `+`
  button + `bgrdView` can't be injected natively. Build a custom shell (`ZStack`: selected-tab content + a custom bottom
  bar with the two side tabs + a centered floating `+` button), or a `TabView` with the button overlaid via safe-area
  insets. The center "tab" becomes dead space the button occupies — drop `PlaceholderController`.
- **New `UIViewControllerRepresentable` bridges** (the app has none today — only `RouteMapView`, a `UIViewRepresentable`):
  - `NewWorkoutViewController` (live recording) in a `.fullScreenCover`; `.interactiveDismissDisabled(builder.status.isActiveStatus)`
    to replicate its `isModalInPresentation` + custom stop-confirm `close()`, and route its dismiss back to the cover binding.
  - `WorkoutMapViewController` (full-screen route map; reached from `WorkoutDetailView.openFullScreenMap`).
  - the share sheet, and `DebugController` (until ported).
  - `WorkoutDetailView.topMostViewController()` and `ORBaseBanner`'s `keyWindow` presenter walks keep working under a
    SwiftUI hosting root (a `UIHostingController` is still a `UIViewController`) — audit but they likely survive; only the
    root-swap above must become state. `keyWindow` is deprecated under multi-scene — prefer a connected-scene lookup.
- **Drop:** `TabBarController.lastCurrent` (no readers), the `TabBarSelectionObserver` mechanism (no conformers — the
  timeline already self-refreshes units via `.onAppear`), `PlaceholderController`.

**Load-bearing risks / decisions to confirm with the owner before starting:**
- **Scene lifecycle:** adopting `WindowGroup` implicitly opts into the UIScene lifecycle, so `AppDelegate`'s
  `applicationDidEnterBackground/WillEnterForeground` STOP firing — their work (map-render suspend/resume,
  `ApplicationStateObservation`) must move to `scenePhase`. **Verify `UIBackgroundModes=[location]` live tracking does
  not regress** (may need an explicit `SceneDelegate` for CoreLocation background delivery during recording).
- Vanilla `TabView` + overlaid button vs. a fully custom tab bar (determines whether `WorkoutTimelineView`/`SettingsView`
  keep their own `NavigationStack`s).
- `DebugController`: **recommended to port to SwiftUI** (it's ~60 lines — see cleanup Phase B for the rationale and
  the row-by-row contents); this same decision unblocks deleting the ~2,080-line Setting DSL.
- iPhone-portrait only — no `NavigationSplitView`/iPad work; `showDetailViewController`'s split-view-awareness is moot
  (it's always a full-screen modal on this target).
- **Verify on sim:** cold launch (set-up & not-set-up), onboarding→main transition, live recording start/stop, the
  background→foreground map-render suspend, and the changelog on a version bump.

---

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

## Phase 4.4 — EditWorkout → SwiftUI: DONE (commits `bd76fe7`, `293347b`)

`OutRun/Views/SwiftUI/EditWorkout/`: `EditWorkoutForm` (a single `Form` for **both** create & edit) +
`EditWorkoutState` (`@MainActor @Observable`, owns the save logic lifted out of the controller). Wired from the
detail-screen `Edit` action (`.sheet`, refreshes in place via `reloadToken`) and the tab-bar manual-add
long-press (`.create`, then shows the new workout's detail). **Deleted** `EditWorkoutController` + the dead
`EditWorkoutView`. Bugs fixed in the rewrite: positive duration seeding (legacy used the reversed
`endDate.distance(to:startDate)`); Save validated on appear; reactive Steps/Strokes label; grouping-free field
seeds (so an untouched 12,000-step value isn't wiped on save); type picker preserves a non-standard existing
type. Apple Health save errors are surfaced in an alert then the form finalizes (parity with the legacy).
Verified on sim: edit→save→in-place refresh; manual create→save→new detail (avg speed/energy computed).
- **Known low-pri nit (left as-is):** `isValid` uses `Date()` but only recomputes on a re-render, so a manual
  workout whose `start+duration` is ~now shows a stale-disabled Save until any interaction. Matches the legacy
  `validateData` (only ran on control changes). Real fix would be a timer tick; not worth it.

## Phase 4.5 — onboarding → SwiftUI: DONE (commit `1f50859`)

`OutRun/Views/SwiftUI/Onboarding/`: `OnboardingView` (welcome + 4 gated steps: Formalities, User Info, Apple
Health, Permissions, with page dots + contextual Next/Skip/Finish) + `OnboardingState` (`@MainActor
@Observable`, `finish()` ports `finishSetup()` verbatim — incl. the conditional unit-pref block — with the
imperial-altitude `.yards`→`.feet` fix) + `OnboardingStepViews` + `OnboardingLauncher` (hosts the flow and
swaps the window root to `TabBarController` on finish). Permission steps **reuse `PermissionManager.standard`**.
Weight kept canonically in kg, live-reconverted on the Metric/Imperial switch (driven by `.onChange`).
Wired into the `AppDelegate` launch gate (`!isSetUp`) and the `SettingsModel` "delete all data" reset path;
**deleted** `StartScreenViewController`, `SetupViewController`, and the whole `Views/Setup` custom-view stack.
Verified on sim: welcome + formalities render, gating/links/page-dots correct, builds/boots/runs. (Full
step-by-step click-through not exhausted — motion permission can't be granted on the simulator anyway; owner
will spot-check the simpler screens.)

## Phase 5 — timeline → SwiftUI: DONE (commit `82738af`)

Replaces the UIKit `WorkoutListViewController` timeline with a SwiftUI screen driven by the Phase-1
`WorkoutStore` (`@MainActor @Observable`, observes `DataManager.workoutMonitor`, republishes `[WorkoutSnapshot]`
on the main queue — the view holds only value snapshots). Files in `OutRun/Views/SwiftUI/Timeline/`:
- **`WorkoutTimelineView`** — `ScrollView` + `LazyVStack` (NOT `List`, for pixel control of the timeline
  decoration: a continuous accent line + a ring per card). Orange small-caps "Your Workouts" title, `Date ↓`
  sort button, `ContentUnavailableView` empty state. **Hosted directly in the tab bar** (own `NavigationStack`,
  like Settings — `TabBarController` no longer wraps it in a `NavigationController`). Row tap → `WorkoutDetailView`
  as a `.sheet` (matches the legacy modal). `.onAppear` re-renders rows on a distance-unit change (replacing the
  legacy `TabBarSelectionObserver.willGetSelected` reload).
- **`WorkoutTimelineRow`** — the card (`TYPE` / big distance / big duration via `CustomMeasurementFormatting`
  with the legacy "big number + small-caps unit" treatment) + the timeline gutter + `RouteThumbnail` (async,
  cached, off the workout uuid via the existing `WorkoutMapImageManager` — no live `Workout` needed). Race cards
  get the accent border.
- **`WorkoutTimelineSortSheet`** — sort (Date/Distance + Descending) + filter (type + race) as a SwiftUI sheet
  bound to **in-memory** state (NOT `UserPreferences`, matching legacy). Sort/filter applied in memory on the
  snapshot array (the store stays a pure read model — no CoreStore `refetch`).
- **Day headers de-duplicated** (one per day, while date-sorted) — an improvement over the legacy drawing a
  header above every card. Headers are suppressed under distance sort (where day grouping is incoherent and
  would risk duplicate `ForEach` ids).
- **Deleted** `WorkoutListViewController`, `WorkoutListSortViewController`, `WorkoutListCell`, `WorkoutListHeader`
  (all verified unreferenced). `DataManager.workoutMonitor` stays (now consumed by `WorkoutStore`).
- Verified on sim: empty state, card render (line/ring/header/big-number stats), live insert on create,
  row→detail sheet, create→detail. (Route thumbnail not visually exercised — manual workouts have no route — but
  it reuses the same `WorkoutMapImageManager` the detail-screen route map uses.)

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

## Smaller backlog / polish (independent of cleanup + Phase 6)

> Cleanup and the shell flip live in the "⭐ Remaining work" section near the top. These are the leftover smaller
> items, none blocking.

- **3 `SettingsView` action placeholders** (Phase 3 leftover): "Import from Apple Health" (bridge to UIKit
  `HKImportListController`), "Create Backup" / "Import Backup Data" (need a presenting `UIViewController` → wire via
  the `presentSwiftUI`/host bridge). In a SwiftUI shell these become `UIViewControllerRepresentable`/`.sheet` work.
- **Phase 5 follow-up:** the route-row thumbnail wasn't visually exercised on the sim (manual workouts have no
  route) — spot-check with a recorded GPS workout. `fetchBatchSize`/prefetch tuning was **not** needed (the legacy
  loaded all workouts eagerly too, and `WorkoutStore` maps the whole monitor to lightweight value snapshots);
  revisit only for users with thousands of workouts.
- **Pods `post_install`:** add a hook to normalize all pod sub-targets to the iOS 17 deployment target (they still
  show their own 9–13 minimums → harmless warnings).
- **Concurrency hardening (later):** flip project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + Approachable
  Concurrency, then per-target `SWIFT_STRICT_CONCURRENCY`; replace CombineExt relays with native Combine subjects.
- **Polish:** `MetricKit` / SF Symbols pass.

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
