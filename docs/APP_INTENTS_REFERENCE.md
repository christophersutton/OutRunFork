# App Intents — Engineering Reference

> Scope: a practical, fairly exhaustive map of Apple's **App Intents** framework — the API
> surface, every entry point, the iOS 26 → iOS 27 (WWDC 2026) additions, and concrete
> applications for **Move: Feet** (a run-tracking app).
>
> Last verified: June 2026, against Apple's documentation JSON feed
> (`developer.apple.com/tutorials/data/documentation/...`). Symbol names below were taken
> verbatim from Apple's "App Intents — Updates" feed. Marketing/architecture claims that
> are **not** in the API docs (e.g. the Gemini Siri backend) are flagged `[press-reported]`.
>
> iOS naming: WWDC'24 → iOS 18 · WWDC'25 → iOS 26 · WWDC'26 → iOS 27.

---

## 0. TL;DR mental model

App Intents is a **vocabulary, not a runtime listener**. You declare *what your app can do*
and *what nouns it owns*; the OS decides *when and where* to surface those. Three primitives:

- **`AppIntent`** — an action (`perform()` + `@Parameter`s).
- **`AppEntity`** — a noun your app owns (a Run, a Route, a Playlist).
- **`AppEnum`** — fixed-choice parameter values (RunType: outdoor/treadmill/trail).

The OS compiles this metadata at build time and exposes it across ~16 **surfaces** (Siri,
Spotlight, Shortcuts, widgets, Live Activities, controls, Action button, Focus, Visual
Intelligence, …). Intents don't subscribe to system state — instead the *surface* or a
*Shortcuts Automation* triggers them, and you read state at runtime inside `perform()`.

Framework landing: <https://developer.apple.com/documentation/appintents>
What's new: <https://developer.apple.com/documentation/updates/appintents>
HIG (Siri / App Shortcuts): <https://developer.apple.com/design/human-interface-guidelines/siri>

---

## 1. Core building blocks

### 1.1 `AppIntent`
Docs: <https://developer.apple.com/documentation/appintents/appintent>

```swift
struct StartRunIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Run"
    static var description = IntentDescription("Starts a new run.")
    static var isDiscoverable = true          // appears in Shortcuts/Spotlight (default true)
    static var openAppWhenRun = false         // legacy foreground toggle; prefer supportedModes

    @Parameter(title: "Run Type") var runType: RunTypeEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$runType) run")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await RunController.shared.start(type: runType ?? .outdoor)
        return .result(dialog: "Run started.")
    }
}
```

Key static knobs:
- `title`, `description` — required; verb-noun, user-facing.
- `isDiscoverable` — show in Shortcuts/Spotlight.
- `openAppWhenRun` — legacy; superseded by `supportedModes` (§3).
- `authenticationPolicy` — `.alwaysAllowed` / `.requiresAuthentication` /
  `.requiresLocalDeviceAuthentication`.

### 1.2 `AppEntity`
Docs: <https://developer.apple.com/documentation/appintents/appentity>

A stable, identifiable object the system can pass around. **Keep entities separate from your
domain models** — they're a projection, not your `@Model`/struct.

```swift
struct RunEntity: AppEntity {
    var id: UUID
    @Property(title: "Distance") var distanceMeters: Double
    @Property(title: "Date") var startDate: Date

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Run"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(Measurement(value: distanceMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated))",
                              subtitle: "\(startDate.formatted())")
    }
    static var defaultQuery = RunQuery()
}
```

### 1.3 `AppEnum`
Docs: <https://developer.apple.com/documentation/appintents/appenum>

```swift
enum RunTypeEnum: String, AppEnum {
    case outdoor, treadmill, trail
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Run Type"
    static var caseDisplayRepresentations: [RunTypeEnum: DisplayRepresentation] = [
        .outdoor: "Outdoor", .treadmill: "Treadmill", .trail: "Trail"
    ]
}
```

---

## 2. Parameters, queries, and resolution

### 2.1 `@Parameter`
Docs: <https://developer.apple.com/documentation/appintents/parameter>
Optional vs required, defaults, `requestValueDialog`, and `parameterSummary` (the natural-
language phrasing Siri/Spotlight render). Required params with no default **must** appear in
the summary or the intent won't surface in Spotlight.

### 2.2 Entity queries — the family
- **`EntityQuery`** — `entities(for:)` + `suggestedEntities()`.
  <https://developer.apple.com/documentation/appintents/entityquery>
- **`EntityStringQuery`** — adds `entities(matching:)` for free-text search.
  <https://developer.apple.com/documentation/appintents/entitystringquery>
- **`EnumerableEntityQuery`** — `allEntities()` for small bounded sets.
- **`IndexedEntityQuery`** *(iOS 27)* — system pulls indexed entities by id from the Spotlight
  index. <https://developer.apple.com/documentation/appintents/indexedentityquery>
- **`UniqueAppEntityQuery`** — for singletons (see `UniqueAppEntity`, §8).

### 2.3 Property wrappers on entities
- **`@Property`** — expose a value to the system (filter/sort/index).
- **`@ComputedProperty`** *(iOS 26)* — reads a source of truth, no stored value.
  <https://developer.apple.com/documentation/appintents/computedproperty>
- **`@DeferredProperty`** *(iOS 26)* — expensive, fetched only when requested.

---

## 3. Execution model (foreground / background / extension)

Docs: <https://developer.apple.com/documentation/appintents/appintent>

- **`IntentModes`** + `supportedModes` *(iOS 27)* — declare `.background`,
  `.foreground(.immediate/.dynamic/.deferred)`, or both.
  <https://developer.apple.com/documentation/appintents/intentmodes>
- **`IntentSystemContext.currentMode`** *(iOS 27)* — read the live mode inside `perform()` and
  adapt (e.g. `canContinueInForeground`).
  <https://developer.apple.com/documentation/appintents/intentsystemcontext>
- **`IntentExecutionTargets`** + `allowedExecutionTargets` *(iOS 27)* — pin which process runs
  the intent/query: **main app**, **App Intents extension**, or **widget extension**. Critical
  for anything touching a live `HKWorkoutSession` (must be the app).
  <https://developer.apple.com/documentation/appintents/intentexecutiontargets>
- **`LongRunningIntent`** *(iOS 27)* — extend background runtime via
  `performBackgroundTask(options:operation:)` with `LongRunningTaskOptions`, reporting progress.
  <https://developer.apple.com/documentation/appintents/longrunningintent>
- **`CancellableIntent`** *(iOS 27)* — graceful cleanup; inspect `IntentCancellationReason`
  (deliberate cancel vs timeout).
  <https://developer.apple.com/documentation/appintents/cancellableintent>
- **`UndoableIntent`** *(iOS 27)* — reverse an action's effect.
  <https://developer.apple.com/documentation/appintents/undoableintent>

Legacy pattern: `openAppWhenRun = true` or return `.result(opensIntent:)` to foreground the app.

---

## 4. Results, dialogs, snippets, confirmation

### 4.1 Result types
`IntentResult` variants: `.result()`, `.result(value:)`, `.result(dialog:)`,
`.result(view:)`, `.result(opensIntent:)`, plus protocols `ReturnsValue`, `ProvidesDialog`,
`ShowsSnippetView`, `OpensIntent`.

### 4.2 Static result snippet
A one-shot SwiftUI view shown in the **system surface** (not your app) describing the outcome:
```swift
return .result(view: RunStartedView(distanceGoal: goal))
```

### 4.3 `SnippetIntent` — interactive snippets *(iOS 26)*
Docs: <https://developer.apple.com/documentation/appintents/snippetintent>

- Displayed **outside** your app (Siri / Spotlight / Shortcuts / floating). Code runs in your
  process; the app does **not** foreground.
- Returns `some IntentResult & ShowsSnippetView`.
- **Interaction loop:** a button/toggle in the snippet runs *its* App Intent; when that
  completes, **the system re-calls the `SnippetIntent.perform()`** to redraw. → Your
  `perform()` must be idempotent and re-fetch fresh data each call.

```swift
struct RunStatusSnippetIntent: SnippetIntent {
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let s = await RunController.shared.liveStatus()   // re-fetched every interaction
        return .result(view: RunStatusView(status: s))    // hosts Pause/Stop buttons
    }
}
```

### 4.4 Confirmation & choice (don't hand-roll confirm/cancel)
- **`requestConfirmation(result:confirmationActionName:)`** — system-drawn confirm/cancel; can
  carry a custom view (e.g. run summary before Stop).
  <https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(result:confirmationactionname:)>
- **`requestConfirmation(conditions:actionName:dialog:)`** *(iOS 18)* — only confirm if context
  matches a condition.
- **`requestChoice(between:dialog:)`** — structured multiple-choice (`IntentChoiceOption`).

---

## 5. Entry points / surfaces (the full list)

| Surface | Key API | Docs |
|---|---|---|
| **Siri / Apple Intelligence** | App schema domains; assistant schemas | <https://developer.apple.com/documentation/appintents/app-intent-domains> |
| **App Shortcuts** (zero-setup) | `AppShortcutsProvider`, `AppShortcut` | <https://developer.apple.com/documentation/appintents/appshortcutsprovider> |
| **Shortcuts app** | any discoverable `AppIntent` | <https://developer.apple.com/documentation/appintents/appintent> |
| **Shortcuts Automations** | system triggers (see §6) | <https://support.apple.com/guide/shortcuts/apde31e9638b/ios> |
| **Spotlight** | `IndexedEntity`, `@Property(indexingKey:)`, `EntityStringQuery` | <https://developer.apple.com/documentation/appintents/indexedentity> |
| **Widgets (interactive)** | `Button(intent:)` / `Toggle(intent:)`; `RunSystemShortcutIntent` *(iOS 27)* | <https://developer.apple.com/documentation/appintents/runsystemshortcutintent> |
| **Live Activities / Dynamic Island** | `Button(intent:)` in ActivityKit UI | <https://developer.apple.com/documentation/activitykit> |
| **Controls (Control Center / Lock Screen)** | `ControlConfigurationIntent` *(iOS 18)* | <https://developer.apple.com/documentation/appintents/controlconfigurationintent> |
| **Action button** (15 Pro+) / **Apple Watch Ultra** | App Shortcut assignment | HIG |
| **Apple Pencil Pro squeeze** | App Shortcut assignment | HIG |
| **Focus filters** | `SetFocusFilterIntent` | <https://developer.apple.com/documentation/appintents/setfocusfilterintent> |
| **Hardware capture** | `CameraCaptureIntent`, `AudioRecordingIntent` *(iOS 18)* | <https://developer.apple.com/documentation/appintents/cameracaptureintent> |
| **Visual Intelligence** | `IntentValueQuery`, `IntentValueRepresentation` | <https://developer.apple.com/documentation/appintents/intentvaluequery> |
| **Smart Stack (Watch/Lock Screen)** | `RelevantIntentManager`, `RelevantIntent` | <https://developer.apple.com/documentation/appintents/relevantintent> |
| **Apple Intelligence "Use Model" action** | entities as JSON to the on-device LLM | (Shortcuts) |
| **Onscreen entities** | `NSUserActivity.appEntityIdentifier` *(iOS 26)* | <https://developer.apple.com/documentation/foundation/nsuseractivity> |

### 5.1 App Shortcuts specifics
`AppShortcut(intent:phrases:shortTitle:systemImageName:)` — phrases must interpolate
`\(.applicationName)`. Extras: `NegativeAppShortcutPhrases` (iOS 17+), `SiriTipView`,
`ShortcutsLink`, `shortcutTileColor`, `updateAppShortcutParameters()`.
<https://developer.apple.com/documentation/appintents/appshortcut>

---

## 6. System-state & context (the "is audio playing?" question)

There is **no** "register intent X only while media plays" hook. The sanctioned patterns:

1. **Shortcuts Automations** — event triggers: CarPlay, Bluetooth device, Wi-Fi, NFC, Focus
   on/off, Alarm, Sleep, **Apple Watch Workout start/end**, App open/close, Time of Day,
   Battery/Charger/Low-Power, Airplane/DND, **Sound Recognition**, Email/Message/Transaction.
   (No "media is playing" trigger.) <https://support.apple.com/guide/shortcuts/apde31e9638b/ios>
2. **Focus filters** — `SetFocusFilterIntent`: the system hands your app the active Focus; you
   reconfigure (e.g. a "Run" Focus surfaces run controls).
3. **Relevance / proactivity:**
   - `RelevantContext` / `RelevantIntent` / `RelevantIntentManager` — donate when an intent or
     widget is relevant (date/location/context) → Smart Stack & suggestions.
   - **`RelevantEntities`** *(iOS 27)* — system suggests **media entities during workouts** and
     similar contexts. This is the closest thing to "surface a run playlist while running."
     <https://developer.apple.com/documentation/appintents/relevantentities>
   - `PredictableIntent` — learns usage patterns for proactive suggestions.
4. **Read state at runtime** inside `perform()`: `AVAudioSession.isOtherAudioPlaying`,
   `MPNowPlayingInfoCenter`, your own controller — branch behavior there.
5. **Dynamic App Shortcuts** — conditionally include shortcuts and call
   `updateAppShortcutParameters()` when app state changes.

---

## 7. Apple Intelligence integration

- **App schema domains** — conform intents/entities/enums to a domain so Siri/Apple
  Intelligence understands them semantically.
  <https://developer.apple.com/documentation/appintents/app-intent-domains>
- **Assistant schemas** — pre-built intent shapes per app category (Books, Browser, Camera,
  Email, Photos, Presentations, Spreadsheets, Documents).
- **"Use Model" action** (Shortcuts, iOS 18.1+) — your entities are serialized to JSON and
  passed to the on-device model for filtering/reasoning; outputs can be Text/Number/Bool/
  Dictionary/Date/Entities. **Use `AttributedString`** parameters to preserve rich text.
- **Onscreen entities** — `.userActivity(...) { $0.appEntityIdentifier = ... }` lets Siri/
  ChatGPT reason about what's on screen.

`[press-reported]` The iOS 27 Siri reportedly routes complex queries to a large **Google
Gemini** model on **Apple Private Cloud Compute**, with on-device Foundation Models for simple
queries. Not in the API docs; treat as strategy context, not API.

---

## 8. Entity capabilities (deep cuts)

- **`IndexedEntity`** *(iOS 18)* + `@Property(indexingKey:)` / `@ComputedProperty(indexingKey:)`
  *(iOS 26)* — Spotlight index; auto-generates Find actions.
- **`EntityCollection`** *(iOS 27)* — reference large sets by id, resolve on demand (avoids
  resolving every id at parameter resolution).
  <https://developer.apple.com/documentation/appintents/entitycollection>
- **`UniqueAppEntity`** + **`UniqueAppEntityQuery`** *(iOS 18)* — singletons (e.g. app settings).
- **`UnionValue()`** macro *(iOS 18)* → **`AppUnionValue`** + **`AppUnionValueCasesProviding`**
  *(iOS 27)* — union-type parameters with rich picker UI.
- **`Transferable`** conformance — share/drag/paste entities; pairs with `IntentFile`,
  `FileEntity`. <https://developer.apple.com/documentation/coretransferable/transferable>
- **`URLRepresentableIntent` / `URLRepresentableEntity` / `URLRepresentableEnum`** *(iOS 18)* —
  deep links via universal links.
- **`SyncableEntity`** *(iOS 27)* — stable cross-device ids for task continuation (iPhone→Mac).
  <https://developer.apple.com/documentation/appintents/syncableentity>
- **`OwnershipProvidingEntity`** + **`EntityOwnership`** *(iOS 27)* — confirm before destructive
  actions on **shared/public** entities.
  <https://developer.apple.com/documentation/appintents/ownershipprovidingentity>
- **`IntentValueRepresentation`** *(iOS 27)* — bridge an entity to system intent value types in
  `transferRepresentation` (e.g. hand a route to Maps).

---

## 9. Errors

- **`AppIntentError`** + `init(description:)` *(iOS 27)* — localized failure text; or wrap any
  `CustomLocalizedStringResourceConvertible`.
  <https://developer.apple.com/documentation/appintents/appintenterror>
- Built-ins *(iOS 18)*: `AppIntentError.PermissionRequired`, `.Unrecoverable`,
  `.UserActionRequired`.
- **`CustomAppIntentErrorConvertible`** — map your domain errors to user-facing messages.

---

## 10. Testing & packaging

- **App Intents Testing** *(framework, iOS 26+)* — its own topic section under Testing; catches
  broken entity mapping, missing intent behavior, bad assumptions.
  <https://developer.apple.com/documentation/appintents/testing-your-app-intents-code>
- **`AppIntentsPackage`** — declare intents inside Swift Packages / dynamic libraries; the app
  target aggregates via `includedPackages`.
  <https://developer.apple.com/documentation/appintents/appintentspackage>

---

## 11. Version timeline (verbatim buckets from Apple's Updates feed)

**iOS 27 / WWDC 2026 (June 2026)**
`SyncableEntity` · `OwnershipProvidingEntity` + `EntityOwnership` · `RelevantEntities` ·
`IntentValueRepresentation` · `RunSystemShortcutIntent` · `LongRunningIntent` +
`LongRunningTaskOptions` · `CancellableIntent` + `IntentCancellationReason` · `UndoableIntent` ·
`IntentModes`/`supportedModes` + `IntentSystemContext.currentMode` · `IntentExecutionTargets`/
`allowedExecutionTargets` · `EntityCollection` · `AppUnionValue` + `AppUnionValueCasesProviding` ·
`IndexedEntityQuery` · `AppIntentError(description:)` · app-schema conformance.

**iOS 26 / WWDC 2025 (June 2025)**
`SnippetIntent` · `IndexedEntity` + `@ComputedProperty(indexingKey:)`/`@Property(indexingKey:)` ·
`IntentValueQuery` (Visual Intelligence) · `AppEntity: Transferable` +
`NSUserActivity.appEntityIdentifier`.

**iOS 18.2 (Nov 2024)** onscreen content → `AppEntity` + assistant schema + `Transferable` +
`appEntityIdentifier`.

**iOS 18 / WWDC 2024 (June 2024)**
`ControlConfigurationIntent` · `CameraCaptureIntent` · `AudioRecordingIntent` · `IndexedEntity` ·
app-schema domains · `Transferable`/`IntentFile`/`FileEntity` · `URLRepresentable*` ·
`UnionValue()` · `UniqueAppEntity`(+Query) · `AppIntentError.{PermissionRequired,Unrecoverable,
UserActionRequired}` · conditional `requestConfirmation`.

`[press-reported]` WWDC 2026 also delivered a formal **SiriKit deprecation** notice (~2–3 yr
window) making App Intents the sole framework for third-party Siri integration.

---

## 12. Applications for Move: Feet

### 12.1 Recommended surface map
| Goal | Surface | Intents |
|---|---|---|
| "Start my run" hands-free | App Shortcut → Siri / Action button | `StartRunIntent` |
| Live in-run controls | **Live Activity + Dynamic Island** (primary) | `PauseRunIntent`, `ResumeRunIntent`, `StopRunIntent` |
| "How's my run going?" | `SnippetIntent` via Siri/Spotlight | `RunStatusSnippetIntent` (hosts Pause/Stop) |
| Log/review past runs | Spotlight `IndexedEntity` + Find action | `RunEntity` |
| Stop confirmation | `requestConfirmation(view:)` inside `StopRunIntent` | — |
| Surface a run playlist mid-run | `RelevantEntities` *(iOS 27)* | media entity |
| Auto-start on workout | Shortcuts Automation (Apple Watch Workout / Bluetooth → headphones) | `StartRunIntent` |

### 12.2 The architecture gotcha (read this)
Start/Pause/Stop intents and the snippet may run in an **App Intents extension or background**,
**not** the app's main process. A run is driven by `HKWorkoutSession`/`HKLiveWorkoutBuilder`
+ background location, which **must** live in the app. Therefore:

- Pin run-mutating intents to the app with **`allowedExecutionTargets` (`IntentExecutionTargets`)**, OR
- Keep intents **thin**: they flip a flag in a **shared store** (App Group / shared model) that
  the in-app run engine observes. The Live Activity and snippet read the same store.
- Consider **`LongRunningIntent`** if an intent itself needs extended background runtime.
- The run engine — not the intents — is the source of truth.

### 12.3 Confirmation pattern
```
[Run Status snippet] —tap Stop→ StopRunIntent.perform()
  └─ requestConfirmation(result: .result(view: RunSummaryView(...)))
       ├─ Cancel → no-op; snippet re-renders
       └─ Confirm → end workout + save → snippet redraws "Run saved ✓"
```

---

## 13. Curated links

- Framework: <https://developer.apple.com/documentation/appintents>
- Updates / what's new: <https://developer.apple.com/documentation/updates/appintents>
- App Shortcuts: <https://developer.apple.com/documentation/appintents/app-shortcuts>
- Spotlight integration: <https://developer.apple.com/documentation/appintents/indexedentity>
- Visual Intelligence: <https://developer.apple.com/documentation/appintents/intentvaluequery>
- ActivityKit (Live Activities): <https://developer.apple.com/documentation/activitykit>
- HIG — Siri: <https://developer.apple.com/design/human-interface-guidelines/siri>
- HIG — App Shortcuts: <https://developer.apple.com/design/human-interface-guidelines/app-shortcuts>
- Shortcuts Automation triggers: <https://support.apple.com/guide/shortcuts/apde31e9638b/ios>

### WWDC sessions (watch list)
- WWDC25 — "Explore new advances in App Intents": <https://developer.apple.com/videos/play/wwdc2025/275/>
- WWDC23 — "Explore enhancements to App Intents": <https://developer.apple.com/videos/play/wwdc2023/10103/>
- WWDC23 — "Build widgets for the Smart Stack" (RelevantContext): <https://developer.apple.com/videos/play/wwdc2023/10029/>
- WWDC26 — App Intents "new capabilities" + "Make your app available to Siri" code-along `[session #s press-reported]`

---

*Doc links use Apple's stable `/documentation/appintents/<symbol>` pattern; a few may 404 if
Apple reorganizes — search the framework landing page if so. Symbol existence is verified
against Apple's Updates feed; `[press-reported]` items are third-party and unverified against
Apple docs.*
