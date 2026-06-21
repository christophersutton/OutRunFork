# Axiom Audit Findings

Date: 2026-06-21

Scope: static audit of the iOS app after the startup performance fixes. Status notes below track follow-up fixes made on 2026-06-21.

## Skills Used

- `axiom-health-check`
- `axiom-swift-performance`
- `axiom-swiftui-performance`
- `axiom-audit-swiftui-architecture`
- `axiom-audit-swiftui-layout`
- `axiom-audit-swiftui-nav`
- `axiom-audit-concurrency`
- `axiom-swift-concurrency`
- `axiom-audit-core-data`
- `axiom-audit-storage`
- `axiom-audit-memory`
- `axiom-audit-accessibility`
- `axiom-audit-codable`
- `axiom-networking`
- `axiom-audit-energy`
- `axiom-scan-security-privacy`
- `axiom-modernize`
- `axiom-audit-testing`
- `axiom-audit-ux-flow`
- `axiom-timer-patterns`

Skills not applied after signal scan: camera, CloudKit/iCloud, SpriteKit, TextKit, StoreKit/IAP, push notifications, foundation models, and App Intents. A focused networking pass was later applied to the small HTTPS policy fetch/cache behavior; the app has no broader networking layer.

## Executive Summary

Startup appears fixed. I did not find another startup-class blocker after the previous changes and the confirmed fast launch. Most initially high-risk audit items now have focused fixes and regression tests. The remaining high-value work is broadening the partially addressed areas: CoreStore snapshot/DTO coverage, Dynamic Type and fixed-font accessibility, full historical migration/backup import coverage, wider Swift 6 actor isolation, and on-device location-energy validation.

The map-image work is in a much better place now: requests are cached, deduplicated, queued, rendered off the startup path, measured from concrete layout size, and keyed by size/scale/appearance.

## Critical

### Missing Privacy Manifest

Status: Addressed 2026-06-21. Added `OutRun/Support Files/PrivacyInfo.xcprivacy`, wired it into the app resources phase, and added `UnitTests/PrivacyManifestTests.swift`.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-privacy-red -only-testing:UnitTests/PrivacyManifestTests -resultBundlePath /tmp/outrun-main-privacy-red.xcresult` failed because `OutRun.app` did not include `PrivacyInfo.xcprivacy`.
- Green: the same test passed with 1 selected test and 0 failures after adding the manifest.

Original finding: there was no `PrivacyInfo.xcprivacy` in the repository. That App Store readiness issue is now closed for the audited required-reason API categories.

Evidence:
- Fixed: `OutRun/Support Files/PrivacyInfo.xcprivacy` is now present and copied into the app resources.
- `OutRun/Models/Preferences/UserPreference.swift:43` uses `UserDefaults.standard.set`.
- `OutRun/Models/Preferences/UserPreference.swift:55` removes UserDefaults values.
- `OutRun/Models/Preferences/UserPreference.swift:59` reads from UserDefaults.
- `OutRun/Models/Preferences/UserPreferences.swift:50` removes the app UserDefaults domain.
- File APIs are also present in backup/export/cache-size paths, including `OutRun/Models/Data/Backup/BackupManager.swift:46`, `OutRun/Models/Data/Backup/BackupManager.swift:51`, `OutRun/Models/Data/ExportManager.swift:200`, `OutRun/Extensions/URL.swift:26`, and `OutRun/Extensions/FileManager.swift:42`.

Recommendation:
- No further code action for the audited manifest slice.
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

Status: Partially addressed 2026-06-21. Removed the synchronous `threadSafeSyncReturn` bridge from `DataManager.queryExistingHealthUUIDs` and converted its HealthKit observer/import call sites to the new completion-based API. Additional backup/export DTO hardening now makes the CoreStore model `asTemp` conversions for `Workout`, `Event`, `WorkoutPause`, `WorkoutEvent`, `WorkoutRouteDataSample`, and `WorkoutHeartRateDataSample` read raw `_x.value` storage on the transaction queue. The same backup/export pass also fixed current `BackupV4` exports so they advertise the V4 schema instead of a stale V3 version tag. The broader public model accessor debt remains and should continue through snapshot/DTO expansion.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-corestore-red -only-testing:UnitTests/HealthKitBlockingQueryTests/testHealthUUIDQueryPathDoesNotUseSynchronousMainHops -resultBundlePath /tmp/outrun-main-corestore-red.xcresult` failed with the expected 3 assertions against `DataManager+Query.swift`, `HealthStoreManager+Observer.swift`, and `HealthStoreManager+Query.swift`.
- Green: the same selected test passed with 1 test and 0 failures after the async CoreStore query change.
- Regression class: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-corestore-class -only-testing:UnitTests/HealthKitBlockingQueryTests -resultBundlePath /tmp/outrun-main-corestore-class.xcresult` passed with 2 tests and 0 failures.
- Backup/export DTO red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:UnitTests/CoreStoreTempConversionThreadingTests -resultBundlePath /tmp/outrun-corestore-asTemp-red3.xcresult` failed with 51 expected source-shape assertions against public getter usage in the six CoreStore `asTemp` conversions.
- Backup/export DTO green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:UnitTests/CoreStoreTempConversionThreadingTests -resultBundlePath /tmp/outrun-corestore-asTemp-green2.xcresult` passed with 1 selected test and 0 failures after the conversions switched to raw `_x.value` reads.
- Adversarial backup-version red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-corestore-asTemp-orchestrator -resultBundlePath /tmp/outrun-backup-version-red1.xcresult -only-testing:UnitTests/CoreStoreTempConversionThreadingTests/testCurrentBackupEncodingUsesV4VersionCode` failed because current backup JSON encoded `"version": "V3"`.
- Orchestrator green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-corestore-asTemp-orchestrator -resultBundlePath /tmp/outrun-corestore-asTemp-orchestrator2.xcresult -only-testing:UnitTests/CoreStoreTempConversionThreadingTests` passed with 2 selected tests and 0 failures after `BackupV4` switched to `BackupV4.versionCode`.
- Combined audit regression: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-audit-slices-green14 -resultBundlePath /tmp/outrun-audit-slices-green14-corestore-backup.xcresult -only-testing:UnitTests` passed with 43 tests and 0 failures after the backup/export DTO guard and V4 backup-version fix.
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
- Backup/export DTO conversion now bypasses those public getters: `OutRun/Models/Data/DataModels/Workout.swift`, `Event.swift`, `WorkoutPause.swift`, `WorkoutEvent.swift`, `WorkoutRouteDataSample.swift`, and `WorkoutHeartRateDataSample.swift` read raw `_x.value` storage inside their `asTemp` implementations.
- `OutRun/Models/Data/Backup/Backup.swift` now writes `BackupV4.versionCode` for current backups, matching the `typealias Backup = BackupV4` export schema.
- `UnitTests/CoreStoreTempConversionThreadingTests.swift` guards the backup/export conversion path by rejecting public getter tokens in those six `asTemp` bodies while requiring raw `.value` reads, and by asserting current backup JSON advertises version `V4`.
- Fixed previously: `DataManager.queryExistingHealthUUIDs(completion:)` now uses asynchronous CoreStore attribute queries instead of the old main-thread-only `threadSafeSyncReturn` path.

Recommendation:
- Keep the value-snapshot pattern introduced for timeline/detail and expand it.
- Avoid passing CoreStore `Workout`/`Event` objects to SwiftUI and formatting layers.
- Add async query APIs for common needs such as existing HealthKit UUIDs, backup data, route summaries, and export inputs.

### Dynamic Type and Accessibility Debt Is Broad

Status: Partially addressed 2026-06-21. Added explicit localized `LS["Close"]` accessibility labels to the icon-only dismiss buttons in workout detail, debug, policy, and changelog SwiftUI screens, and added `UnitTests/CloseButtonAccessibilityTests.swift` to keep those labels on the `Button` views. A follow-up Dynamic Type source-shape slice now converts curated audited text fonts in onboarding, timeline, workout detail, policy/changelog, shell loading/tab labels, and selected UIKit controls to semantic/preferred fonts.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-main-accessibility-red -only-testing:UnitTests/CloseButtonAccessibilityTests -resultBundlePath /tmp/outrun-main-accessibility-red.xcresult` failed with the expected 4 assertions for the unlabeled close buttons.
- Green: the same selected test passed with 1 test and 0 failures after adding button-level labels.
- Static: `plutil -lint OutRun.xcodeproj/project.pbxproj` and `git diff --check` passed for the touched accessibility/test/project files.
- Adversarial review blocked the first test draft because it only checked for nearby labels, not labels applied to the `Button`. The merged test now requires button-level labeled snippets.
- Dynamic Type red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-dynamic-type-red -only-testing:UnitTests/DynamicTypeFontShapeTests` failed on 33 fixed text-font violations.
- Dynamic Type green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-dynamic-type-green -only-testing:UnitTests/DynamicTypeFontShapeTests` passed with 1 selected test and 0 failures.
- Regression: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-dynamic-type-unittests -only-testing:UnitTests` passed with 47 tests and 0 failures.

The SwiftUI replacement surfaces and legacy UIKit views had many fixed font sizes, risking clipping, poor Large Content Size behavior, and inconsistent VoiceOver output. This slice addresses the audited text-font matches but did not perform visual/manual VoiceOver validation.

Evidence:
- Fixed: audited SwiftUI text fonts in onboarding, timeline, workout detail, policy/changelog, and shell surfaces now use semantic fonts such as `.body`, `.title2`, `.subheadline`, `.caption`, and `.caption2`.
- Fixed: `OutRun/Controllers/General/DetailViewController.swift` now uses `UIFont.preferredFont(forTextStyle: .largeTitle)` and enables `adjustsFontForContentSizeCategory` on the headline label.
- Fixed: `OutRun/Views/Workout/NewWorkoutControllerActionButton.swift` now uses `UIFont.preferredFont(forTextStyle: .headline)` and enables Dynamic Type adjustment on button title labels.
- Fixed: `OutRun/Extensions/UIKit/UISegmentedControl.swift` now uses a preferred caption font for segmented title attributes.
- Guarded: `UnitTests/DynamicTypeFontShapeTests.swift` scans the curated audited files for fixed text font APIs while explicitly allowlisting intentional brand/composite display text and symbol-only icon sizing.
- Fixed previously: the icon-only dismiss buttons in `OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift`, `OutRun/Views/SwiftUI/Debug/DebugView.swift`, `OutRun/Views/SwiftUI/PolicyView.swift`, and `OutRun/Views/SwiftUI/ChangelogView.swift` now carry explicit localized Close labels on the `Button` views.

Recommendation:
- Keep future text font additions on semantic SwiftUI fonts or UIKit preferred/scaled fonts.
- Keep explicit labels on icon-only controls such as "Close" and "Expand map".
- Run with extra-large Dynamic Type and VoiceOver after changes; this static source-shape slice does not prove every layout remains usable at accessibility sizes.

### Migration Testing Is Essentially Absent

Status: Partially addressed 2026-06-21. Replaced the template `UnitTests/MigrationTests.swift` content with fixture-backed CoreStore migration coverage for the V3to4 -> V4 heart-rate conversion. `OutRunV4` no longer force-casts legacy `heartRate` values; malformed or unsupported persisted values now migrate to the required V4 `Int` field as `0` instead of crashing or silently dropping the destination row. A focused V3 backup-import fix now maps legacy non-pause workout events with the same `eventType - 4` semantics as the CoreStore V3to4 migration instead of crashing. Full historical V1/V2/V3 chain coverage and broader backup import version coverage remain open.

Validation:
- Red: the migration slice initially failed against the force-cast/guard regression class; after a stale overwrite was detected, static checks again exposed the old `guard let heartRate`, optional helper result, and `return nil` patterns before repair.
- Green: the final selected audit run at `/tmp/outrun-audit-slices-green2.xcresult` passed with 14 selected tests and 0 failures, including all 4 `MigrationTests`.
- Static: `rg -n "guard let heartRate|-> Int\\?|return nil|as! Double|unsafeRemoveAllPersistentStoresAndWait|SkipsMalformed|XCTAssertNil|ValidatesHeartRateBeforeCreatingDestinationObject" OutRun/Models/Data/DataModels/Versions/OutRunV4.swift UnitTests/MigrationTests.swift` found no stale migration patterns after repair.
- V3 backup-event red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-v3-backup-events-red-workspace -only-testing:UnitTests/MigrationTests/testTempV3BackupWorkoutEventConversionMatchesV3ToV4MigrationShape -resultBundlePath /tmp/outrun-v3-backup-events-red-workspace.xcresult` failed with the expected `fatalError()` and missing `eventType - 4` assertions.
- V3 backup-event green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-v3-backup-events-orchestrator2 -resultBundlePath /tmp/outrun-v3-backup-events-orchestrator2.xcresult -only-testing:UnitTests/MigrationTests/testTempV3BackupWorkoutEventConversionMatchesV3ToV4MigrationShape -only-testing:UnitTests/MigrationTests/testTempV3BackupWorkoutEventConversionMapsLegacyNonPauseEvents -only-testing:UnitTests/MigrationTests/testTempV3BackupWorkoutConversionKeepsPauseEventsOutOfWorkoutEvents` passed with 3 selected tests and 0 failures.
- Combined audit regression: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-audit-slices-green16 -resultBundlePath /tmp/outrun-audit-slices-green16-v3-backup-events.xcresult -only-testing:UnitTests` passed with 46 tests and 0 failures.
- Adversarial review rejected an earlier source-only implementation. The merged test now proves migration behavior by corrupting the raw SQLite `ZWORKOUTHEARTRATESAMPLE.ZHEARTRATE` value before opening through the V4 chain.

The app has code-based CoreStore migrations and user health data. The current tests now cover the V3to4 -> V4 heart-rate conversion path, but broader historical migration coverage is still thin.

Evidence:
- `UnitTests/MigrationTests.swift` now seeds a real V3to4 CoreStore SQLite store, opens it through the V4 migration chain, and asserts migrated heart-rate samples.
- `UnitTests/MigrationTests.swift` covers supported `Double` and `NSNumber` conversion, unsupported `nil`/string helper inputs, and a malformed persisted SQLite value that now migrates to `[0]`.
- `OutRun/Models/Data/DataModels/Versions/OutRunV4.swift` converts supported legacy values and defaults unsupported values to `0` without force-casting.
- `OutRun/Models/Data/Temp/Versions/TempV3.swift` now converts V3 backup workout events using `eventType - 4`, so legacy values 4/5/6 become lap/marker/segment and higher values become `.unknown` instead of crashing.
- `UnitTests/MigrationTests.swift` guards the V3 backup workout-event source shape, runtime conversion for 4, 5, 6, and an unknown high value, and the `Workout.asTemp` import path that excludes pause/resume values from `workoutEvents`.
- Missing coverage remains for full V1/V2/V3 -> V4 migration fixtures and backup import versions V1 through V4 beyond this focused V3 workout-event slice.

Recommendation:
- Extend the fixture-backed migration tests to V1 -> V4 and intermediate historical versions, not only V3to4 -> V4.
- Keep covering nil/malformed old values where possible, especially required-field conversions.
- Add tests for backup import versions V1 through V4.

### UIKit and App Infrastructure Need Main-Actor Isolation

UIKit classes and UI-facing app infrastructure are not annotated with `@MainActor`. This works today, but it is weak for Swift 6 strict concurrency and makes accidental off-main UI access easier.

Status: Partially addressed 2026-06-21. Added declaration-level `@MainActor` to the eight UIKit classes called out below and added a focused regression test that locks that audit list. Broader UI infrastructure isolation, including queue/helper types, remains open.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-mainactor-red -only-testing:UnitTests/MainActorIsolationTests` reported 1 selected test with 8 expected failures, one for each unannotated class.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-mainactor-current -only-testing:UnitTests/MainActorIsolationTests -resultBundlePath /tmp/outrun-mainactor-current.xcresult` passed with 1 selected test and 0 failures.
- Build: `xcodebuild build -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-final-build` succeeded from the final source state after generated `/tmp/outrun-*` derived-data cleanup.
- Adversarial review found no blockers for this slice; it noted the string-based test is intentionally narrow. Residual manual smoke risk remains around workout completion banner save/dismiss/continue and map-type selection because some UI calls now cross into `Task { @MainActor in ... }` closures.

Evidence:
- UIKit classes now annotated with `@MainActor` include `OutRun/Views/Data/LoadingView.swift:23`, `OutRun/Views/Data/LabelledDataView.swift:23`, `OutRun/Views/Workout/WorkoutActionView.swift:23`, `OutRun/Views/Workout/WorkoutBuilderTypeView.swift:23`, `OutRun/Views/Workout/WorkoutBuilderReadinessIndicationView.swift:23`, `OutRun/Views/Workout/NewWorkoutControllerActionButton.swift:23`, `OutRun/Views/ORBanner/ORBaseBanner.swift:23`, and `OutRun/Controllers/General/DetailViewController.swift:23`.
- `UnitTests/MainActorIsolationTests.swift` verifies the audit list remains explicitly annotated immediately before the class declarations.
- Supporting compile fixes isolate UI-facing methods in `ORBannerQueue` and `WorkoutCompletionActionHandler`, and hop map-type/action-handler UI updates back to the main actor from async closures.
- SwiftUI models are modernizing well with `@Observable`, but UIKit/legacy components have not had the same isolation pass.

Recommendation:
- Add `@MainActor` to UIKit subclasses and UI-only helpers.
- Turn on stricter concurrency warnings incrementally and fix surfaced issues module by module.

## Medium

### Location Energy Settings Ignore the User's Accuracy Preference at the CLLocationManager Level

Status: Partially addressed 2026-06-21. `LocationManagement.prepare()` now maps explicit `UserPreferences.gpsAccuracy` meter values into both the route-filtering threshold and `CLLocationManager.desiredAccuracy`. The standard `nil` mode keeps the prior adaptive behavior by requesting `kCLLocationAccuracyBest` from Core Location while adapting the route filter locally, and the `-1` off sentinel now disables location updates and marks the component ready. Added `UnitTests/LocationAccuracyPreferenceTests.swift` for these mappings. On-device energy profiling and pre-recording-vs-active accuracy tuning remain open.

Validation:
- Red: an initial selected test run with `LocationAccuracyPreferenceTests` wired into `UnitTests` failed to compile because `LocationManagement.locationManagerDesiredAccuracy(forGPSAccuracyPreference:)` and `LocationManagement.routeFilteringAccuracy(forGPSAccuracyPreference:)` did not exist.
- Green: the final selected audit run at `/tmp/outrun-audit-slices-green2.xcresult` passed with 14 selected tests and 0 failures, including all 5 `LocationAccuracyPreferenceTests`.
- Adversarial review rejected the first `nil -> 20` manager-accuracy mapping because it weakened the existing standard/adaptive mode. The merged version preserves standard mode as `kCLLocationAccuracyBest`, applies explicit meter tiers to the manager, and disables updates for `-1`.

Before this fix, the recording path filtered locations according to user preference, but the underlying `CLLocationManager` always requested best accuracy and background updates.

Evidence:
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:42` maps `-1` to disabled Core Location updates.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:46` maps `nil` to the default 20-meter route filter and `-1` to disabled filtering.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:51` maps explicit preferences to the `CLLocationManager` desired accuracy while preserving `kCLLocationAccuracyBest` for standard adaptive mode.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:57` stops location updates and marks the component ready when GPS is off.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:194` reads `UserPreferences.gpsAccuracy` into the route filter.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:205` applies the mapped value to `locationManager.desiredAccuracy` when updates are enabled.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:209` still enables background location updates for active location tracking.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift:213` enables automatic pause of location updates.
- `OutRun/Support Files/Info.plist:39` declares the `location` background mode.

Recommendation:
- Keep background location for active workouts, and validate the new manager-level accuracy mapping on device with an energy trace.
- Consider lowering accuracy during pre-recording readiness and restoring higher accuracy only while actively recording.

### Map Image Size and Cache Keys Are Still Screen-Bounds Based

Status: Addressed 2026-06-21. `WorkoutTimelineRow` now measures its card container with `onGeometryChange` and requests route thumbnails at half of that measured card width only when the snapshot has route data. `WorkoutMapImageRequest` now carries the concrete point size, display scale, and requested appearance; cache identifiers and request equality include UUID, logical size, point size, scale, and appearance. `WorkoutMapImageManager` renders snapshots using the request's point size and scale instead of screen globals, and its coalescing path preserves high-priority requests, dark/light follow-up requests, and already-running renders without dropping completions or duplicating work.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-map-size-red2 -only-testing:UnitTests/WorkoutMapImageRequestTests -resultBundlePath /tmp/outrun-map-size-red2.xcresult` failed to compile because `WorkoutMapImageRequest` did not yet accept `pointSize`, `scale`, or `usesDarkAppearance`.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-map-size-green5 -only-testing:UnitTests/WorkoutMapImageRequestTests -resultBundlePath /tmp/outrun-map-size-green5.xcresult` passed with 7 selected tests and 0 failures after adversarial review corrections.
- Build: `xcodebuild build -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-map-size-build2` succeeded.
- Static: `plutil -lint OutRun.xcodeproj/project.pbxproj` and `git diff --check` passed. `grep -R "UIScreen.main.bounds\\|UIScreen.main.scale" OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageSize.swift OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageRequest.swift OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift` found no forbidden screen sizing calls.

The map-image cache now exists and should keep startup fast. The resolved issue was that image size was derived from `UIScreen.main.bounds`, and cache keys only included workout UUID, size category, and appearance. That could be wrong for iPad split view, Stage Manager, rotation, larger phones, or any future responsive layout.

Evidence:
- `OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift` derives route thumbnail size from the measured card width rather than `UIScreen.main.bounds`.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageRequest.swift` stores concrete `pointSize`, `scale`, and `usesDarkAppearance` and includes them in cache identity/equality.
- `OutRun/Models/Data/Snapshots/WorkoutSnapshot.swift` carries `hasRouteData` so route-less timeline rows do not enter the map image queue.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift` passes `request.pointSize` and `request.scale` to `MKMapSnapshotter.Options` and the renderer, and drains coalesced completions from a main-queue finish path.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageQueue.swift` promotes pending duplicate high-priority requests while excluding the currently running request from duplicate promotion.
- `UnitTests/WorkoutMapImageRequestTests.swift` covers cache identifier/equality separation, route-data gating, high-priority promotion, in-flight promotion exclusion, dark-mode requeue coalescing, and the absence of screen-bound map/timeline sizing.

Recommendation:
- No further action for this slice. Continue using concrete layout sizes for any future map-image call sites.

### Formatter Allocation Occurs in Render and Hot Formatting Paths

Status: Addressed 2026-06-21; adversarial review fix applied. `CustomDateFormatting` and `CustomMeasurementFormatting` now guard every shared cached `DateFormatter`, `MeasurementFormatter`, and `DateComponentsFormatter` parse/string operation with formatter locks. Fixed day identifiers and backup filenames use cached `en_US_POSIX` + Gregorian formatters, while display formatters remain locale-sensitive. `dayIDFormat` is now immutable so the cached day-identifier formatter cannot desynchronize from a mutable format string.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-formatter-red -only-testing:UnitTests/FormatterAllocationTests -resultBundlePath /tmp/outrun-formatter-red.xcresult` failed with 7 expected assertions for per-call formatter allocation patterns and missing `en_US_POSIX` fixed-date formatting.
- Adversarial review red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/outrun-formatter-threadsafe -only-testing:UnitTests/FormatterAllocationTests -resultBundlePath /tmp/outrun-formatter-threadsafe.xcresult` failed before build because the destination was ambiguous across simulator runtimes; rerun by UUID.
- Review-fix red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-formatter-threadsafe2 -only-testing:UnitTests/FormatterAllocationTests -resultBundlePath /tmp/outrun-formatter-threadsafe2.xcresult` built and ran, then failed 6 assertions because the strengthened tests exposed unpinned Gregorian fixed-date formatting and corrected Foundation positional padding expectations.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-formatter-threadsafe3 -only-testing:UnitTests/FormatterAllocationTests -resultBundlePath /tmp/outrun-formatter-threadsafe3.xcresult` passed with 6 selected tests and 0 failures.
- Static: `rg -n 'let dateFormatter = DateFormatter\\(\\)|let formatter = MeasurementFormatter\\(\\)|let timeFormatter = DateComponentsFormatter\\(\\)|MeasurementFormatter\\(\\)\\.string\\(from:' OutRun/Models/Formatting/CustomDateFormatting.swift OutRun/Models/Formatting/CustomMeasurementFormatting.swift OutRun/Views/SwiftUI/Settings/SettingsView.swift OutRun/Views/SwiftUI/Settings/UnitSelectionView.swift` found no matches.
- Static: `rg -n 'formatterLock|en_US_POSIX|gregorianCalendar|static let dayIDFormat' OutRun/Models/Formatting/CustomDateFormatting.swift OutRun/Models/Formatting/CustomMeasurementFormatting.swift` found the expected locks, fixed-date locale/calendar, and immutable day format.

Evidence:
- `UnitTests/FormatterAllocationTests.swift` now scopes static allocation checks to audited hot helper bodies/render paths so static factory initialization remains allowed.
- `UnitTests/FormatterAllocationTests.swift` covers deterministic fixed day identifiers and backup time codes, default unit-label parity for Settings/UnitSelection units, positional clock/pace strings, and concurrent formatter-helper stress calls.
- `OutRun/Models/Formatting/CustomDateFormatting.swift` locks shared display and fixed-date formatter operations, keeps display formatting locale-sensitive, and pins fixed storage/backup formatters to POSIX locale + Gregorian calendar.
- `OutRun/Models/Formatting/CustomMeasurementFormatting.swift` locks shared measurement/unit/clock/pace formatter string operations.

Recommendation:
- No further action for this slice. Remaining risk is that cached display Foundation formatters retain locale settings after in-app locale changes; if the app adds live locale switching, refresh these display caches or use value-style `FormatStyle` for display-only paths.

### Backup and Export Files Need Clearer Protection Semantics

Status: Addressed 2026-06-21. Added `TemporaryExportFileProtection` for generated temporary export files. `.orbup` writes now use explicit `.completeFileProtectionUntilFirstUserAuthentication` data-write options and post-write protection attributes, while CoreGPX-created `.gpx` files receive matching file-protection attributes after creation and before sharing. Both paths mark generated URLs as excluded from device backup. If post-write protection or backup-exclusion metadata fails, the generated temporary export is removed and cleanup failures are logged. Settings backup cleanup still uses logged `do`/`catch` removal instead of `try?`, without changing the share-sheet lifecycle.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-temp-export-protection-red -only-testing:UnitTests/TemporaryExportFileProtectionTests -resultBundlePath /tmp/outrun-temp-export-protection-red.xcresult` failed with 4 selected tests, 7 expected failures, and 0 passing assertions for the missing helper, plain backup write, unprotected GPX export, and `try?` Settings cleanup.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-temp-export-protection-review2 -only-testing:UnitTests/TemporaryExportFileProtectionTests -resultBundlePath /tmp/outrun-temp-export-protection-review2.xcresult` passed with 5 selected tests and 0 failures, including runtime file-protection and backup-exclusion attribute checks.
- Static: `plutil -lint OutRun.xcodeproj/project.pbxproj`, `git diff --check`, and `! rg -n "try\\? FileManager\\.default\\.removeItem\\(at: url\\)|try data\\.write\\(to: url\\)" OutRun/Models/Data/Backup/BackupManager.swift OutRun/Views/SwiftUI/Settings/SettingsView.swift` passed.

Evidence:
- `OutRun/Models/Data/TemporaryExportFileProtection.swift` writes temporary export data with `.completeFileProtectionUntilFirstUserAuthentication`, sets `FileAttributeKey.protectionKey` to `FileProtectionType.completeUntilFirstUserAuthentication`, applies `URLResourceValues.isExcludedFromBackup = true`, and removes generated files if metadata application fails after creation.
- `OutRun/Models/Data/Backup/BackupManager.swift` now writes generated `.orbup` files through `TemporaryExportFileProtection.write(data:to:)`.
- `OutRun/Models/Data/ExportManager.swift` now calls `TemporaryExportFileProtection.protectExistingTemporaryExportFile(at:)` on each CoreGPX-created `.gpx` before appending the URL for sharing.
- `OutRun/Views/SwiftUI/Settings/SettingsView.swift` now routes temporary backup removal through `cleanupTemporaryBackup(at:)`, which logs cleanup failures via `do`/`catch`.
- `UnitTests/TemporaryExportFileProtectionTests.swift` covers the backup write path, GPX post-write protection/backup exclusion path, Settings cleanup semantics, cleanup-on-metadata-failure expectations, and runtime protection/backup-exclusion attributes for a temp export file.

Recommendation:
- No further action for this slice. The chosen protection level protects files until first user authentication after boot while avoiding common share/export breakage after the device has been unlocked.

### Policy Fetch Bypasses Normal URL Loading Cache

Status: Addressed 2026-06-21. `PolicyManager` still fetches policy text over HTTPS, now leaves requests on the default protocol cache policy, and reuses a static `URLSession.shared` session instead of creating and invalidating a one-off session per query.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -only-testing:UnitTests/PolicyManagerNetworkingTests/testPolicyFetchUsesHTTPSDefaultCachePolicyAndReusableSession` failed with 5 expected assertions against the previous cache-bypassing implementation.
- Green: the same focused test passed after the networking fix.

Policy text is fetched over HTTPS and now uses normal URL loading cache behavior with a shared reusable session.

Evidence:
- `OutRun/Models/Settings/PolicyManager.swift` uses an HTTPS base URL.
- `OutRun/Models/Settings/PolicyManager.swift` no longer sets `.reloadIgnoringLocalAndRemoteCacheData` or any explicit `request.cachePolicy` for policy fetches.
- `OutRun/Models/Settings/PolicyManager.swift` reuses a static `URLSession.shared` session and no longer calls `finishTasksAndInvalidate()` after each policy query.
- `UnitTests/PolicyManagerNetworkingTests.swift` guards the HTTPS/default-cache/reusable-session behavior.

Recommendation:
- No further action for this slice unless product requirements later demand a documented freshness override.

### Live Stats Uses Two One-Second Timers

Status: Addressed 2026-06-21. `LiveStats` now creates one shared 1-second timer publisher for duration and burned-energy readouts. The timer remains on `.main` / `.common`, still uses `.autoconnect()`, and adds a 0.1-second tolerance before sharing the autoconnected publisher between both chains.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-live-stats-timer-red -only-testing:UnitTests/LiveStatsTimerTests -resultBundlePath /tmp/outrun-live-stats-timer-red.xcresult` failed with 1 selected test and 6 expected assertions against the two independent timer publishers.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-live-stats-timer-green -only-testing:UnitTests/LiveStatsTimerTests -resultBundlePath /tmp/outrun-live-stats-timer-green.xcresult` passed with 1 selected test and 0 failures.

Evidence:
- `OutRun/Models/Workout/WorkoutBuilder/Components/LiveStats.swift` defines `liveStatsTimer` once with `Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect().share()`.
- `OutRun/Models/Workout/WorkoutBuilder/Components/LiveStats.swift` uses that shared `liveStatsTimer` for both the duration and burned-energy `combineLatest` chains without changing their existing mappers.
- `UnitTests/LiveStatsTimerTests.swift` guards against returning to two `Timer.publish` calls and requires `.common`, `.autoconnect()`, `.share()`, the tolerance, and both chains subscribing to the shared local.

Recommendation:
- No further action for this slice. Keep future live-stat periodic readouts on the same shared timer unless a different cadence is explicitly required.

### Route Image Queue Uses Raw Dispatch Queue Suspension

Status: Addressed 2026-06-21. `WorkoutMapImageManager` no longer suspends or resumes its dispatch queues. Backgrounding now flips the existing logical `internalStatus == .suspended` gate so queued renders remain pending while an already-running render may finish normally. The manager's suspend/resume entry points are idempotent, so callers no longer need to balance raw dispatch suspension counts.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-map-suspension-red -only-testing:UnitTests/MapImageRenderSuspensionTests` failed with 2 selected tests and 8 expected assertions against the raw queue suspension implementation and stale app comment.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-map-suspension-green -only-testing:UnitTests/MapImageRenderSuspensionTests` passed with 2 selected tests and 0 failures.

Evidence:
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift` keeps `executeNextInQueue()` gated by `internalStatus == .suspended`.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift` now makes `suspendRenderProcess()` return early when already suspended and only sets `internalStatus = .suspended`.
- `OutRun/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift` now makes `resumeRenderProcess()` return early unless currently suspended and only sets `internalStatus = .idle`.
- `OutRun/Views/SwiftUI/Shell/OutRunApp.swift` keeps the scene-phase `renderSuspended` flag for redundant-call avoidance without documenting raw dispatch over-resume trap avoidance.
- `UnitTests/MapImageRenderSuspensionTests.swift` guards against reintroducing `processQueue.suspend()`, `snapshotQueue.suspend()`, `processQueue.resume()`, or `snapshotQueue.resume()` and checks the logical/idempotent source behavior.

Recommendation:
- No further action for this slice. Keep future background render throttling on logical state gates rather than raw dispatch queue suspension.

## Low

### Debug View Uses `Task.detached`

Status: Addressed 2026-06-21. `DebugView.loadValues()` now uses structured async flow through `DataManager.debugSummary()`. CoreStore counts, database disk-size reads, and map-cache disk-size reads happen inside CoreStore asynchronous transaction work; SwiftUI receives only sendable value data.

The debug view moved database count/cache-size reads off the main actor using `Task.detached`. This was probably fine because it is debug-only UI and returned value data, but it was worth replacing with explicit async APIs over time.

Evidence:
- `OutRun/Views/SwiftUI/Debug/DebugView.swift` is `@MainActor`.
- Fixed: `DebugView.loadValues()` now awaits `DataManager.debugSummary()` using structured async flow and no `Task.detached`.
- Fixed: `DebugView.loadValues()` consumes the returned cache value and no longer reads `CustomImageCache.mapImageCache.diskSize` on the main actor.
- Fixed: `DataManager.debugSummary()` returns sendable value data and performs CoreStore count reads plus database/cache disk-size reads inside `dataStack.perform(asynchronous:)`.
- Fixed previously: the icon-only close button keeps `.accessibilityLabel(Text(LS["Close"]))`.

Validation:
- Red: added `UnitTests/DebugViewTaskTests.swift` to assert no `Task.detached`, no direct `DataManager.fetchCount` or `CustomImageCache.mapImageCache.diskSize` calls in `loadValues()`, and an explicit async DataManager debug-summary API backed by CoreStore async work.
- Review hardening: strengthened the source-slice test so the pre-`dataStack.perform(asynchronous:)` portion of `debugSummary()` cannot read `diskSize`, while the asynchronous closure must read both `DataManager.diskSize` and `CustomImageCache.mapImageCache.diskSize`.
- Green: focused workspace validation passed for `UnitTests/DebugViewTaskTests` with 1 selected test and 0 failures after `DataManager.DebugSummary` gained `cacheDiskSize` and `DebugView.loadValues()` consumed only returned value data.
- Regression: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-audit-slices-green12 -resultBundlePath /tmp/outrun-audit-slices-green12.xcresult ...` passed the combined audit pack with 41 selected tests and 0 failures, including `UnitTests/DebugViewTaskTests` and `UnitTests/ApplicationStateObservationTests`.

Recommendation:
- No further action for this slice. If Debug View gains more expensive maintenance controls, keep adding value-returning async APIs instead of reading CoreStore/file/cache state directly from SwiftUI.

### Application State Observation Is Weak and Mostly OK

Status: Addressed 2026-06-21. `WorkoutBuilder` now unregisters from `ApplicationStateObservation` in `deinit`, and the shared observer table is lock-protected so lifecycle cleanup and scene-phase delivery cannot race on the static registry.

The custom observer table uses weak observer references, so it is not a strong-retain leak. It does leave stale dictionary entries until the next state change if callers never call `stopObservingApplicationState()`.

Evidence:
- `OutRun/Models/ApplicationStateObservation.swift:25` stores `weak var observer`.
- `OutRun/Models/ApplicationStateObservation.swift:67` removes nil observers during state changes.
- `OutRun/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift:53` starts observing.
- Fixed: `OutRun/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift` now calls `stopObservingApplicationState()` from `deinit`.
- Fixed: `OutRun/Models/ApplicationStateObservation.swift` now wraps registry reads/writes with `observationsLock`, snapshots `activeObservers` while locked, then invokes callbacks after unlocking.

Validation:
- Red: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-appstate-red2 -only-testing:UnitTests/ApplicationStateObservationTests -resultBundlePath /tmp/outrun-appstate-red2.xcresult` failed because the observer table still had the `WorkoutBuilder` entry after release.
- Review hardening: the added registry-lock test failed until `ApplicationStateObservation` protected the shared static registry and released the lock before invoking observer callbacks.
- Green: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-app-state-observation-orchestrator -resultBundlePath /tmp/outrun-app-state-observation-orchestrator5.xcresult -only-testing:UnitTests/ApplicationStateObservationTests` passed with 3 selected tests and 0 failures.
- Regression: `xcodebuild test -workspace OutRun.xcworkspace -scheme OutRun -destination 'platform=iOS Simulator,id=D6C217FB-9E68-4CA2-B9FC-A5202C44A667' -derivedDataPath /tmp/outrun-audit-slices-green12 -resultBundlePath /tmp/outrun-audit-slices-green12.xcresult ...` passed the combined audit pack with 41 selected tests and 0 failures, including `UnitTests/ApplicationStateObservationTests`.

Recommendation:
- No further action for the known observer type. Future `ApplicationStateObserver` conformers should still pair `startObservingApplicationState()` with explicit stop/deinit cleanup so stale weak entries do not depend on the next state-change prune.

## Positive Findings

- No hardcoded secrets or credentials were found in the static scan.
- Policy network requests use HTTPS.
- The `http://www.topografix.com/GPX` strings in `Info.plist` are UTI reference URLs, not live app network endpoints.
- SwiftUI state modernization has started: key SwiftUI shells/models use `@Observable` rather than older `ObservableObject` patterns.
- `RootView` removes its `NotificationCenter` observer in deinit.
- Map image generation now has caching, deduplication, serialized rendering, and coordinate simplification. This matches the startup fix direction.
- `ApplicationStateObservation` uses weak references and `WorkoutBuilder` now unregisters in deinit, so it should not retain or keep stale entries for workout builders.

## Recommended Implementation Order

1. Continue the snapshot/DTO pattern so SwiftUI, export, backup, and formatting code do not rely on thread-confined CoreStore model objects.
2. Add full historical migration and backup import tests beyond the current V3to4 -> V4 fixture coverage.
3. Do the remaining Dynamic Type/fixed-font accessibility pass, especially larger content sizes in SwiftUI and UIKit surfaces.
4. Broaden `@MainActor` isolation to remaining UI infrastructure and then enable stricter concurrency warnings module by module.
5. Validate the new location accuracy mapping on device with an energy trace, especially pre-recording readiness versus active recording.
6. Consider bounded concurrency/progress handling for very large HealthKit imports and deletes.

## Audit Notes

This was a static audit. I did not run Instruments, Energy Organizer, Accessibility Inspector, or full UI automation in this pass. Those should be the next validation layer after the code-level backlog above is reduced.
