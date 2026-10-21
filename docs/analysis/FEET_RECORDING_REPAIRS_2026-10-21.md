# Feet recording repairs — October 21, 2026

Scope: recording components, temporary workout construction, completion actions and recovery. Existing workout/schema UUIDs and history are unchanged. New recordings receive their UUID at Start and retain it through checkpoints, Continue and local save.

## Integration hook for the root owner

RootView was deliberately not edited. After **successful local store setup** and arrival at the normal main screen, check:

```swift
let hasRecording = RecordingCheckpointStore<TempWorkout>(url: WorkoutBuilder.recoveryURL).exists
```

If true, present the existing recording screen (`NewWorkoutViewController`) once using the normal recording presentation path. Its `viewDidAppear` offers Review / confirmed Discard / Later. Do not present before successful store setup, over onboarding, or more than once per launch. Returning to recording offers recovery again. Do not construct a second recording controller while one is already active. No special root-owned mutation of the checkpoint is needed.

Without that small root integration, recovery is available automatically **when the recording screen opens**, but no launch prompt appears on the main screen.

## Behavior

- Pause toggles back to recording with Play. Activity selection binds immediately, including the initial presentation value, and locks after Start until discard/new recording. Current supported activities are running, walking and hiking (the audit's Cycling example is not a current supported type).
- Recording component delivery is synchronous on main. Location updates publish after route/distance processing, so Stop captures all already-delivered samples. Pedometer callbacks hop to main and use a generation to reject callbacks from a previous pause/resume interval. Distance never bridges movement during a pause or interruption.
- Invalid coordinates/accuracy, non-finite values, samples older than 15 seconds, more than 5 seconds in the future, duplicate timestamps and reversed timestamps are rejected before recording/publication. Valid live samples publish to maps/auto-pause even when route accuracy filtering excludes storage.
- NewWorkout stores computed energy. Open pauses freeze the live elapsed display, and saved pause intervals are counted once.
- Application Support/Recording/current-session.json is atomically replaced after accepted GPS updates, step/heart-rate updates, status changes, background transitions, and a five-second timer while active. The file uses protection until first unlock and is excluded from backup. Review is frozen; failed Save persists its phase. I/O errors are surfaced, not silently treated as durable success.
- Recovery always opens in review at the last durable end date. Continue appends the interruption as a pause. No clock runs automatically across process termination. The last uncheckpointed interval can be lost (up to five seconds without sensor delivery); time after the durable end is deliberately excluded. There is no guarantee of delivery for samples still held inside system sensor APIs at termination.
- Clear happens after successful local save, a UUID lookup proving the local record was already committed, or confirmed discard. A corrupt checkpoint is retained on read failure and requires explicit discard. A save completing after a prior local commit cannot insert a second record. An old UUID cannot clear a newer session.
- Local save precedes optional Health export. Local failure retains recovery and allows retry; Health failure reports “saved on this iPhone” plus export failure/incompleteness and does not undo or repeat the local insert. Health retry/export details remain owned by the adapter worker. The existing adapter can still hide asynchronous route/sample failures; this repair cannot truthfully detect errors it never receives. A crash between local commit and Health export can leave an unsynced local record for later Health synchronization.

## Validation

Executed locally:

- `python3 scripts/test-recording-core.py`: 12 behavioral XCTest cases, 0 failures. Compiles the actual three production Foundation sources into a temporary Swift package and tests only synthetic temporary files/callbacks; no application database or sensors. Test names are in `UnitTests/RecordingDurabilityTests.swift`: phase round trips; failed replacement preserving the prior file; corruption/discard; identity-aware clear; I/O failure; invalid/stale/out-of-order GPS; Health off; Health failure; Health success/repeated callbacks; retry after local failure; commit-before-clear deduplication; double tap during pending save.
- `swiftc -typecheck` for RecordingCheckpointStore, RecordingLocationGate and RecordingSaveOperation.
- `xcrun swiftc -frontend -parse` for changed/new Swift files, including the native test file. Parsing does **not** typecheck UIKit/CoreStore integration.
- `plutil -lint MoveFeet.xcodeproj/project.pbxproj`, explicit source/test wiring and source-path checks, `git diff --check`.

Added/wired for integration, **not executed locally**: eight native behavioral tests in `FeetRecordingBehaviorTests`: pause/resume accounting/display; every supported initial type/locking/Health type mapping; moving→stationary→moving publication/auto-pause; invalid GPS/distance/final Stop sample; all four recovery phases/Continue timing/identity; calculated energy at two distances; committed recovery without Continue; final step/heart-rate retention and checkpoint clearing.

The checkout has no Pods directory or MoveFeet.xcworkspace. No native app build, simulator, physical device, real GPS/background/locked-screen recording, real Health export, private database, SSH/Grogu or Nidra checks were performed. Main owns native workspace build and integration tests. Run both added XCTest classes, the existing suite, then validate termination in active/paused/review/failed-save states and a measured outdoor session with screen lock, stops and app switching. Native file protection while locked and sustained full-route checkpoint cost still require device evidence.

## Exact test inventory

Executed by `python3 scripts/test-recording-core.py`:

- `RecordingDurabilityTests.testEveryRecoveryPhaseSurvivesFreshStoreInstance`
- `RecordingDurabilityTests.testFailedReplacementPreservesLastCompleteCheckpoint`
- `RecordingDurabilityTests.testCorruptCheckpointIsKeptUntilConfirmedDiscard`
- `RecordingDurabilityTests.testObsoleteSaveCannotClearNewSession`
- `RecordingDurabilityTests.testCheckpointWriteFailureIsReported`
- `RecordingDurabilityTests.testGPSRejectsInvalidStaleDuplicateReversedAndFutureSamples`
- `RecordingDurabilityTests.testHealthOptOutSavesLocallyWithoutExport`
- `RecordingDurabilityTests.testHealthFailureOccursAfterLocalCommitAndDoesNotResave`
- `RecordingDurabilityTests.testHealthSuccessAndRepeatedCallbacksCompleteOnlyOnce`
- `RecordingDurabilityTests.testLocalFailureRetainsRecoveryAndAllowsRetry`
- `RecordingDurabilityTests.testCrashAfterCommitBeforeClearDoesNotInsertOrExportAgain`
- `RecordingDurabilityTests.testDoubleTapDuringPendingLocalSaveIsIgnored`

Added to the native UnitTests target, parsed but not executed:

- `FeetRecordingBehaviorTests.testPausePlayExcludesEachPauseExactlyOnceAndFreezesDisplayClock`
- `FeetRecordingBehaviorTests.testInitialSelectionAndEverySupportedTypeReachSnapshotAndCannotChangeAfterStart`
- `FeetRecordingBehaviorTests.testLiveLocationDrivesAutoPauseResumeAndMapPublisherDuringRecording`
- `FeetRecordingBehaviorTests.testInvalidAndReorderedGPSDoNotChangeRouteOrDistanceAndStopKeepsFinalSample`
- `FeetRecordingBehaviorTests.testRecoveryOfEveryPhaseFreezesEndAndContinueExcludesTerminationTime`
- `FeetRecordingBehaviorTests.testCommittedRecoveryClearsCheckpointWithoutOfferingContinue`
- `FeetRecordingBehaviorTests.testFinalStepsAndHeartRateRemainInReviewAndSuccessfulSaveStaysCleared`
- `FeetRecordingBehaviorTests.testCalculatedEnergyIsSavedForDifferentDistancesAtSameWeight`

## Files in this repair

- `MoveFeet.xcodeproj/project.pbxproj`
- `MoveFeet/Controllers/Workout/NewWorkoutViewController.swift`
- `MoveFeet/Models/Data/NewWorkout.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/Components/AltitudeManagement.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/Components/AutoPauseDetection.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/Components/LiveStats.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/Components/LocationManagement.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/Components/StepCounter.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/RecordingCheckpointStore.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/RecordingLocationGate.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/RecordingSaveOperation.swift`
- `MoveFeet/Models/Workout/WorkoutBuilder/WorkoutBuilder.swift`
- `MoveFeet/Models/Workout/WorkoutCompletionActionHandler.swift`
- `MoveFeet/Views/Workout/NewWorkoutControllerActionButton.swift`
- `MoveFeet/Views/Workout/WorkoutCompletionBanner.swift`
- `UnitTests/FeetRecordingBehaviorTests.swift`
- `UnitTests/RecordingDurabilityTests.swift`
- `docs/analysis/FEET_RECORDING_REPAIRS_2026-10-21.md`
- `scripts/test-recording-core.py`
