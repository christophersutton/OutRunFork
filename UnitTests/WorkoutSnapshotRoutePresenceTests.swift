import CoreData
import CoreStore
import XCTest
@testable import MoveFeet

/// Synthetic stores only. Never opens DataManager's stack or the application's workout history.
final class WorkoutSnapshotRoutePresenceTests: XCTestCase {

    @MainActor
    func testColdTimelineWithLargeRouteDoesNotRegisterRouteSampleObjects() throws {
        let url = try temporaryStoreURL()
        let routedID = UUID()
        let routeFreeID = UUID()
        let sampleCount = 25_000

        // Close and reopen SQLite to discard the seeding contexts and relationship caches.
        let seed = try makeStack(at: url)
        try seed.perform(synchronous: { transaction in
            let routed = transaction.create(Into<Workout>())
            routed._uuid .= routedID
            routed._distance .= 0 // Route presence must not be inferred from distance.
            for _ in 0..<sampleCount {
                let sample = transaction.create(Into<WorkoutRouteDataSample>())
                sample._workout .= routed
            }
            let routeFree = transaction.create(Into<Workout>())
            routeFree._uuid .= routeFreeID
            routeFree._distance .= 100_000
            for _ in 0..<131 {
                let workout = transaction.create(Into<Workout>())
                workout._uuid .= UUID()
            }
            // An orphan sample must not make any workout appear to have a route.
            _ = transaction.create(Into<WorkoutRouteDataSample>())
        })
        seed.unsafeRemoveAllPersistentStoresAndWait()

        let stack = try makeStack(at: url)
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        let context = stack.unsafeContext()
        // Keep any accidentally materialized samples registered so this assertion cannot depend on
        // autorelease timing or CoreStore wrapper lifetimes. No wall-clock threshold is needed.
        context.retainsRegisteredObjects = true
        XCTAssertEqual(try stack.fetchCount(From<WorkoutRouteDataSample>()), sampleCount + 1)
        let monitor = stack.monitorList(From<Workout>().orderBy(.descending(\._startDate)))
        let objects = monitor.objectsInAllSections()
        XCTAssertEqual(registeredRouteSampleCount(in: context), 0)

        let store = WorkoutStore(monitor: monitor)
        XCTAssertTrue(store.isLoaded)
        XCTAssertEqual(store.workouts.count, 133)
        XCTAssertEqual(store.workouts.first { $0.id == routedID }?.hasRouteData, true)
        XCTAssertEqual(store.workouts.first { $0.id == routeFreeID }?.hasRouteData, false)
        XCTAssertEqual(store.workouts.filter(\.hasRouteData).count, 1)
        XCTAssertEqual(registeredRouteSampleCount(in: context), 0,
                       "Timeline snapshots must not materialize thousands of related route objects.")

        // Rebuilding snapshots on the same context must have the same behavior.
        XCTAssertEqual(objects.map { WorkoutSnapshot($0) }.filter(\.hasRouteData).count, 1)
        XCTAssertEqual(registeredRouteSampleCount(in: context), 0)
    }

    func testUnsavedRelationshipsAndMissingIdentifiersOnBackgroundTransactionQueue() throws {
        let stack = try makeStack()
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        let done = expectation(description: "Snapshot unsaved route edits on their owning queue")
        stack.perform(asynchronous: { transaction in
            XCTAssertFalse(Thread.isMainThread)
            let workout = transaction.create(Into<Workout>())
            // No UUID, dates, or distance have been supplied. Empty relationships are still valid.
            XCTAssertNil(workout._uuid.value)
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData)
            let sample = transaction.create(Into<WorkoutRouteDataSample>())
            XCTAssertNil(sample._uuid.value)
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData, "Unlinked data is not a route.")

            sample._workout .= workout
            XCTAssertTrue(WorkoutSnapshot(workout).hasRouteData, "Include unsaved inverse additions.")
            sample._workout .= nil
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData, "Include unsaved inverse removals.")
            workout._routeData .= [sample]
            XCTAssertTrue(WorkoutSnapshot(workout).hasRouteData, "Include ordered relationship edits.")
            workout._routeData .= []
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData)

            let other = transaction.create(Into<Workout>())
            sample._workout .= workout
            sample._workout .= other
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData)
            XCTAssertTrue(WorkoutSnapshot(other).hasRouteData, "Include pending reassignment.")
            transaction.delete(sample)
            other.cs_toRaw().managedObjectContext?.processPendingChanges()
            XCTAssertFalse(WorkoutSnapshot(other).hasRouteData, "A deleted final sample leaves no route.")
        }) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    @MainActor
    func testSavedRouteEditsReflectPendingChangesAndRollback() throws {
        let url = try temporaryStoreURL()
        let stack = try makeStack(at: url)
        defer { stack.unsafeRemoveAllPersistentStoresAndWait() }
        try stack.perform(synchronous: { transaction in
            let workout = transaction.create(Into<Workout>())
            workout._uuid .= UUID()
            let sample = transaction.create(Into<WorkoutRouteDataSample>())
            sample._workout .= workout
        })

        let done = expectation(description: "Roll back pending route removal")
        stack.perform(asynchronous: { transaction in
            let workout = try XCTUnwrap(transaction.fetchOne(From<Workout>()))
            XCTAssertTrue(WorkoutSnapshot(workout).hasRouteData)
            let sample = try XCTUnwrap(transaction.fetchOne(From<WorkoutRouteDataSample>()))
            workout._routeData .= []
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData,
                           "A persistent-store-only query would incorrectly return true here.")
            workout._routeData .= [sample]
            XCTAssertTrue(WorkoutSnapshot(workout).hasRouteData)
            transaction.delete(sample)
            workout.cs_toRaw().managedObjectContext?.processPendingChanges()
            XCTAssertFalse(WorkoutSnapshot(workout).hasRouteData)
            try transaction.cancel()
        }) { result in
            switch result {
            case .failure(.userCancelled): break
            default: XCTFail("Expected transaction cancellation, got \(result)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        let saved = try XCTUnwrap(stack.fetchOne(From<Workout>()))
        XCTAssertTrue(WorkoutSnapshot(saved).hasRouteData, "Rollback must preserve the saved route.")
        XCTAssertEqual(try stack.fetchCount(From<WorkoutRouteDataSample>()), 1)
    }

    private func registeredRouteSampleCount(in context: NSManagedObjectContext) -> Int {
        context.registeredObjects.filter { WorkoutRouteDataSample.cs_matches(object: $0) }.count
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutSnapshotRoutePresenceTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("Synthetic.sqlite")
    }

    private func makeStack(at url: URL? = nil) throws -> DataStack {
        let stack = DataStack(oRMigrationChain: OutRunV4.migrationChain, oRDataModel: OutRunV4.self)
        if let url {
            try stack.addStorageAndWait(SQLiteStore(fileURL: url, localStorageOptions: .none))
        } else {
            try stack.addStorageAndWait(InMemoryStore())
        }
        return stack
    }
}
