# Move Feet release audit — October 21, 2026

## Scope and priorities

The owner is the only current user. Prioritize current recording correctness and protection of the owner’s data, then fresh-install behavior for future testers. Historical format support is not a general release requirement; test round trips of current data first. Preserve existing data/schema identities while fixing behavior. Nidra is being handled separately by Claude.

Recommended implementation order:

1. Repair pause/resume, workout-type binding, live GPS publication and saved calorie values; add behavioral tests.
2. Make local save and recovery reliable, then fix Health opt-in, export, retry and import checkpoint handling.
3. Correct store/restore/delete failure reporting and supply working policy documents.
4. Verify a real outdoor session with screen lock, pause/resume, a stop, and background app use. Audit findings below are source evidence, not a replacement for that test.

The full audit below records proposed fixes, verification cases and remaining runtime questions. It does not authorize or claim implementation.

---

**Current dev HEAD is not ready for outside testers.** The blockers are recording controls, data loss/recovery, incorrect saved values, Health synchronization, and unavailable policy documents.

Audited commit: `217a3b6ba433e8c1cff311c32840ccf32a03e8b5`. Worktree HEAD matches local `dev`. I read `AGENTS.md`; no repository files were changed. No build, installation, phone access, SSH, personal-data access, or Nidra work occurred. The Grogu workspace build is historical evidence only.

Below, **High** means loss/corruption of data or a broken primary flow; **Medium** means incomplete behavior or misleading feedback. Verification tests are proposed unless explicitly listed as executed.

**Must fix before outside testers — confirmed source defects**

1. **High — Recordings have no durable recovery path.**  
   Recording state lives in memory in [WorkoutBuilder.swift:128](../../MoveFeet/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift#L128); persistence happens only through explicit Save in [WorkoutCompletionActionHandler.swift:145](../../MoveFeet/Models/Workout/WorkoutCompletionActionHandler.swift#L145). A new controller constructs a new builder. Process termination during recording or review loses the unsaved workout.
   **Smallest fix:** checkpoint the existing Codable temporary workout and recording state, then offer recovery on launch; clear it after successful save or confirmed discard.  
   **Test:** terminate during recording, pause, review, and failed Save; relaunch and recover without duplicate workouts.

2. **High — The pause button cannot resume recording.**  
   [NewWorkoutViewController.swift:81](../../MoveFeet/Controllers/Workout/NewWorkoutViewController.swift#L81) always sends `.paused` for `.pauseOrContinue`. After pausing, tapping the displayed Play button sends the same status, which the builder ignores.
   **Smallest fix:** send `.recording` when paused and `.paused` when recording.  
   **Test:** Start → Pause → Play; verify recording resumes and pause duration is excluded exactly once.

3. **High — Workout-type selections do not reach the builder.**  
   The controller supplies a workout-type publisher, but [WorkoutBuilder.swift:219](../../MoveFeet/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift#L219) never subscribes to `input.workoutType`. The builder is initialized with the preference default at [NewWorkoutViewController.swift:209](../../MoveFeet/Controllers/Workout/NewWorkoutViewController.swift#L209). Selecting Cycling can therefore display Cycling while saving the default type, affecting calories and Health export.
   **Smallest fix:** bind the supplied type to `workoutTypeRelay`, with an explicit rule for changes after Start.  
   **Test:** choose every supported type, including the initial-type presentation path; verify saved type, calculations, and exported Health activity type.

4. **High — Active GPS updates stop feeding automatic pause detection.**  
   [LocationManagement.swift:229](../../MoveFeet/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift#L229) publishes `currentLocationRelay` only while not recording. [AutoPauseDetection.swift:97](../../MoveFeet/Models/Workout/WorkoutBuilder/Components/AutoPauseDetection.swift#L97) consumes that publisher. During recording it receives no fresh speed samples; map following also consumes this stale stream.
   **Smallest fix:** publish current location independently of route-storage eligibility and recording state.  
   **Test:** feed moving → stationary → moving samples; verify auto-pause/resume and camera following continue throughout recording.

5. **High — Saved calories contain body weight.**  
   [NewWorkout.swift:28](../../MoveFeet/Models/Data/NewWorkout.swift#L28) calculates `burnedEnergy`, but line 43 passes `bodyWeight` into the saved `burnedEnergy` field. Both recorded and manually created workouts use this initializer.
   **Smallest fix:** pass the calculated energy value.  
   **Test:** create two workouts of different distances at the same weight; verify saved energy matches the calculation and Health export, rather than the weight.

6. **High — Saving a recorded workout does not perform enabled Health synchronization.**  
   [WorkoutCompletionActionHandler.swift:145](../../MoveFeet/Models/Workout/WorkoutCompletionActionHandler.swift#L145) saves locally and dismisses without checking the sync preference or calling Health export. Manual creation does call it at [EditWorkoutState.swift:238](../../MoveFeet/Views/SwiftUI/EditWorkout/EditWorkoutState.swift#L238).
   **Smallest fix:** after local success, export when enabled and report Health failure separately while preserving the local workout.  
   **Test:** save recordings with synchronization on/off and with Health writes denied; verify one local record, the expected Health record, and accurate feedback.

7. **High — “Sync All” queries a random Health UUID instead of unsynced workouts.**  
   [HealthStoreManager.swift:247](../../MoveFeet/Models/HealthKit/HealthStoreManager.swift#L247) uses `_healthKitUUID == UUID()`. Ordinary unsynced records have a nil reference, so the action reports everything already synced.
   **Smallest fix:** query nil Health references.  
   **Test:** seed linked and unlinked workouts; verify only unlinked records export, and repeating the action creates no duplicates.

8. **High — Health authorization is requested even when the user opted out.**  
   [OnboardingState.swift:109](../../MoveFeet/Views/SwiftUI/Onboarding/OnboardingState.swift#L109) always calls observer setup. [HealthStoreManager+Observer.swift:156](../../MoveFeet/Models/HealthKit/HealthStoreManager+Observer.swift#L156) requests authorization before checking the workout-sync preference; the weight branch does likewise.
   **Smallest fix:** check each opt-in preference before requesting its authorization.  
   **Test:** complete onboarding with both Health options off and relaunch; expect no Health authorization requests.

9. **High — Health permission handling blocks valid partial/read-only use and can trap onboarding.**  
   [PermissionManager.swift:36](../../MoveFeet/Models/PermissionManager.swift#L36) requires write authorization for every implemented type. Read queries also use this write-based gate at [HealthStoreManager+Query.swift:113](../../MoveFeet/Models/HealthKit/HealthStoreManager+Query.swift#L113). Selecting sync and declining one unrelated write permission prevents Finish through [OnboardingState.swift:57](../../MoveFeet/Views/SwiftUI/Onboarding/OnboardingState.swift#L57); the forward-only flow offers no way to disable that selection.
   **Smallest fix:** request types per feature, gate writes per type, allow read queries after authorization presentation, and provide Back/Continue without Health. Apple documents that sharing authorization does not reveal read authorization. [Apple documentation](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus)  
   **Test:** read-only import, workout-only writes, denied weight/heart-rate writes, and denial during onboarding; each should degrade without trapping setup.

10. **High — Automatic Health import advances its checkpoint before saving data.**  
    [HealthStoreManager+Observer.swift:92](../../MoveFeet/Models/HealthKit/HealthStoreManager+Observer.swift#L92) persists the new anchor before conversion and database insertion. Save failures are only printed. A subsequent launch starts beyond the failed batch, so automatic import does not retry it.
    **Smallest fix:** advance the anchor after successful processing, or durably queue the batch first.  
    **Test:** inject a database failure, relaunch, and verify the same batch retries exactly once.

11. **High — Restore reports duplicate skips as failure and can commit only part of a backup.**  
    [BackupManager.swift:117](../../MoveFeet/Models/Data/Backup/BackupManager.swift#L117) treats any `saveError` as failure and discards returned imported-record information. Yet [DataManager.swift:404](../../MoveFeet/Models/Data/DataManager.swift#L404) deliberately returns success plus `.notAllSaved` for duplicate skips. Workouts and events also use separate transactions, without rollback across them.
    **Smallest fix:** distinguish duplicate skips from failures, preserve counts, and use one restore transaction for atomic workout/event insertion.  
    **Test:** restore twice, restore overlapping backups, and inject failure into either entity group; verify counts, relationships, feedback, and rollback behavior.

12. **High — Store setup failures are ignored by the root router.**  
    [RootView.swift:65](../../MoveFeet/Views/SwiftUI/Shell/RootView.swift#L65) ignores `DataManager.setup`’s error and always calls `finishBoot()`. Storage or migration failure therefore enters normal onboarding/main UI with an unavailable or incompletely migrated store.
    **Smallest fix:** add a setup-error state with retry and recovery guidance; keep normal data operations unavailable until setup succeeds.  
    **Test:** inject add-storage and intermediate-migration failures; verify no normal store access or destructive reset occurs.

13. **High — Delete All can report success after a deletion error.**  
    [DataManager.swift:846](../../MoveFeet/Models/Data/DataManager.swift#L846) catches deletion errors without aborting, then returns `completion(true, error)`. [SettingsView.swift:409](../../MoveFeet/Views/SwiftUI/Settings/SettingsView.swift#L409) ignores the error and resets preferences. Remaining data can survive an apparently successful reset.
    **Smallest fix:** abort/rollback on deletion failure, return failure, and require both success and no error before resetting preferences.  
    **Test:** fail each deletion stage; verify retained data/preferences remain consistent and an error is shown.

14. **High — Policy documents are unavailable, and HTTP errors are accepted as policy text.**  
    Read-only requests during this audit returned **404 HTML** for both configured [privacy](https://move.wavelength.computer/policies/privacy-policy.txt) and [terms](https://move.wavelength.computer/policies/terms-of-service.txt) URLs. [PolicyManager.swift:48](../../MoveFeet/Models/Settings/PolicyManager.swift#L48) treats any UTF-8 response body as success, while onboarding requires agreement.
    **Smallest fix:** publish the intended documents, validate HTTP status/content, and provide a bundled fallback or explicit unavailable state.  
    **Test:** exercise 200 text, 404 HTML, empty response, and offline launch; users must receive the intended document or a clear failure.

**Can wait for a bounded initial test — confirmed problems**

These should still be tracked; Health completeness work should precede broader Health testing.

| Severity / finding | Evidence and trigger → impact | Smallest fix and verification |
|---|---|---|
| **Medium — Imported steps stop accumulating** | [HealthStoreManager.swift:550](../../MoveFeet/Models/HealthKit/HealthStoreManager.swift#L550): `lastValue ?? 0 + sample` retains the first non-nil accumulated value instead of adding subsequent samples. | Use `(lastValue ?? 0) + sample`. Test samples 100, 200, 300 → 600. [Swift operator precedence](https://developer.apple.com/documentation/swift/operator-declarations) |
| **Medium — Health export finishes before route/sample success** | [HealthStoreManager.swift:194](../../MoveFeet/Models/HealthKit/HealthStoreManager.swift#L194) starts asynchronous attachment, records the Health reference, and completes independently. Route insertion failure is silently dropped at line 495. | Await attachments, surface partial success, and retain retry status. Inject route/sample failures; verify truthful feedback and repair without duplicating the parent workout. |
| **Medium — Invalid/stale GPS samples are not rejected** | [LocationManagement.swift:72](../../MoveFeet/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift#L72) accepts negative horizontal accuracy; recording at line 242 has no timestamp/order check. Such supplied samples can affect readiness, route, and distance. | Reject invalid accuracy and stale/out-of-order timestamps. Feed negative accuracy, cached, duplicate, and reversed-time samples; verify no distance corruption. |
| **Medium — Fork-facing documentation routes people upstream** | [README.md:31](../../README.md#L31) retains the inherited beta invitation and upstream issue/contribution destinations; [CONTRIBUTING.md:11](../../CONTRIBUTING.md#L11) instructs cloning upstream. | Replace fork operational destinations while retaining attribution. Verify every tester/support/contribution link against the intended fork destination. |
| **Medium — Health permission descriptions misdescribe the operations** | [Info.plist:38](../../MoveFeet/Support%20Files/Info.plist#L38) describes saving under Share and reading under Update; English localized overrides repeat it at [InfoPlist.strings:21](../../MoveFeet/Support%20Files/en.lproj/InfoPlist.strings#L21). | Describe actual read/import and write/export uses consistently across localizations. Verify the displayed prompts on a fresh authorization flow. |

**Needs real-device or release-artifact evidence — untested risks**

These are **not confirmed runtime failures**.

| Severity | Evidence / concrete risk | Required verification; smallest response if it fails |
|---|---|---|
| **High** | Background location is enabled, but automatic location pausing is also enabled and errors are only logged: [LocationManagement.swift:210](../../MoveFeet/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift#L210), line 254. | Record a measured route with screen locked, extended stops, app switching, poor GPS, and power-saving conditions. Verify continuity and visible failure handling; add targeted pause/resume/error recovery where demonstrated necessary. |
| **High** | Builder/component state crosses UI, sensor, and background delivery queues: [Publisher.swift:37](../../MoveFeet/Extensions/Combine/Publisher.swift#L37), [WorkoutBuilder.swift:315](../../MoveFeet/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift#L315). Final-sample ordering and races remain unproven. | Stress rapid Pause/Stop/Continue while samples arrive; use race diagnostics and compare captured versus saved samples. Serialize state mutation and drain pending samples before final capture if needed. |
| **High** | Observer setup can register another workout query without retaining a handle or guarding registration: [HealthStoreManager+Observer.swift:154](../../MoveFeet/Models/HealthKit/HealthStoreManager+Observer.swift#L154). Repeated toggles could cause overlapping imports. | Toggle workout/weight sync repeatedly, revoke permissions, lock/unlock, and add one synthetic Health workout. Expect one local import; retain/stop query handles and enforce Health-UUID deduplication if overlap occurs. |
| **High** | Backup supports V1–V4, but there is no current full restore proof: [BackupManager.swift:79](../../MoveFeet/Models/Data/Backup/BackupManager.swift#L79). | Round-trip synthetic fixtures for all versions, event relationships, pauses, routes, heart rates, overlap, large files, and interrupted restore. Verify cross-install Health references; repair only demonstrated conversion/reference failures. |
| **Medium** | Signing/version settings are source configuration, not a validated distribution artifact: [project.pbxproj:1914](../../MoveFeet.xcodeproj/project.pbxproj#L1914). | Later produce and inspect the intended Release archive: identifiers, entitlements, embedded extension, versions, privacy resources, and provisioning. Correct mismatches before distribution. |

**Architecture and reusable family capabilities**

The existing architecture supports incremental repair.

| Existing capability | Evidence and reuse boundary |
|---|---|
| Composable recording engine | [WorkoutBuilderComponent.swift:24](../../MoveFeet/Protocols/WorkoutBuilder/WorkoutBuilderComponent.swift#L24) and the controller’s component assembly at [NewWorkoutViewController.swift:208](../../MoveFeet/Controllers/Workout/NewWorkoutViewController.swift#L208). Location, steps, altitude, statistics, and automatic pause already have separate components. |
| Versioned persistence and presentation snapshots | [OutRunV4.swift:90](../../MoveFeet/Models/Data/DataModels/Versions/OutRunV4.swift#L90) preserves the migration chain; [WorkoutStore.swift:16](../../MoveFeet/Models/Data/Store/WorkoutStore.swift#L16) publishes immutable timeline snapshots. These are useful family patterns without replacing CoreStore. |
| Portable data and Health adapters | [TempV4.swift:25](../../MoveFeet/Models/Data/Temp/Versions/TempV4.swift#L25), versioned backups, GPX export, and `HealthStoreManager` provide existing boundaries. They need correctness fixes before reuse. |
| Shared units, formatting, maps, and Live Activities | [UserPreferences.swift:42](../../MoveFeet/Models/Preferences/UserPreferences.swift#L42), [RouteMapView.swift:21](../../MoveFeet/Views/SwiftUI/RouteMapView.swift#L21), and [WorkoutLiveActivityController.swift:31](../../MoveFeet/LiveActivity/WorkoutLiveActivityController.swift#L31) are concrete reuse candidates. They currently remain app-specific code, not a packaged shared library. |

**Privacy, support, attribution, and distribution facts**

- The app declares location background mode and HealthKit entitlement. Its privacy manifest declares UserDefaults and file-timestamp reasons and is included in app resources at [project.pbxproj:1392](../../MoveFeet.xcodeproj/project.pbxproj#L1392). This does not establish archive-wide manifest completeness.
- Temporary exports explicitly receive file protection and backup exclusion at [TemporaryExportFileProtection.swift:10](../../MoveFeet/Models/Data/TemporaryExportFileProtection.swift#L10). Locked-device database accessibility remains untested.
- Settings points to Wavelength support and fork source at [SettingsView.swift:442](../../MoveFeet/Views/SwiftUI/Settings/SettingsView.swift#L442). Inbox delivery and unauthenticated source availability were not verified; no messages were sent.
- Fork attribution is present in [NOTICE.md:3](../../NOTICE.md#L3), README, retained headers, and Settings. Preserved schema/backup identifiers are documented compatibility decisions, not stale branding defects.
- Release-owner questions remain: which distribution channel, what exact corresponding-source artifact accompanies that binary, whether recipients can access it, and whether store privacy declarations match the shipped app and dependencies. I make no current legal-compliance or App Store acceptance determination.

**Checks executed and limits**

Passed: `plutil` validation of **54** tracked project/plist/entitlement/privacy/localization files; parsing **2** tracked XML files; install-script syntax checking without execution; source-path resolution for all **182 source-phase entries**; and clean working/index diff checks.

All **17 test files / 49 test methods** are wired into the test target. **XCTest was not run.** This checkout has neither `Pods/` nor `MoveFeet.xcworkspace`; dependencies were not installed. Existing tests include useful migration/runtime cases and many source-shape checks, but they do not establish release readiness or cover the failures above.