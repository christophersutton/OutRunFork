import XCTest
import Combine
import CoreLocation
@testable import MoveFeet

@MainActor
final class FeetRecordingBehaviorTests: XCTestCase {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
    }

    private func store() -> WorkoutBuilder.CheckpointStore {
        WorkoutBuilder.CheckpointStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("session.json"))
    }

    private func sample(_ date: Date, latitude: Double = 40, speed: Double = 2, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: -74), altitude: 10,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0, speed: speed, timestamp: date)
    }

    func testPausePlayExcludesEachPauseExactlyOnceAndFreezesDisplayClock() throws {
        let store = store(), clock = Clock()
        defer { try? store.discard() }
        let builder = WorkoutBuilder(checkpointStore: store, now: { clock.date })
        let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
        let readiness = PassthroughSubject<WorkoutBuilderComponentStatus, Never>()
        let output = builder.tranform(.init(readiness: readiness.eraseToAnyPublisher(), statusSuggestion: status.eraseToAnyPublisher()))
        var displayEnd: Date?
        let token = output.durationEndDate.sink { displayEnd = $0 }
        defer { token.cancel() }
        readiness.send(.ready(LocationManagement.self))
        status.send(.recording)
        clock.advance(10); builder.togglePause()
        XCTAssertEqual(displayEnd, clock.date)
        clock.advance(20); builder.togglePause()
        XCTAssertEqual(builder.status, .recording)
        XCTAssertNil(displayEnd)
        clock.advance(5); builder.togglePause()
        clock.advance(7); status.send(.reviewing)
        let snapshot = try XCTUnwrap(builder.createSnapshotProvider()?())
        XCTAssertEqual(snapshot.activeDuration, 15, accuracy: 0.001)
        XCTAssertEqual(snapshot.pauseDuration, 27, accuracy: 0.001)
        XCTAssertEqual(snapshot.pauses.count, 2)
    }

    func testInitialSelectionAndEverySupportedTypeReachSnapshotAndCannotChangeAfterStart() throws {
        for type in Workout.WorkoutType.supportedTypes {
            let store = store(), clock = Clock()
            defer { try? store.discard() }
            let builder = WorkoutBuilder(workoutType: .unknown, checkpointStore: store, now: { clock.date })
            let types = CurrentValueSubject<Workout.WorkoutType, Never>(type)
            let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
            let ready = CurrentValueSubject<WorkoutBuilderComponentStatus, Never>(.ready(LocationManagement.self))
            _ = builder.tranform(.init(readiness: ready.eraseToAnyPublisher(), workoutType: types.eraseToAnyPublisher(), statusSuggestion: status.eraseToAnyPublisher()))
            XCTAssertEqual(builder.selectedWorkoutType, type)
            status.send(.recording)
            types.send(.unknown)
            clock.advance(10); status.send(.reviewing)
            let snapshot = try XCTUnwrap(builder.createSnapshotProvider()?())
            XCTAssertEqual(snapshot.workoutType, type)
            XCTAssertEqual(snapshot.workoutType.healthKitType, type.healthKitType)
        }
    }

    func testLiveLocationDrivesAutoPauseResumeAndMapPublisherDuringRecording() throws {
        let store = store(), clock = Clock()
        defer { try? store.discard() }
        let builder = WorkoutBuilder(workoutType: .running, checkpointStore: store, now: { clock.date })
        let autoPause = AutoPauseDetection(builder: builder)
        let location = LocationManagement(builder: builder, prepareSensors: false)
        let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
        let output = builder.tranform(.init(statusSuggestion: status.eraseToAnyPublisher()))
        var published: [Date] = []
        let token = output.currentLocation.compactMap { $0 }.sink { published.append($0.timestamp) }
        defer { token.cancel(); withExtendedLifetime(autoPause) {} }
        status.send(.recording)
        location.process([sample(clock.date)], now: clock.date)
        clock.advance(1)
        location.process([sample(clock.date, accuracy: 500)], now: clock.date)
        clock.advance(1)
        location.process([sample(clock.date, speed: 0)], now: clock.date)
        XCTAssertEqual(builder.status, .autoPaused)
        clock.advance(5)
        location.process([sample(clock.date, latitude: 40.001)], now: clock.date)
        XCTAssertEqual(builder.status, .recording)
        XCTAssertEqual(published.count, 4)
        status.send(.reviewing)
        let snapshot = try XCTUnwrap(builder.createSnapshotProvider()?())
        XCTAssertEqual(snapshot.routeData.count, 3)
        XCTAssertEqual(snapshot.pauseDuration, 5, accuracy: 0.001)
    }

    func testInvalidAndReorderedGPSDoNotChangeRouteOrDistanceAndStopKeepsFinalSample() throws {
        let store = store(), clock = Clock()
        defer { try? store.discard() }
        let builder = WorkoutBuilder(workoutType: .walking, checkpointStore: store, now: { clock.date })
        let location = LocationManagement(builder: builder, prepareSensors: false)
        let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
        _ = builder.tranform(.init(statusSuggestion: status.eraseToAnyPublisher()))
        status.send(.recording)
        let first = sample(clock.date)
        location.process([first], now: clock.date)
        clock.advance(2)
        location.process([sample(clock.date, latitude: 41, accuracy: -1), first,
                          sample(clock.date.addingTimeInterval(-40), latitude: 42),
                          sample(clock.date.addingTimeInterval(-3), latitude: 43)], now: clock.date)
        let final = sample(clock.date, latitude: 40.001)
        location.process([final], now: clock.date)
        status.send(.reviewing)
        let snapshot = try XCTUnwrap(builder.createSnapshotProvider()?())
        XCTAssertEqual(snapshot.routeData.count, 2)
        XCTAssertEqual(snapshot.routeData.last?.timestamp, final.timestamp)
        XCTAssertEqual(snapshot.distance, final.distance(from: first), accuracy: 0.01)
        XCTAssertEqual(try store.load()?.snapshot.routeData.count, 2)
    }

    func testRecoveryOfEveryPhaseFreezesEndAndContinueExcludesTerminationTime() throws {
        for phase: WorkoutBuilder.CheckpointStore.Phase in [.recording, .paused, .reviewing, .failedSave] {
            let store = store(), clock = Clock()
            defer { try? store.discard() }
            let builder = WorkoutBuilder(checkpointStore: store, now: { clock.date })
            let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
            let ready = CurrentValueSubject<WorkoutBuilderComponentStatus, Never>(.ready(LocationManagement.self))
            _ = builder.tranform(.init(readiness: ready.eraseToAnyPublisher(), statusSuggestion: status.eraseToAnyPublisher()))
            status.send(.recording)
            clock.advance(10)
            if phase == .paused { status.send(.paused); clock.advance(3) }
            if phase == .reviewing || phase == .failedSave { status.send(.reviewing) }
            builder.checkpoint(phase: phase)
            let checkpoint = try XCTUnwrap(store.load())
            clock.advance(1000)
            let recovered = WorkoutBuilder(checkpointStore: store, now: { clock.date })
            XCTAssertTrue(try recovered.recoverWorkout(isLocallySaved: { _ in false }))
            XCTAssertEqual(recovered.status, .reviewing)
            let snapshot = try XCTUnwrap(recovered.createSnapshotProvider()?())
            XCTAssertEqual(snapshot.uuid, checkpoint.sessionID)
            XCTAssertEqual(snapshot.endDate, checkpoint.snapshot.endDate)
            XCTAssertEqual(snapshot.activeDuration, checkpoint.snapshot.activeDuration)
            recovered.continueWorkout(from: snapshot)
            clock.advance(5)
            let stop = PassthroughSubject<WorkoutBuilder.Status, Never>()
            _ = recovered.tranform(.init(statusSuggestion: stop.eraseToAnyPublisher()))
            stop.send(.reviewing)
            let final = try XCTUnwrap(recovered.createSnapshotProvider()?())
            XCTAssertEqual(final.uuid, snapshot.uuid)
            XCTAssertEqual(final.activeDuration, snapshot.activeDuration + 5, accuracy: 0.001)
        }
    }

    func testCommittedRecoveryClearsCheckpointWithoutOfferingContinue() throws {
        let store = store(), clock = Clock()
        let builder = WorkoutBuilder(checkpointStore: store, now: { clock.date })
        let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
        let ready = CurrentValueSubject<WorkoutBuilderComponentStatus, Never>(.ready(LocationManagement.self))
        _ = builder.tranform(.init(readiness: ready.eraseToAnyPublisher(), statusSuggestion: status.eraseToAnyPublisher()))
        status.send(.recording)
        clock.advance(10); status.send(.reviewing)
        let id = try XCTUnwrap(store.load()?.sessionID)
        let recovered = WorkoutBuilder(checkpointStore: store, now: { clock.date })
        XCTAssertFalse(try recovered.recoverWorkout(isLocallySaved: { XCTAssertEqual($0, id); return true }))
        XCTAssertFalse(store.exists)
        XCTAssertFalse(recovered.status.isReviewingStatus)
        XCTAssertNil(recovered.createSnapshotProvider())
    }

    func testFinalStepsAndHeartRateRemainInReviewAndSuccessfulSaveStaysCleared() throws {
        let store = store(), clock = Clock()
        let builder = WorkoutBuilder(checkpointStore: store, now: { clock.date })
        let status = PassthroughSubject<WorkoutBuilder.Status, Never>()
        let ready = CurrentValueSubject<WorkoutBuilderComponentStatus, Never>(.ready(LocationManagement.self))
        let steps = PassthroughSubject<Int?, Never>()
        let heartRates = PassthroughSubject<[TempWorkoutHeartRateDataSample], Never>()
        _ = builder.tranform(.init(readiness: ready.eraseToAnyPublisher(), statusSuggestion: status.eraseToAnyPublisher(),
                                  steps: steps.eraseToAnyPublisher(), heartRates: heartRates.eraseToAnyPublisher()))
        status.send(.recording)
        clock.advance(10)
        steps.send(50)
        heartRates.send([.init(uuid: nil, heartRate: 120, timestamp: clock.date)])
        status.send(.reviewing)
        steps.send(99)
        let snapshot = try XCTUnwrap(builder.createSnapshotProvider()?())
        XCTAssertEqual(snapshot.steps, 50)
        XCTAssertEqual(snapshot.heartRates.last?.heartRate, 120)
        XCTAssertEqual(try store.load()?.snapshot.steps, 50)
        builder.didSaveLocally()
        builder.checkpoint(phase: .reviewing)
        XCTAssertFalse(store.exists)
    }

    func testCalculatedEnergyIsSavedForDifferentDistancesAtSameWeight() {
        let previous = UserPreferences.weight.value
        UserPreferences.weight.value = 70
        defer { UserPreferences.weight.value = previous }
        let start = Date(timeIntervalSince1970: 1000)
        func workout(_ distance: Double) -> NewWorkout {
            NewWorkout(workoutType: .running, distance: distance, steps: nil, startDate: start,
                endDate: start.addingTimeInterval(600), isRace: false, comment: nil,
                isUserModified: false, finishedRecording: true, heartRates: [], routeData: [], pauses: [], workoutEvents: [])
        }
        let short = workout(1000), long = workout(5000)
        XCTAssertEqual(short.burnedEnergy, Computation.calculateBurnedEnergy(for: .running, distance: 1000, weight: 70))
        XCTAssertEqual(long.burnedEnergy, Computation.calculateBurnedEnergy(for: .running, distance: 5000, weight: 70))
        XCTAssertNotEqual(short.burnedEnergy, 70)
        XCTAssertNotEqual(short.burnedEnergy, long.burnedEnergy)
    }
}
