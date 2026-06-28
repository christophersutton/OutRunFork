# Design: Live Activity for Active Workouts

**Status:** Exploration / design only — not implemented
**Author:** Design pass (Claude)
**Date:** 2026-06-28
**Roadmap item:** *Live Activity for active workouts — add a Live Activity view (Lock Screen / Dynamic Island) showing the in-progress workout.*

> Scope note: this targets **iOS 17–18-era ActivityKit only**. No iOS 26 / Liquid Glass adoption (`glassEffect`, accented rendering tuning, etc.) is in scope here — those are deferred.

---

## 1. Context & Scope

Add a Live Activity that surfaces the in-progress workout on the **Lock Screen** and **Dynamic Island** while a recording is active, mirroring the live readouts already shown in `NewWorkoutViewController` (duration, distance, pace/speed, calories) and reflecting pause/resume/stop state.

**v1 goal:** a *display-only* Live Activity (tap to open the app), driven entirely by local `Activity.update()` calls from the running app. **Interactive controls** (pause/stop buttons in the Dynamic Island) are a deferred phase because they require routing App Intents back into the live `WorkoutBuilder` (see §9).

### Current architecture (relevant facts)

| Area | Finding |
|---|---|
| Deployment target | **iOS 17.0** (`project.pbxproj`, `Podfile`) → ActivityKit (16.1+) and `LiveActivityIntent` (17+) both available. |
| Bundle ID / Team | `com.wcc.movefeet`, team `W67CF9C739`, **Automatic** signing, Swift 5.0. |
| Recording UI | UIKit: `NewWorkoutViewController` (`MoveFeet/Controllers/Workout/`) owns the `WorkoutBuilder` + components incl. `LiveStats`. |
| State source of truth | `WorkoutBuilder` (`Models/Workout/WorkoutBuilder/`) publishes via CombineExt relays an `Output`: `status, workoutType, startDate, endDate, distance (m), steps, pauses ([TempWorkoutPause]), …`. |
| Status enum | `.waiting, .ready, .recording, .paused, .autoPaused` (`WorkoutBuilder+Status.swift`). `isActiveStatus` = recording/paused/autoPaused; `isPausedStatus` = paused/autoPaused. |
| Live readouts | `LiveStats` already computes **formatted strings** for distance/duration/speed/pace/burnedEnergy on a shared 1 s timer. Raw values live on the builder (`distance: Double` meters, `pauses` with durations). |
| Background execution | `UIBackgroundModes = [location]` already set. App stays alive during recording → **local Activity updates work, no push server needed**. |
| Completion flow | On `.ready`, builder snapshots → `WorkoutCompletionActionHandler` shows `WorkoutCompletionBanner` (save / continue / discard). `continueWorkout(from:)` resumes recording. |
| Existing widget infra | **None.** Entitlements = HealthKit only. No App Groups, no `NSSupportsLiveActivities`, no extension target, no `ActivityAttributes`. Greenfield. |

---

## 2. Recommended UX

### Lock Screen / banner (`ActivityConfiguration` content)
Compact card mirroring the in-app stat tiles:

```
┌─────────────────────────────────────────────┐
│  🏃  Running                      ● RECORDING │   ← type + status pill (color from Status.color)
│                                               │
│  12:34            3.21 km                     │   ← duration (auto-ticking)   distance
│  5:42 /km         286 kcal                    │   ← pace/speed (user pref)    calories
└─────────────────────────────────────────────┘
```

- **Duration** uses a self-updating `Text(timerInterval:pauseTime:)` — see §5.1 (the system ticks it; we do *not* push every second).
- **Status pill**: "RECORDING" (red), "PAUSED" / "AUTO-PAUSED" (gray) — reuse `Status.title` / `Status.color` semantics.
- Honor the user's speed-vs-pace preference (`UserPreferences.speedMeasurementType.isPaceUnit`), matching `NewWorkoutViewController.speedIndication`.
- Whole card is a `widgetURL(...)` deep link back into the active-workout screen.

### Dynamic Island

**Compact** (most common, recording in background):
- `compactLeading`: workout-type SF Symbol (tinted by status).
- `compactTrailing`: auto-ticking duration `Text(timerInterval:)` (monospaced digits, fixed width).

**Minimal** (multiple activities): status-tinted workout glyph only.

**Expanded** (long-press):
- `leading`: type glyph + localized type name.
- `trailing`: duration (large, monospaced).
- `center`: status pill.
- `bottom`: 3-up stat row — distance · pace/speed · calories. (Pause/Stop buttons added here in the deferred interactive phase.)

**Design hygiene:** concentric rounded shapes, monospaced-digit duration to prevent width jitter, spring/elastic transitions (per ActivityKit HIG). Keep `ContentState` well under the **4 KB** limit (trivial — only scalars/short strings).

---

## 3. ActivityKit Data Model

One shared file, compiled into **both** the app and the widget extension target.

```swift
import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Self-ticking timer support (§5.1)
        var timerStart: Date          // effective start = now - activeElapsed (advances across pauses)
        var pauseTime: Date?          // non-nil while paused → freezes the Text(timerInterval:) counter
        var isPaused: Bool

        // Pre-formatted, localized, unit-aware readouts (built app-side via StatsHelper)
        var distanceText: String
        var paceOrSpeedText: String
        var caloriesText: String

        // For status pill / glyph
        var statusTitle: String       // e.g. Status.title
    }

    // Static — set once at start
    var workoutTypeRawValue: Int      // Workout.WorkoutType.rawValue → reconstruct glyph/name in widget
    var usesPace: Bool                // so the widget can label the pace/speed tile correctly
}
```

**Design choices**
- **Pre-format strings app-side** using the existing `StatsHelper` / `LiveStats` formatters. The extension stays free of the app's formatting stack and pods (§7). The only logic in the widget is glyph/label selection.
- **Numbers as text, duration as timer.** Distance/pace/calories are pushed as already-formatted strings on a throttled cadence; duration is *not* a string — it's a system-driven `Text(timerInterval:)` so it stays live between updates.
- `workoutTypeRawValue` is an `Int` so the widget can map to an SF Symbol without importing the model layer. (If `Workout.WorkoutType` → glyph mapping isn't trivially shareable, duplicate a small switch in the extension.)

---

## 4. New Component: `WorkoutLiveActivityController` (app side)

A thin coordinator in the **main app** that owns the `Activity<WorkoutActivityAttributes>` handle and bridges builder output → ActivityKit.

Responsibilities:
- Subscribe to `WorkoutBuilder.Output` (status, workoutType, startDate, distance, pauses) — same publishers `LiveStats` already consumes. Easiest integration: instantiate it alongside the other components in `NewWorkoutViewController.init()` (peer to `liveStats`), or have it observe `LiveStats`'s already-formatted string publishers directly to avoid duplicating formatting.
- Translate state transitions into `start / update / end` (§5).
- Throttle updates (e.g. `.throttle(for: .seconds(2), latest: true)` on distance/calories) to respect ActivityKit's background update budget.
- Guard on `ActivityAuthorizationInfo().areActivitiesEnabled`.

Keeping it a `WorkoutBuilderComponent`-style peer means it lives and dies with the recording session and needs no changes to the builder's core.

---

## 5. Update Lifecycle (tied to start / pause / resume / stop / save / discard)

| Builder transition | Live Activity action |
|---|---|
| → `.recording` (first time, `startDate` set) | `Activity.request(...)` with `pushType: nil`. Initialize `timerStart = startDate`, `isPaused = false`. |
| → `.paused` / `.autoPaused` | `activity.update(...)` with `isPaused = true`, `pauseTime = now`, `statusTitle` updated. Freezes the counter. |
| → `.recording` (resume from pause) | `activity.update(...)` with `isPaused = false`, `pauseTime = nil`, and **recompute `timerStart`** to exclude the just-ended pause (so elapsed excludes paused time). |
| distance/calories/pace tick (while recording) | throttled `activity.update(...)` with new formatted strings. No `staleDate` needed for a continuously-updated local activity, or set a short one as a safety net. |
| → `.ready` (Stop pressed) | Recording ends → builder snapshots → completion banner appears. **Do not end the activity yet** (workout may be *continued*). Mark activity "ended-pending"; or `update` to a paused/"finished" visual. Resolve on the completion action below. |
| Completion: **Save** | `activity.end(finalContent, dismissalPolicy: .immediate)` (or `.after(short)` to briefly show a summary). |
| Completion: **Discard** | `activity.end(..., dismissalPolicy: .immediate)`. |
| Completion: **Continue** (`continueWorkout`) | If the activity wasn't ended, `activity.update(...)` back to recording; if it was, `Activity.request(...)` a fresh one. Recommend **keeping the activity alive** through the banner so Continue just resumes. |
| App force-quit mid-workout | Activity persists on Lock Screen showing last state; system marks it stale. On relaunch, reconcile via `Activity<…>.activities` (end orphans or rebind). |

### 5.1 The duration trick (critical)

ActivityKit cannot reliably push once per second (budget + throttling), so **never** push the duration as a string. Instead:

```swift
// Recording:
Text(timerInterval: state.timerStart...Date.distantFuture,
     pauseTime: state.pauseTime,            // nil while running
     countsDown: false)
    .monospacedDigit()
```

- `timerStart` is an **effective start** = `realStartDate + totalPausedDuration`, so the displayed counter equals *active* elapsed time (matching `LiveStats.durationMapper`, which subtracts pauses).
- On pause: set `pauseTime = now` → the system freezes the text at the right value.
- On resume: clear `pauseTime`, add the just-completed pause's duration into `timerStart`.

This means duration stays correct and live on the Lock Screen between our (infrequent) data updates.

---

## 6. Files / Targets to Change

**New widget extension target** (e.g. `MoveFeetActivities`):
- `MoveFeetActivities/WorkoutActivityWidget.swift` — `Widget` with `ActivityConfiguration` + Lock Screen view + `DynamicIsland { … }`.
- `MoveFeetActivities/*View.swift` — Lock Screen + Dynamic Island SwiftUI views (no app pods; SwiftUI + SF Symbols only).
- `MoveFeetActivities/Info.plist` (extension), `MoveFeetActivities.entitlements`.
- `@main struct ...Bundle: WidgetBundle` (or single `@main` widget).

**Shared (membership in app target + extension target):**
- `WorkoutActivityAttributes.swift` (the model in §3). Keep dependency-free.

**Main app:**
- `WorkoutLiveActivityController.swift` (§4).
- `NewWorkoutViewController.swift` — instantiate the controller alongside other components (one line in `init`), no structural change.
- `Support Files/Info.plist` — add `NSSupportsLiveActivities = YES` (and optionally `NSSupportsLiveActivitiesFrequentUpdates` — *not* needed for local updates; leave off).

**Project / tooling:**
- `MoveFeet.xcodeproj/project.pbxproj` — new extension target, "Embed App Extensions" (or "Embed Foundation Extensions") build phase on the app, target membership for the shared file, signing config for the new target.
- `Podfile` — the extension should **not** inherit the app's heavy pods. Either don't add it to the Podfile, or add a minimal `target` with no pods. (Verify `pod install` doesn't try to link CoreStore/Cache into the extension.)
- Asset catalog: ensure any SF Symbols are system symbols; if reusing custom glyphs (`runningGlyph`), add them to the extension's assets or use SF Symbols instead.

---

## 7. Signing / Entitlements Requirements

| Requirement | Needed for v1 (display-only, local)? | Notes |
|---|---|---|
| `NSSupportsLiveActivities` in **app** Info.plist | **Yes** | Gate for ActivityKit. |
| Widget extension target + provisioning profile | **Yes** | New bundle ID `com.wcc.movefeet.<ext>`; Automatic signing under team `W67CF9C739` should generate it. |
| **App Groups** entitlement (app + ext) | **No for v1**; **Yes** if/when adding interactive App Intents or sharing assets/state | Local `Activity.update()` passes `ContentState` directly — no shared container required. Add `group.com.wcc.movefeet` only when the deferred interactive phase needs the extension/intent to reach app state. |
| Push entitlement (`...activity-push-notification...`) | **No** | We use local updates only. Would only matter for server-driven updates. |
| Frequent-updates entitlement | **No** | Duration is system-ticked; data updates are coarse. |

No new privacy strings required (no new data access).

---

## 8. Incremental Implementation Sequence

1. **Scaffold the extension.** Add the Widget Extension target (iOS 17), confirm it builds/embeds, confirm `Podfile`/`pod install` doesn't pollute it. Ship a hardcoded placeholder Live Activity.
2. **Shared model.** Add `WorkoutActivityAttributes` to both targets.
3. **Lock Screen view.** Build the static card from a mock `ContentState`; validate via Xcode preview + a debug "start fake activity" button. Nail the `Text(timerInterval:pauseTime:)` behavior.
4. **Dynamic Island.** Compact / minimal / expanded regions from the same mock state.
5. **Controller + start/end.** Add `WorkoutLiveActivityController`, wire into `NewWorkoutViewController`; start on first `.recording`, end on Save/Discard. Verify on device.
6. **Live data + pause/resume.** Subscribe to builder output, throttle updates, implement the §5.1 timer-start recompute across pauses/auto-pauses. Verify duration matches the in-app tile.
7. **Edge cases.** Continue-after-stop, force-quit reconciliation on launch, `areActivitiesEnabled == false`, multiple-start guard, end-on-app-termination.
8. **(Deferred) Interactive controls.** Pause/Resume/Stop via `LiveActivityIntent`. Requires an app-level handle to the active `WorkoutBuilder` (a coordinator/singleton holding the current session) + likely App Groups. Design separately.
9. **(Deferred) Apple Watch / CarPlay.** `supplementalActivityFamilies` — out of scope now.

---

## 9. Risks / Unknowns

- **Interactive buttons need state routing.** The builder is owned by `NewWorkoutViewController` and driven by Combine subjects; there's no app-global handle. `LiveActivityIntent.perform()` runs in the app process but needs a way to deliver `.paused`/`.recording`/`.ready` suggestions to the *live* builder. Requires introducing a session coordinator/singleton (and probably App Groups). **This is why v1 is display-only.**
- **Stop ≠ end.** Stopping enters the completion banner where the user may *Continue*. The activity must survive the banner and only end on Save/Discard — otherwise Continue can't resume cleanly. Lifecycle in §5 handles this but needs careful sequencing against `WorkoutCompletionActionHandler`.
- **Background update cadence.** Local updates while backgrounded are throttled by the system. Mitigated by the system-ticked duration (§5.1) + coarse (2–5 s) data updates. Acceptable for distance/pace/calories; confirm on-device that updates land while screen-locked (the existing `location` background mode should keep the app scheduled).
- **CocoaPods + extension linkage.** New targets with `use_frameworks!` can pull unwanted pods into the extension and break the 30/50 MB / dependency hygiene. Must keep the extension pod-free (shared model file must not transitively import CombineExt/CoreStore).
- **Formatting reuse vs duplication.** Pre-formatting strings app-side (recommended) keeps the extension lean but means the controller must observe `LiveStats`/`StatsHelper`. Verify those formatters are reachable from the controller without retain-cycle issues.
- **Workout-type → glyph mapping.** Need a small, dependency-free mapping in the extension (SF Symbols) keyed by `workoutTypeRawValue`; keep it in sync with the app's type list.
- **Hybrid app lifecycle.** App has both `AppDelegate` and a SwiftUI `MoveFeetApp`; confirm where to perform launch-time orphan-activity reconciliation (likely `AppDelegate.didFinishLaunching` or the app's scene activation).
- **iOS version guards.** All ActivityKit here is 16.1/17-safe given the 17.0 floor; still wrap in availability checks per Apple convention. No 26/Liquid Glass work — revisit accented rendering later.

---

## 10. Summary

A self-contained, **local** (no push) Live Activity is a clean fit: the app already runs in the background via the `location` mode during recording, the `WorkoutBuilder` already publishes everything needed, and `LiveStats` already formats it. The main new pieces are a **widget extension target**, a **shared `ActivityAttributes`**, and a small **`WorkoutLiveActivityController`** wired in next to the existing components. The two things to get right are the **pause-aware system-ticked duration** (§5.1) and the **stop-vs-continue lifecycle** (§5). Interactive Dynamic Island controls are deferred until a session coordinator exists to route intents back into the live builder.
