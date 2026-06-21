# Axiom Audit Findings

Date: 2026-06-21

Scope: static audit of the iOS app after the startup performance fixes. No app code changes were made for this audit.

## Skills Used

- `axiom-health-check`
- `axiom-swift-performance`
- `axiom-swiftui-performance`
- `axiom-audit-swiftui-architecture`
- `axiom-audit-swiftui-layout`
- `axiom-audit-swiftui-nav`
- `axiom-audit-concurrency`
- `axiom-audit-core-data`
- `axiom-audit-storage`
- `axiom-audit-memory`
- `axiom-audit-accessibility`
- `axiom-audit-codable`
- `axiom-audit-energy`
- `axiom-scan-security-privacy`
- `axiom-modernize`
- `axiom-audit-testing`
- `axiom-audit-ux-flow`

Skills not applied after signal scan: camera, CloudKit/iCloud, SpriteKit, TextKit, StoreKit/IAP, push notifications, foundation models, App Intents, and networking-specific audits. The app has a small HTTPS policy fetch, but no broader networking layer or cache/session policy worth a dedicated networking audit.

## Executive Summary

Startup appears fixed. I did not find another startup-class blocker after the previous changes and the confirmed fast launch. The remaining high-value work is hardening: privacy manifest compliance, async HealthKit/CoreStore boundaries, Dynamic Type/accessibility, Swift 6 actor isolation, and real migration tests.

The map-image work is in a much better place now: requests are cached, deduplicated, queued, and rendered off the startup path. The remaining map-image concern is layout correctness and cache-key sizing on non-fullscreen or differently sized environments.

## Critical

### Missing Privacy Manifest

Status: Addressed 2026-06-21. Added `OutRun/Support Files/PrivacyInfo.xcprivacy`, wired it into the app resources phase, and added `UnitTests/PrivacyManifestTests.swift`.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-privacy-red -only-testing:UnitTests/PrivacyManifestTests -resultBundlePath /tmp/outrun-main-privacy-red.xcresult` failed because `OutRun.app` did not include `PrivacyInfo.xcprivacy`.
- Green: the same test passed with 1 selected test and 0 failures after adding the manifest.

There is no `PrivacyInfo.xcprivacy` in the repository. This is an App Store readiness issue and should be addressed before release.

Evidence:
- `find . -name PrivacyInfo.xcprivacy` returned no files.
- `OutRun/Models/Preferences/UserPreference.swift:43` uses `UserDefaults.standard.set`.
- `OutRun/Models/Preferences/UserPreference.swift:55` removes UserDefaults values.
- `OutRun/Models/Preferences/UserPreference.swift:59` reads from UserDefaults.
- `OutRun/Models/Preferences/UserPreferences.swift:50` removes the app UserDefaults domain.
- File APIs are also present in backup/export/cache-size paths, including `OutRun/Models/Data/Backup/BackupManager.swift:46`, `OutRun/Models/Data/Backup/BackupManager.swift:51`, `OutRun/Models/Data/ExportManager.swift:200`, `OutRun/Extensions/URL.swift:26`, and `OutRun/Extensions/FileManager.swift:42`.

Recommendation:
- Add `PrivacyInfo.xcprivacy`.
- Declare the required reason API categories used by the app, especially UserDefaults and file timestamp/size access if the current Apple required-reason API rules classify these calls.
- Re-check HealthKit, Location, Motion, and exported file behavior against the app privacy questionnaire.

## High

### HealthKit Queries Still Use Synchronous Blocking Bridges

Status: Addressed 2026-06-21. Replaced the synchronous HealthKit query bridges in `HealthStoreManager`, `HealthStoreManager+Query`, and `HealthStoreManager+Observer` with callback-based coordination, and added `UnitTests/HealthKitBlockingQueryTests.swift` to prevent `.wait()` regressions in the HealthKit manager files.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-healthkit-red -only-testing:UnitTests/HealthKitBlockingQueryTests -resultBundlePath /tmp/outrun-main-healthkit-red.xcresult` failed with the expected blocking-wait assertions against `HealthStoreManager.swift` and `HealthStoreManager+Query.swift`.
- Green: the same selected test passed with 1 test and 0 failures after converting the HealthKit paths.
- Static: `rg -n "\\.wait\\(" OutRun/Models/HealthKit UnitTests` found no matches; `plutil -lint OutRun.xcodeproj/project.pbxproj` and `git diff --check` passed for the touched HealthKit/test/project files.
- Adversarial review found no merge-blocking issues. Residual risk: workout conversion now fans out per-workout HealthKit route, step, and heart-rate queries, so very large imports may still deserve future bounded concurrency or progress handling.

Several HealthKit query paths still use `DispatchGroup.wait()`. These are no longer the observed startup bottleneck, but they can block queues during imports, deletes, and duplicate checks.

Evidence:
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:88` defines `objectExists(...) -> Bool`.
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:91` creates a `DispatchGroup`.
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:106` waits synchronously.
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:156` defines synchronous anchored series loading.
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:179` waits synchronously.
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:188` defines synchronous route loading.
- `OutRun/Models/HealthKit/HealthStoreManager+Query.swift:217` waits synchronously.
- `OutRun/Models/HealthKit/HealthStoreManager.swift:286` creates a `DispatchGroup` during delete.
- `OutRun/Models/HealthKit/HealthStoreManager.swift:299` waits synchronously before deleting the workout.

Recommendation:
- Convert these APIs to async functions using continuations or `AsyncThrowingStream` for HealthKit series/route queries.
- Keep HealthKit callback work off the main actor, then hop to `MainActor` only for UI state updates.
- Add bounded import/delete progress so large HealthKit datasets do not monopolize app work.

### CoreStore Model Accessors Hide Threading With Synchronous Main Hops

Status: Partially addressed 2026-06-21. Removed the synchronous `threadSafeSyncReturn` bridge from `DataManager.queryExistingHealthUUIDs` and converted its HealthKit observer/import call sites to the new completion-based API. The broader public model accessor debt remains and should continue through snapshot/DTO expansion.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-corestore-red -only-testing:UnitTests/HealthKitBlockingQueryTests/testHealthUUIDQueryPathDoesNotUseSynchronousMainHops -resultBundlePath /tmp/outrun-main-corestore-red.xcresult` failed with the expected 3 assertions against `DataManager+Query.swift`, `HealthStoreManager+Observer.swift`, and `HealthStoreManager+Query.swift`.
- Green: the same selected test passed with 1 test and 0 failures after the async CoreStore query change.
- Regression class: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-corestore-class -only-testing:UnitTests/HealthKitBlockingQueryTests -resultBundlePath /tmp/outrun-main-corestore-class.xcresult` passed with 2 tests and 0 failures.
- Static: `rg -n "DataManager\\.queryExistingHealthUUIDs\\(\\)|threadSafeSyncReturn|\\.wait\\(\\)" OutRun/Models/Data/DataManager+Query.swift OutRun/Models/HealthKit/HealthStoreManager+Observer.swift OutRun/Models/HealthKit/HealthStoreManager+Query.swift` found no production-source matches; `plutil -lint OutRun.xcodeproj/project.pbxproj` and `git diff --check` passed for the touched files.
- Adversarial review found one merge blocker in the subagent patch: `HKSampleQuery` had lost `sampleType: HealthType.Workout`. The merged version restores `sampleType` and keeps the existing attribute-only CoreStore query shape inside asynchronous transaction work.

The CoreStore models expose many public properties through `threadSafeSyncReturn`, which synchronously dispatches to the main queue from background threads. This avoids obvious thread-confined object crashes, but it can create blocking behavior and makes call sites look cheap when they may block.

Evidence:
- `OutRun/Models/HelperMethods.swift:42` defines `threadSafeSyncReturn`.
- `OutRun/Models/HelperMethods.swift:50` creates a `DispatchGroup`.
- `OutRun/Models/HelperMethods.swift:58` waits synchronously.
- `OutRun/Models/Data/DataModels/Workout.swift:172` through `OutRun/Models/Data/DataModels/Workout.swift:188` use it for scalar properties.
- `OutRun/Models/Data/DataModels/WorkoutRouteDataSample.swift:47` through `OutRun/Models/Data/DataModels/WorkoutRouteDataSample.swift:56` use it for route sample access.
- `OutRun/Models/Data/DataModels/WorkoutHeartRateDataSample.swift:46` through `OutRun/Models/Data/DataModels/WorkoutHeartRateDataSample.swift:48` use it for heart-rate samples.
- `OutRun/Models/Data/DataModels/Event.swift:46` through `OutRun/Models/Data/DataModels/Event.swift:50` use it for event values.
- `OutRun/Models/Data/DataManager+Query.swift:264` says `queryExistingHealthUUIDs()` should only be used on the main thread, then calls `threadSafeSyncReturn`.

Recommendation:
- Keep the value-snapshot pattern introduced for timeline/detail and expand it.
- Avoid passing CoreStore `Workout`/`Event` objects to SwiftUI and formatting layers.
- Add async query APIs for common needs such as existing HealthKit UUIDs, backup data, route summaries, and export inputs.

### Dynamic Type and Accessibility Debt Is Broad

The SwiftUI replacement surfaces and legacy UIKit views use many fixed font sizes. This risks clipping, poor Large Content Size behavior, and inconsistent VoiceOver output.

Evidence:
- Fixed SwiftUI fonts appear in timeline rows: `OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift:48` and `OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift:80`.
- Onboarding uses many fixed sizes: `OutRun/Views/SwiftUI/Onboarding/OnboardingView.swift:69`, `OutRun/Views/SwiftUI/Onboarding/OnboardingView.swift:122`, `OutRun/Views/SwiftUI/Onboarding/OnboardingView.swift:193`.
- Workout detail uses fixed sizes: `OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift:105`, `OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift:110`, `OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift:252`.
- UIKit code uses fixed `UIFont.systemFont`: `OutRun/Controllers/General/DetailViewController.swift:32` and `OutRun/Views/Workout/NewWorkoutControllerActionButton.swift:125`.
- Several icon-only close buttons lack explicit accessibility labels: `OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift:41`, `OutRun/Views/SwiftUI/Debug/DebugView.swift:70`, `OutRun/Views/SwiftUI/PolicyView.swift:40`, and `OutRun/Views/SwiftUI/ChangelogView.swift:27`.

Recommendation:
- Replace most fixed SwiftUI font sizes with semantic fonts or `.font(.system(..., relativeTo: ...))`.
- Use `UIFontMetrics` or preferred fonts for UIKit labels/buttons.
- Add explicit labels for icon-only controls such as "Close" and "Expand map".
- Run with extra-large Dynamic Type and VoiceOver after changes.

### Migration Testing Is Essentially Absent

The app has code-based CoreStore migrations and user health data, but the only test file is still template content.

Evidence:
- Only one app test file was found: `UnitTests/MigrationTests.swift`.
- `UnitTests/MigrationTests.swift:33` has template `testExample()` with no assertions.
- `UnitTests/MigrationTests.swift:41` has template `testPerformanceExample()` with an empty measured block.
- `OutRun/Models/Data/DataModels/Versions/OutRunV4.swift:77` force-casts `heartRate` during migration: `sourceObject["heartRate"] as! Double`.

Recommendation:
- Replace the template tests with fixture-backed migrations for V1 -> V4 and V3to4 -> V4.
- Cover nil/malformed old values where possible, especially heart-rate conversion.
- Add tests for backup import versions V1 through V4.

### UIKit and App Infrastructure Need Main-Actor Isolation

UIKit classes and UI-facing app infrastructure are not annotated with `@MainActor`. This works today, but it is weak for Swift 6 strict concurrency and makes accidental off-main UI access easier.

Evidence:
- UIKit classes without `@MainActor` include `OutRun/Views/Data/LoadingView.swift:23`, `OutRun/Views/Data/LabelledDataView.swift:23`, `OutRun/Views/Workout/WorkoutActionView.swift:23`, `OutRun/Views/Workout/WorkoutBuilderTypeView.swift:23`, `OutRun/Views/Workout/WorkoutBuilderReadinessIndicationView.swift:23`, `OutRun/Views/Workout/NewWorkoutControllerActionButton.swift:23`, `OutRun/Views/ORBanner/ORBaseBanner.swift:23`, and `OutRun/Controllers/General/DetailViewController.swift:23`.
- SwiftUI models are modernizing well with `@Observable`, but UIKit/legacy components have not had the same isolation pass.

Recommendation:
- Add `@MainActor` to UIKit subclasses and UI-only helpers.
- Turn on stricter concurrency warnings incrementally and fix surfaced issues module by module.

## Medium

### Location Energy Settings Ignore the User's Accuracy Preference at the CLLocationManager Level

The recording path filters locations according to user preference, but the underlying `CLLocationManager` always requests best accuracy and background updates.

Evidence:
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:169` reads `UserPreferences.gpsAccuracy`.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:174` sets `locationManager.desiredAccuracy = kCLLocationAccuracyBest`.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:175` enables background location updates.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:179` enables automatic pause of location updates.
- `OutRun/Support Files/Info.plist:39` declares the `location` background mode.

Recommendation:
- Keep background location for active workouts, but map the user's GPS accuracy setting to `CLLocationManager.desiredAccuracy`.
- Consider lowering accuracy during pre-recording readiness and restoring higher accuracy only while actively recording.

### Map Image Size and Cache Keys Are Still Screen-Bounds Based

The map-image cache now exists and should keep startup fast. The remaining issue is that image size is derived from `UIScreen.main.bounds`, and cache keys only include workout UUID, size category, and appearance. This can be wrong for iPad split view, Stage Manager, rotation, larger phones, or any future responsive layout.

Evidence:
- `OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift:113` computes thumbnail width from `UIScreen.main.bounds.width`.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageSize.swift:29` and `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageSize.swift:33` compute render sizes from `UIScreen.main.bounds.width`.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageRequest.swift:30` builds cache identifiers from UUID, logical size, and appearance only.

Recommendation:
- Pass concrete layout size into `WorkoutMapImageRequest`.
- Include pixel size or point size plus scale in the cache identifier.
- Remove `UIScreen.main.bounds` from SwiftUI view sizing and use the parent layout width.

### Formatter Allocation Occurs in Render and Hot Formatting Paths

Several formatting helpers allocate `DateFormatter`, `MeasurementFormatter`, and `DateComponentsFormatter` on each call. This is not a top startup issue, but it can matter in timeline rows, detail stats, and live updates.

Evidence:
- `OutRun/Models/Formatting/CustomDateFormatting.swift:33`, `OutRun/Models/Formatting/CustomDateFormatting.swift:46`, `OutRun/Models/Formatting/CustomDateFormatting.swift:59`, `OutRun/Models/Formatting/CustomDateFormatting.swift:70`, and `OutRun/Models/Formatting/CustomDateFormatting.swift:77` allocate date formatters.
- `OutRun/Models/Formatting/CustomMeasurementFormatting.swift:27` allocates a `MeasurementFormatter`.
- `OutRun/Models/Formatting/CustomMeasurementFormatting.swift:48` allocates a `DateComponentsFormatter`.
- `OutRun/Models/Formatting/CustomMeasurementFormatting.swift:70` allocates another `MeasurementFormatter`.
- `OutRun/Views/SwiftUI/Settings/SettingsView.swift:233`, `OutRun/Views/SwiftUI/Settings/SettingsView.swift:239`, `OutRun/Views/SwiftUI/Settings/SettingsView.swift:245`, `OutRun/Views/SwiftUI/Settings/SettingsView.swift:251`, and `OutRun/Views/SwiftUI/Settings/SettingsView.swift:257` create `MeasurementFormatter()` in the view body path.

Recommendation:
- Prefer cached formatters or value-style `FormatStyle` where possible.
- Use `en_US_POSIX` locale for fixed date formats such as `yyyyMMdd` and backup filenames.
- Keep locale-sensitive display formatting separate from storage identifiers.

### Backup and Export Files Need Clearer Protection Semantics

Temporary backup/export files can include sensitive workout, location, and health-derived data. The code writes them to the temporary directory and relies on follow-up UI/export cleanup.

Evidence:
- `OutRun/Models/Data/Backup/BackupManager.swift:46` chooses `FileManager.default.temporaryDirectory`.
- `OutRun/Models/Data/Backup/BackupManager.swift:51` writes backup data without explicit protection options.
- `OutRun/Models/Data/ExportManager.swift:200` uses the temporary directory for GPX export.
- `OutRun/Models/Data/ExportManager.swift:203` through `OutRun/Models/Data/ExportManager.swift:205` writes GPX output.
- `OutRun/Views/SwiftUI/Settings/SettingsView.swift:160` and `OutRun/Views/SwiftUI/Settings/SettingsView.swift:166` attempt cleanup with `try?`.

Recommendation:
- Apply explicit file protection to generated backups/exports.
- Ensure temporary files are excluded from device backup if they can persist.
- Prefer do/catch cleanup with logging for failed cleanup of sensitive temp files.

### Policy Fetch Bypasses Normal URL Loading Cache

Policy text is fetched over HTTPS, which is good. The request explicitly ignores local and remote caches and creates a one-off session.

Evidence:
- `OutRun/Models/Settings/PolicyManager.swift:25` uses an HTTPS base URL.
- `OutRun/Models/Settings/PolicyManager.swift:38` sets `.reloadIgnoringLocalAndRemoteCacheData`.
- `OutRun/Models/Settings/PolicyManager.swift:40` creates a new `URLSession`.

Recommendation:
- Consider `URLSession.shared` or a static session and default cache policy.
- If policies must always be fresh, keep the current behavior but document that product requirement.

### Live Stats Uses Two One-Second Timers

Live stats now correctly uses `.autoconnect()` and `.common`, but it creates two independent 1-second publishers.

Evidence:
- `OutRun/Models/Workout/WorkoutBuilder/Components/LiveStats.swift:163` creates a duration timer.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LiveStats.swift:170` creates a burned-energy timer.

Recommendation:
- Use one shared timer publisher for both live-stat chains.
- If this area gets touched, consider whether a tolerance-bearing timer is practical without regressing map interaction behavior.

### Route Image Queue Uses Raw Dispatch Queue Suspension

The app-level scene-phase code balances suspend/resume with a `renderSuspended` flag, which avoids the worst issue. Still, `DispatchQueue.suspend()` / `resume()` is fragile as an app-state primitive.

Evidence:
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift:90` suspends queues.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift:97` resumes queues.
- `OutRun/Views/SwiftUI/Shell/OutRunApp.swift:30` tracks the balancing flag.
- `OutRun/Views/SwiftUI/Shell/OutRunApp.swift:37` handles scene-phase transitions.

Recommendation:
- Eventually replace queue suspension with an actor/operation queue state machine that stops accepting new render work while backgrounded and lets in-flight work finish or cancel explicitly.

## Low

### Debug View Uses `Task.detached`

The debug view moves database count/cache-size reads off the main actor using `Task.detached`. This is probably fine because it is debug-only UI and returns value data, but it is worth replacing with explicit async APIs over time.

Evidence:
- `OutRun/Views/SwiftUI/Debug/DebugView.swift:23` is `@MainActor`.
- `OutRun/Views/SwiftUI/Debug/DebugView.swift:93` uses `Task.detached`.
- `OutRun/Views/SwiftUI/Debug/DebugView.swift:101` through `OutRun/Views/SwiftUI/Debug/DebugView.swift:117` fetch CoreStore counts inside that detached task.

Recommendation:
- Replace with `DataManager` async debug-summary API.
- Add an accessibility label to the close button at `OutRun/Views/SwiftUI/Debug/DebugView.swift:70`.

### Application State Observation Is Weak and Mostly OK

The custom observer table uses weak observer references, so it is not a strong-retain leak. It does leave stale dictionary entries until the next state change if callers never call `stopObservingApplicationState()`.

Evidence:
- `OutRun/Models/ApplicationStateObservation.swift:25` stores `weak var observer`.
- `OutRun/Models/ApplicationStateObservation.swift:45` removes nil observers during state changes.
- `OutRun/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift:53` starts observing.
- No `WorkoutBuilder` deinit calls `stopObservingApplicationState()`, but weak storage prevents retention.

Recommendation:
- Low priority: add explicit `deinit { stopObservingApplicationState() }` to observer types for cleaner bookkeeping.

## Positive Findings

- No hardcoded secrets or credentials were found in the static scan.
- Policy network requests use HTTPS.
- The `http://www.topografix.com/GPX` strings in `Info.plist` are UTI reference URLs, not live app network endpoints.
- SwiftUI state modernization has started: key SwiftUI shells/models use `@Observable` rather than older `ObservableObject` patterns.
- `RootView` removes its `NotificationCenter` observer in deinit.
- Map image generation now has caching, deduplication, serialized rendering, and coordinate simplification. This matches the startup fix direction.
- `ApplicationStateObservation` uses weak references, so it should not retain workout builders.

## Recommended Implementation Order

1. Add and verify `PrivacyInfo.xcprivacy`.
2. Replace HealthKit `DispatchGroup.wait()` query bridges with async APIs.
3. Continue the snapshot/DTO pattern so SwiftUI and export/backup code do not rely on thread-confined CoreStore model objects.
4. Add real migration and backup import tests.
5. Do a Dynamic Type and icon-label accessibility pass.
6. Add `@MainActor` to UIKit subclasses and UI-only infrastructure, then enable stricter concurrency warnings.
7. Pass concrete map-image sizes through layout and include size/scale in cache keys.
8. Cache or modernize date/measurement formatters.
9. Tune location manager accuracy based on user preference and recording state.
10. Rework queue suspension and live-stat timers when nearby code is touched.

## Audit Notes

This was a static audit. I did not run Instruments, Energy Organizer, Accessibility Inspector, or full UI automation in this pass. Those should be the next validation layer after the code-level backlog above is reduced.
