import CoreStore
import XCTest
@testable import MoveFeet

/// Setup tests create only unique disposable SQLite stores, never the default application store.
final class StorageSetupTests: XCTestCase {
    func testAddStorageFailureExposesNoCandidateAndCanRetry() throws {
        let url = try temporaryStoreURL()
        let failure = prepare(url, addStorage: { _, _, completion in
            completion(.failure(.userCancelled))
            return nil
        })
        XCTAssertThrowsError(try failure.get())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let stack = try prepare(url).get()
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        XCTAssertEqual(stack.modelVersion, OutRunV4.identifier)
        XCTAssertEqual(try stack.fetchCount(From<Workout>()), 0)
    }

    func testIntermediateFailureRetainsStoreAndRetriesMapping() throws {
        let url = try temporaryStoreURL()
        let workoutID = try seedIntermediate(at: url)
        let failure = prepare(url, mapIntermediate: { _, _ in false })
        XCTAssertThrowsError(try failure.get())
        XCTAssertEqual(store(url).currentORModel(from: OutRunV4.migrationChain)?.identifier, OutRunV3to4.identifier)
        try inspectIntermediate(url) { stack in
            XCTAssertEqual(try stack.fetchCount(From<OutRunV3to4.WorkoutPause>()), 0)
            XCTAssertEqual(try stack.fetchOne(From<OutRunV3to4.Workout>())?.uuid.value, workoutID)
        }
        let stack = try prepare(url).get()
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        XCTAssertEqual(stack.modelVersion, OutRunV4.identifier)
        XCTAssertEqual(try stack.fetchCount(From<Workout>()), 1)
        XCTAssertEqual(try stack.fetchCount(From<WorkoutPause>()), 1)
        XCTAssertEqual(try stack.fetchOne(From<Workout>())?._uuid.value, workoutID)
    }

    func testFailureAfterCommittedIntermediateMappingRetriesWithoutDuplicatePauses() throws {
        let url = try temporaryStoreURL()
        let workoutID = try seedIntermediate(at: url)
        let failure = prepare(url, addStorage: { stack, storage, completion in
            if stack.modelVersion == OutRunV4.identifier {
                completion(.failure(.userCancelled))
                return nil
            }
            return stack.addStorage(storage, completion: completion)
        })
        XCTAssertThrowsError(try failure.get())
        try inspectIntermediate(url) { stack in
            XCTAssertEqual(try stack.fetchCount(From<OutRunV3to4.WorkoutPause>()), 1)
            XCTAssertFalse(try XCTUnwrap(stack.fetchOne(From<OutRunV3to4.Workout>())).dayIdentifier.value.isEmpty)
        }
        // Reopen from the persisted intermediate schema, simulating a fresh process as well as retry.
        let stack = try prepare(url).get()
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        XCTAssertEqual(try stack.fetchCount(From<WorkoutPause>()), 1)
        let workout = try XCTUnwrap(stack.fetchOne(From<Workout>()))
        XCTAssertEqual(workout._uuid.value, workoutID)
        XCTAssertEqual(workout._activeDuration.value, 890, accuracy: 0.001)
        XCTAssertEqual(workout._pauseDuration.value, 10, accuracy: 0.001)
    }

    func testInconsistentIntermediateStoreIsBlockedWithoutReplayingInserts() throws {
        let url = try temporaryStoreURL()
        _ = try seedIntermediate(at: url)
        try inspectIntermediate(url) { stack in
            try stack.perform(synchronous: { transaction in
                let first = try XCTUnwrap(transaction.fetchOne(From<OutRunV3to4.Workout>()))
                first.dayIdentifier .= "already-processed"
                let second = transaction.create(Into<OutRunV3to4.Workout>())
                second.uuid .= UUID()
                let event = transaction.create(Into<OutRunV3to4.WorkoutEvent>())
                event.eventType .= 4
                event.workout .= second
            })
        }
        XCTAssertThrowsError(try prepare(url).get())
        try inspectIntermediate(url) { stack in
            XCTAssertEqual(try stack.fetchCount(From<OutRunV3to4.Workout>()), 2)
            XCTAssertEqual(try stack.fetchCount(From<OutRunV3to4.WorkoutPause>()), 0)
        }
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StorageSetupTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("Synthetic.sqlite")
    }

    private func store(_ url: URL) -> SQLiteStore {
        SQLiteStore(fileURL: url, migrationMappingProviders: OutRunV4.migrationChain.compactMap { $0.mappingProvider }, localStorageOptions: .none)
    }

    private func prepare(
        _ url: URL,
        addStorage: @escaping DataManager.AddStorage = { $0.addStorage($1, completion: $2) },
        mapIntermediate: @escaping DataManager.MapIntermediate = DataManager.completeIntermediateMapping
    ) -> Result<DataStack, DataManager.SetupError> {
        let done = expectation(description: "Prepare synthetic store")
        var received: Result<DataStack, DataManager.SetupError>?
        DataManager.prepareStorage(storage: store(url), addStorage: addStorage,
                                   mapIntermediate: mapIntermediate, migration: { _ in }) { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(received, "Exactly one completion")
            received = result
            done.fulfill()
        }
        wait(for: [done], timeout: 15)
        return received ?? .failure(.failedToAddStorage(error: .userCancelled))
    }

    private func inspectIntermediate(_ url: URL, body: (DataStack) throws -> Void) throws {
        let stack = DataStack(oRMigrationChain: OutRunV4.migrationChain, oRDataModel: OutRunV3to4.self)
        try stack.addStorageAndWait(store(url))
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        try body(stack)
    }

    private func seedIntermediate(at url: URL) throws -> UUID {
        let id = UUID()
        try inspectIntermediate(url) { stack in
            try stack.perform(synchronous: { transaction in
                let workout = transaction.create(Into<OutRunV3to4.Workout>())
                workout.uuid .= id
                workout.workoutType .= 0
                workout.distance .= 1000
                workout.startDate .= StorageFixtures.start
                workout.endDate .= StorageFixtures.start.addingTimeInterval(900)
                for (type, offset) in [(0, 10.0), (2, 20.0)] {
                    let event = transaction.create(Into<OutRunV3to4.WorkoutEvent>())
                    event.uuid .= UUID()
                    event.eventType .= type
                    event.startDate .= StorageFixtures.start.addingTimeInterval(offset)
                    event.endDate .= StorageFixtures.start.addingTimeInterval(offset)
                    event.workout .= workout
                }
            })
        }
        return id
    }
}
