import CoreStore
import XCTest
@testable import MoveFeet

/// Every store in these tests is in-memory. No DataManager global or application SQLite URL is used.
final class StorageTransactionTests: XCTestCase {
    private enum Fault: Error { case injected }

    func testCurrentV4RestoreTwicePreservesEveryFieldAndRelationship() throws {
        let stack = try makeStack()
        let workout = StorageFixtures.workout()
        let event = StorageFixtures.event(workouts: [workout])
        let data = try JSONEncoder().encode(Backup(workouts: [workout], events: [event]))
        let decoded = try BackupManager.decodeBackup(from: data)

        let first = try restore(decoded.workouts, decoded.events, in: stack).get()
        XCTAssertEqual([first.importedWorkouts, first.skippedWorkouts, first.importedEvents, first.skippedEvents], [1, 0, 1, 0])
        let saved = try snapshot(stack)
        XCTAssertEqual(try json(saved.workoutData[0]), try json(workout))
        XCTAssertEqual(try json(saved.eventData[0]), try json(event))

        // Export the persisted current format, then restore that same backup twice.
        let exported = try BackupManager.decodeBackup(from: JSONEncoder().encode(saved))
        for _ in 0..<2 {
            let report = try restore(exported.workouts, exported.events, in: stack).get()
            XCTAssertEqual([report.importedWorkouts, report.skippedWorkouts, report.importedEvents, report.skippedEvents], [0, 1, 0, 1])
            XCTAssertEqual(try contents(stack), try contents(saved))
            XCTAssertEqual(try counts(stack), [1, 1, 1, 1, 1, 1])
        }
        let inverses = expectation(description: "Event inverse relationship")
        stack.perform(asynchronous: { transaction -> Bool in
            let workout = try XCTUnwrap(transaction.fetchOne(From<Workout>()))
            let event = try XCTUnwrap(transaction.fetchOne(From<Event>()))
            return workout._events.value.contains(event) && event._workouts.value.contains(workout)
        }) { result in
            XCTAssertEqual(try? result.get(), true)
            inverses.fulfill()
        }
        wait(for: [inverses], timeout: 5)
    }

    func testOverlappingBackupsReuseWorkoutsAndUnionExistingEventMembers() throws {
        let stack = try makeStack()
        let first = StorageFixtures.workout()
        let second = StorageFixtures.workout()
        let third = StorageFixtures.workout()
        let existingEvent = StorageFixtures.event(workouts: [first])
        _ = try restore([first], [existingEvent], in: stack).get()

        let overlapping = StorageFixtures.event(workouts: [first, second], id: existingEvent.uuid!)
        overlapping.title = "Must not overwrite the existing title"
        let newEvent = StorageFixtures.event(workouts: [first, second, third])
        let report = try restore([first, second, third], [overlapping, newEvent], in: stack).get()
        XCTAssertEqual([report.importedWorkouts, report.skippedWorkouts, report.importedEvents, report.skippedEvents], [2, 1, 1, 1])
        let saved = try snapshot(stack)
        let reused = try XCTUnwrap(saved.eventData.first { $0.uuid == existingEvent.uuid })
        XCTAssertEqual(reused.title, existingEvent.title)
        XCTAssertEqual(Set(reused.workouts), Set([first.uuid!, second.uuid!]))
        XCTAssertEqual(Set(try XCTUnwrap(saved.eventData.first { $0.uuid == newEvent.uuid }).workouts), Set([first.uuid!, second.uuid!, third.uuid!]))
        XCTAssertEqual(try counts(stack), [3, 3, 3, 3, 3, 2])
    }

    func testDuplicateRowsInsideOneBackupAreSuccessfulSkips() throws {
        let stack = try makeStack()
        let workout = StorageFixtures.workout()
        let event = StorageFixtures.event(workouts: [workout])
        let report = try restore([workout, workout], [event, event], in: stack).get()
        XCTAssertEqual([report.importedWorkouts, report.skippedWorkouts, report.importedEvents, report.skippedEvents], [1, 1, 1, 1])
        XCTAssertEqual(try counts(stack), [1, 1, 1, 1, 1, 1])
    }

    func testFailureAfterEitherRestoreStageRollsBackAllRowsAndExistingLinks() throws {
        for stage in [DataManager.RestoreStage.workouts, .events] {
            let stack = try makeStack()
            let retained = StorageFixtures.workout()
            let retainedEvent = StorageFixtures.event(workouts: [retained])
            _ = try restore([retained], [retainedEvent], in: stack).get()
            let before = try contents(stack)
            let added = StorageFixtures.workout()
            let expanded = StorageFixtures.event(workouts: [retained, added], id: retainedEvent.uuid!)
            let result = restore([added], [expanded, StorageFixtures.event(workouts: [added])], in: stack) {
                if $0 == stage { throw Fault.injected }
            }
            XCTAssertThrowsError(try result.get())
            XCTAssertEqual(try contents(stack), before)
            XCTAssertEqual(try counts(stack), [1, 1, 1, 1, 1, 1])
            // A failure must not poison the next transaction or prevent retry.
            let retry = try restore([added], [expanded], in: stack).get()
            XCTAssertEqual([retry.importedWorkouts, retry.skippedEvents], [1, 1])
        }
    }

    func testMissingRelationshipRejectsWholeRestoreAfterWorkoutInserts() throws {
        let stack = try makeStack()
        let workout = StorageFixtures.workout()
        let missing = StorageFixtures.workout()
        let event = StorageFixtures.event(workouts: [workout, missing])
        XCTAssertThrowsError(try restore([workout], [event], in: stack).get())
        XCTAssertEqual(try counts(stack), [0, 0, 0, 0, 0, 0])
    }

    func testInvalidPayloadCommitsNothingEvenWhenOtherRowsAreValid() throws {
        let stack = try makeStack()
        let valid = StorageFixtures.workout()
        let invalid = StorageFixtures.workout()
        invalid.distance = -1
        XCTAssertThrowsError(try restore([valid, invalid], [StorageFixtures.event(workouts: [valid])], in: stack).get())
        XCTAssertEqual(try counts(stack), [0, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try BackupManager.decodeBackup(from: Data("{\"version\":\"V4\",\"workoutData\":[{}]}".utf8)))
        XCTAssertThrowsError(try BackupManager.decodeBackup(from: Data("{\"version\":\"future\"}".utf8)))
    }

    func testDeleteAllReportsFailureAndRollsBackAtEveryDeletionStage() throws {
        for faultStage in 0..<6 {
            let stack = try makeStack()
            let workout = StorageFixtures.workout()
            _ = try restore([workout], [StorageFixtures.event(workouts: [workout])], in: stack).get()
            let before = try contents(stack)
            let done = expectation(description: "Delete failure \(faultStage)")
            DataManager.deleteAll(in: stack, afterStage: { stage in
                if stage == faultStage { throw Fault.injected }
            }) { success, error in
                XCTAssertFalse(success)
                XCTAssertNotNil(error)
                XCTAssertTrue(Thread.isMainThread)
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
            XCTAssertEqual(try contents(stack), before)
            XCTAssertEqual(try counts(stack), [1, 1, 1, 1, 1, 1])
        }
    }

    func testDeleteAllSuccessRemovesEveryEntityAndCanBeRepeated() throws {
        let stack = try makeStack()
        let workout = StorageFixtures.workout()
        _ = try restore([workout], [StorageFixtures.event(workouts: [workout])], in: stack).get()
        for _ in 0..<2 {
            let done = expectation(description: "Delete success")
            DataManager.deleteAll(in: stack) { success, error in
                XCTAssertTrue(success)
                XCTAssertNil(error)
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
            XCTAssertEqual(try counts(stack), [0, 0, 0, 0, 0, 0])
        }
    }

    private func makeStack() throws -> DataStack {
        let stack = DataStack(oRMigrationChain: OutRunV4.migrationChain, oRDataModel: OutRunV4.self)
        try stack.addStorageAndWait(InMemoryStore())
        return stack
    }

    private func restore(
        _ workouts: [TempWorkout], _ events: [TempEvent], in stack: DataStack,
        afterStage: @escaping (DataManager.RestoreStage) throws -> Void = { _ in }
    ) -> Result<DataManager.RestoreReport, Error> {
        let done = expectation(description: "Atomic restore")
        var received: Result<DataManager.RestoreReport, Error>?
        DataManager.restore(workouts: workouts, events: events, in: stack, afterStage: afterStage) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(received, "Exactly one completion")
            received = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return received ?? .failure(Fault.injected)
    }

    private func snapshot(_ stack: DataStack) throws -> Backup {
        let done = expectation(description: "Snapshot")
        var received: Result<Backup, CoreStoreError>?
        stack.perform(asynchronous: { transaction -> Backup in
            Backup(workouts: try transaction.fetchAll(From<Workout>()).map { $0.asTemp },
                   events: try transaction.fetchAll(From<Event>()).map { $0.asTemp })
        }) { result in
            received = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(received).get()
    }

    private func counts(_ stack: DataStack) throws -> [Int] {
        try [stack.fetchCount(From<Workout>()), stack.fetchCount(From<WorkoutPause>()),
             stack.fetchCount(From<WorkoutEvent>()), stack.fetchCount(From<WorkoutRouteDataSample>()),
             stack.fetchCount(From<WorkoutHeartRateDataSample>()), stack.fetchCount(From<Event>())]
    }

    private func contents(_ stack: DataStack) throws -> [Data] { try contents(snapshot(stack)) }

    private func contents(_ backup: Backup) throws -> [Data] {
        // Ignore the backup creation date and fetch ordering; retain all stored fields and identities.
        let workouts = backup.workoutData.sorted { $0.uuid!.uuidString < $1.uuid!.uuidString }
        let events = backup.eventData.sorted { $0.uuid!.uuidString < $1.uuid!.uuidString }
        return try workouts.map(json) + events.map(json)
    }

    private func json<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(object)
    }
}
