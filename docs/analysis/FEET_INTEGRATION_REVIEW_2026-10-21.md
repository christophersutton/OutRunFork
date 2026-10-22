# Feet integration review — October 21, 2026

Reviewed `3c2bdac..0440353` and the integration repairs in this commit. Read `AGENTS.md`, the release audit, recording repair handoff, migration handoff and fork audit. No SSH, native app build, simulator, phone, private application data, Nidra or worker access occurred. Main owns native builds and device validation.

## Confirmed defects repaired

1. **Recovery after onboarding:** Root only offered launch recovery through its existing-user permission/changelog path. `completeOnboarding()` now also schedules recovery after storage is ready. The delayed presentation rechecks checkpoint existence, ends when a recording (including one underneath an alert) is already open, and refuses to present over another modal or a controller already presenting. Late launch callbacks cannot open the changelog over onboarding. Injected recovery boundaries let the portable router tests run without reading the app's checkpoint or using UIKit.
2. **Delete All left recoverable data:** Successful database deletion and preference reset left `Recording/current-session.json` behind. Settings now removes the checkpoint after database success and before resetting preferences/routing to onboarding. Database failure preserves recovery. Cleanup failure reports failure and leaves preferences/routing intact for retry; the database deletion itself has already committed in that case. SQLite deletion and file cleanup are sequential, not one crash-atomic transaction.
3. **Settings requested the old Health feature selection:** Both enabling toggles called the default permission helper before changing their preference. With both features off, that helper requested nothing; with another feature on it requested that other feature's permissions. Each toggle now explicitly requests only the feature being enabled. Weight requests reads only.
4. **Partial Health export could mix edited data with completed attachments:** The retry ledger tracked completion groups without binding them to their input. Local edits during/between attempts could combine an old parent or completed samples with new values and report success. Each export now captures a temporary value snapshot before queueing it. A SHA-256 digest binds the durable retry entry to that snapshot (excluding the Health link and local-only comment/race/day label). Changed input fails with the existing recovery-required error before writes; it does not delete or replace Health history. Parent reconciliation also checks distance/energy, in addition to dates/activity/identity. Older ledger entries without a digest revalidate all sample groups instead of trusting their completion flags. The ledger stores the digest, identities and flags, not the workout payload.
5. **Health import dropped later route segments:** Import read only `routes.first`. It now reads every returned route, orders the merged locations by timestamp, and rejects the entire conversion on a segment error. The existing observer queue therefore cannot commit an anchor for a partially read route.
6. **Invalid vertical accuracy could disable all future checkpoints:** GPS validation omitted `verticalAccuracy.isFinite`. A NaN value could enter the route, after which JSON encoding every later checkpoint failed. It is now rejected before route/distance/publication changes; negative finite values still represent unavailable accuracy.
7. **Portable storage runner was broken by integration:** Root's new recording/UI dependencies were missing from the harness. The runner now compiles the real checkpoint implementation, supplies fail-on-access platform stubs, and injects recovery detection/presentation in router tests. It never accesses the app's storage or default recovery URL.

## Other integration paths reviewed

- Successful `DataManager.setup` retains one public stack; repeated setup returns it without replacing the stack beneath the lazy workout monitor. Failed candidates stay private, detach before retry, and retry examines the durable intermediate schema. V3to4's durable day-identifier sentinel prevents replaying its committed pause conversion. No additional confirmed setup/monitor defect was found.
- Current restore validates before writing, performs duplicate decisions/inserts/event relationship unions in one transaction, supplies explicit UUID members to the event mapper, and returns imported/skipped counts separately. Throwing after either stage rolls back new rows and changes to existing event links. No schema/identity or generalized legacy conversion changes were made. Native CoreStore tests remain required evidence.
- Recording Stop and Continue retain the stable UUID, frozen review end, interruption pause and already-delivered final sensor values. Review/default timer checkpoints cannot replace failed-save state. A committed recovery clears the checkpoint rather than offering Continue. Sensor delivery still held inside system APIs is outside this guarantee.
- Health imports share serialized identity checks/persistence; failed or superseded observer batches cannot commit a later anchor. Read-query paths do not use sharing authorization. Export lookups remain scoped to the app source and exact external identifiers; partial quantity writes reuse saved sample identities. Existing edit error behavior and Health UUID retention remain intact.
- Offline policy validation and fallback were reviewed; no additional confirmed policy defect was found.

## Validation executed

- `python3 scripts/test-recording-core.py`: **12 passed**.
- `python3 scripts/test-health-sync.py`: **33 passed**, including the two existing blocking-query checks.
- `python3 scripts/test-storage-validation.py`: **19 passed**.
- Swift frontend syntax parsing: **48 Swift files** changed since `3c2bdac`, including native tests.
- `plutil -lint MoveFeet.xcodeproj/project.pbxproj`: passed.
- All **201 source-phase entries** resolve to existing files; modified tests are already wired into the native target.
- Existing **124 test methods retained**; current inventory **138 methods** (14 added).
- Tracked workspace/scheme XML, portable-runner Python syntax, device-install shell syntax (without execution), and `git diff --check`: passed.

The checkout has neither `MoveFeet.xcworkspace` nor `Pods`. No dependencies were installed and no native build/test was attempted, as requested. Swift parsing does not typecheck UIKit, HealthKit or CoreStore integration. The portable tests exercise production Foundation code and injected boundaries, not those frameworks.

Added native-only cases for main: `FeetRecordingBehaviorTests.testNonfiniteVerticalAccuracyCannotPoisonDurableRouteCheckpoint`, `HealthPermissionsBehaviorTests.testEnablingAHealthFeatureRequestsItsPermissionsBeforePreferenceIsEnabled`, and `HealthPermissionsBehaviorTests.testExportContentTracksEditedStepsAndMeasurementsButNotHealthLinkOrLocalComment`. The other 11 added cases run portably as well as belonging to the existing native target. Main should rerun the native recording/Health/storage suites against this commit; its earlier 70-test recording result predates these changes.

## Remaining runtime validation for main

- On a real device, recovery after setup/changelog and manual opening of recording while launch recovery waits; no second controller or automatic resumption. Termination during active/paused/review/failed-save and Continue; checkpoint protection while locked; final samples and long-route checkpoint cost.
- Fresh Health opt-out; independently enabling workout/weight sync; read-only/partial write grants, revocation, repeated toggles and observer restart. Import a synthetic workout with several routes, fail a later segment/local save, and verify anchor retry/deduplication.
- Interrupt Health parent save, sample attachment and route completion; retry without duplicate parents/samples. Edit steps/distance during a partial export and verify recovery-required feedback while prior Health history remains intact. Real HealthKit partial-write and visibility behavior cannot be established by the portable model.
- Native synthetic CoreStore setup/migration retry, monitored inserts, current backup roundtrip/overlap/rollback and deletion failure cases. Then disposable-data UI checks for successful Delete All/checkpoint cleanup and a cleanup failure. A process kill between database deletion and checkpoint cleanup remains a cross-resource crash window; no combined atomicity is claimed.

## Main integration verification

The final merged source at `42c68ab` passed **138 native XCTest cases with zero failures** on Grogu’s iPhone 16 Pro simulator (iOS 26.2). This includes synthetic CoreStore setup/migration retry, event links, restore overlap/rollback and delete-failure coverage. The main integration fixes preserve Foundation progress observation, skip completed intermediate migrations and use CoreStore key-path membership predicates. The route collection completion required an explicit native `Result<[CLLocation], Error>` annotation.

All portable suites passed again: recording 12, Health 33, storage 19. `scripts/install-movefeet.sh --build-only` completed in Grogu’s desktop Terminal session after SSH signing encountered a locked-keychain interaction restriction. The resulting app and extension pass strict signature verification; both provisioning profiles include the selected phone. Artifact version: 1.3 (1), source `42c68ab`. Device installation and outdoor/Health/lifecycle checks are tracked separately; native tests do not establish those behaviors.

Physical installation and launch succeeded on October 21 after a fresh private container backup. All ten SQLite tables, including 133 workouts and 256,279 route samples, match the pre-upgrade backup row-for-row after launch. No restoration or data cleanup was performed. The signed artifact is retained privately (ZIP SHA-256 `46a688df32df2ef7c0cbe95dafbe9a5e54dadd3777fbaeae126b090db289e776`). Outdoor recording, physical Health permission behavior and locked-screen continuity still need a real session.

## Startup regression follow-up — build 3

The owner reported a slow launch after build 2. The newly added `WorkoutSnapshot.hasRouteData` evaluated `!workout._routeData.value.isEmpty` during every main-actor `WorkoutStore` rebuild. CoreStore first bridges every related managed object into a Swift wrapper. A startup CPU sample confirmed that path dominated snapshot work with the owner’s 133-workout / 256,279-route-point backup.

Changed the check to Core Data relationship object IDs, using CoreStore’s relationship key and the existing object’s designated queue. This preserves route/no-route behavior and pending relationship edits without materializing route sample objects. No schema or stored-data change was needed.

| Same Debug simulator, same private backup, new app process | Home-list snapshot rebuild |
| --- | --- |
| Before, run 1 | 7,300.3 ms |
| Before, run 2 (CPU sampled) | 7,556.2 ms |
| After, run 1 | 674.6 ms |
| After, run 2 | 483.7 ms |

These are snapshot-work measurements, not whole-launch timings or measurements on the physical phone. The iOS 27 store copy opened on the iOS 26.2 simulator with a persistence-version warning; both before/after used the same copy/environment. The original phone store was never replaced. Health synchronization was disabled in the simulator. The private benchmark database and map caches were cleared afterward and the original synthetic simulator store restored.

All **144 native tests pass**. New tests cover 25,000 samples across a 133-workout synthetic cold SQLite timeline with zero registered route sample objects, unsaved additions/removals/reassignments, deleted final samples, missing identifiers, and rollback. The first test attempt exposed a fixture issue: context retention must be configured before any objects are registered. That was repaired before the passing run.

An optimized **Release** build, version **1.3 (3)**, compiled from production source `bae413d`, passed signature and device provisioning checks, and was installed and launched successfully. Its process was verified. The repository installer now defaults to Release (`df5e029`); Debug remains available explicitly for diagnostics. A fresh private backup with SQLite integrity OK and 133 workouts preceded installation. No restore or cleanup was applied to the phone.
