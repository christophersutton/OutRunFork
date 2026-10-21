import Foundation
import XCTest
#if canImport(MoveFeet)
@testable import MoveFeet
#else
@testable import HealthSyncCore
#endif

final class HealthSyncBehaviorTests: XCTestCase {
    func testImportedStepSamplesAccumulate() {
        let result = [100, 200, 300].reduce(nil as Int?) { HealthImportValues.addingSteps($0, $1) }
        XCTAssertEqual(result, 600)
    }

    func testOptOutRequestsNothing() {
        let plan = HealthAccessPlan(workouts: false, weight: false)
        XCTAssertTrue(plan.read.isEmpty)
        XCTAssertTrue(plan.write.isEmpty)
    }

    func testWeightSyncReadsWeightWithoutRequestingUnrelatedWrites() {
        let plan = HealthAccessPlan(workouts: false, weight: true)
        XCTAssertEqual(plan.read, [.bodyMass])
        XCTAssertTrue(plan.write.isEmpty)
    }

    func testWorkoutPlanDoesNotRequestWeightPermission() {
        let plan = HealthAccessPlan(workouts: true, weight: false)
        XCTAssertEqual(plan.read, [.workout, .route, .steps, .heartRate])
        XCTAssertEqual(plan.write, [.workout, .route, .distance, .energy, .steps, .heartRate])
    }

    func testImportWaitsForPersistenceBeforeCommittingAndSerializesBatches() {
        let batches = HealthImportBatchQueue()
        var finish: ((Bool) -> Void)?
        var events: [String] = []
        batches.enqueue(process: { finish = $0; events.append("persist1") }, commit: { events.append("anchor1") }, failure: { XCTFail() })
        batches.enqueue(process: { events.append("persist2"); $0(true) }, commit: { events.append("anchor2") }, failure: { XCTFail() })
        XCTAssertEqual(events, ["persist1"])
        finish?(true)
        XCTAssertEqual(events, ["persist1", "anchor1", "persist2", "anchor2"])
    }

    func testFailedBatchCannotBeSkippedByLaterBatchesAndRetriesAfterSetup() {
        let batches = HealthImportBatchQueue()
        var finish: ((Bool) -> Void)?
        var anchors: [Int] = []
        var attempts = 0
        batches.enqueue(process: { attempts += 1; finish = $0 }, commit: { anchors.append(1) }, failure: {})
        batches.enqueue(process: { _ in XCTFail("Later batch must be discarded") }, commit: { anchors.append(2) }, failure: {})
        finish?(false)
        XCTAssertTrue(batches.blocked)
        XCTAssertTrue(anchors.isEmpty)
        batches.enqueue(process: { _ in XCTFail("Failed observer remains stopped") }, commit: {}, failure: {})
        batches.reset()
        batches.enqueue(process: { attempts += 1; $0(true) }, commit: { anchors.append(1) }, failure: { XCTFail() })
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(anchors, [1])
    }

    func testDisableInvalidatesInFlightBatchCompletion() {
        let batches = HealthImportBatchQueue()
        var finish: ((Bool) -> Void)?
        batches.enqueue(process: { finish = $0 }, commit: { XCTFail("Disabled observer cannot advance") }, failure: { XCTFail() })
        batches.reset()
        finish?(true)
        XCTAssertFalse(batches.blocked)
    }

    func testRepeatedCompletionDoesNotCommitOrDrainTwice() {
        let batches = HealthImportBatchQueue()
        var first: ((Bool) -> Void)?
        var second: ((Bool) -> Void)?
        var commits = 0
        batches.enqueue(process: { first = $0 }, commit: { commits += 1 }, failure: { XCTFail() })
        batches.enqueue(process: { second = $0 }, commit: { commits += 1 }, failure: { XCTFail() })
        first?(true)
        first?(true)
        XCTAssertEqual(commits, 1)
        second?(true)
        XCTAssertEqual(commits, 2)
    }

    func testDuplicateImportsWithinAndAcrossBatchesAreIdempotent() {
        let id = UUID()
        var persisted = Set<UUID>()
        var saves = 0
        let store = HealthImportPersistence<UUID>(identity: { $0 }, isLocalExport: { _, _ in false }, prepare: { _ in },
            query: { $0(.init(health: persisted, local: [])) },
            save: { values, done in saves += values.count; persisted.formUnion(values); done(true) })
        store.persist([id, id]) { XCTAssertTrue($0) }
        store.persist([id]) { XCTAssertTrue($0) }
        XCTAssertEqual(saves, 1)
    }

    func testFailedDuplicateQueryNeverInsertsRows() {
        let store = HealthImportPersistence<UUID>(identity: { $0 }, isLocalExport: { _, _ in false }, prepare: { _ in XCTFail() },
            query: { $0(nil) }, save: { _, _ in XCTFail() })
        store.persist([UUID()]) { XCTAssertFalse($0) }
    }

    func testSaveFailureReportsFailureAndAllowsNextAttempt() {
        let id = UUID()
        var persisted = Set<UUID>()
        var attempts = 0
        let store = HealthImportPersistence<UUID>(identity: { $0 }, isLocalExport: { _, _ in false }, prepare: { _ in },
            query: { $0(.init(health: persisted, local: [])) }, save: { values, done in
                attempts += 1
                if attempts == 2 { persisted.formUnion(values) }
                done(attempts == 2)
            })
        store.persist([id]) { XCTAssertFalse($0) }
        store.persist([id]) { XCTAssertTrue($0) }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(persisted, [id])
    }

    func testPartialSaveIsNotSuccessfulUntilEveryHealthIdentityIsPersisted() {
        let id = UUID(), missing = UUID()
        var persisted = Set<UUID>()
        let store = HealthImportPersistence<UUID>(identity: { $0 }, isLocalExport: { _, _ in false }, prepare: { _ in },
            query: { $0(.init(health: persisted, local: [])) }, save: { _, done in persisted.insert(id); done(true) })
        store.persist([id, missing]) { XCTAssertFalse($0) }
    }

    func testOverlappingImportsSerializeCheckAndSave() {
        let id = UUID()
        var persisted = Set<UUID>()
        var saveCompletion: ((Bool) -> Void)?
        var saves = 0
        let store = HealthImportPersistence<UUID>(identity: { $0 }, isLocalExport: { _, _ in false }, prepare: { _ in },
            query: { $0(.init(health: persisted, local: [])) }, save: { _, done in saves += 1; saveCompletion = done })
        var completions = 0
        store.persist([id]) { XCTAssertTrue($0); completions += 1 }
        store.persist([id]) { XCTAssertTrue($0); completions += 1 }
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(completions, 0)
        persisted.insert(id)
        saveCompletion?(true)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(completions, 2)
    }

    func testOwnExportIsNotReimportedBeforeReferenceCallbackFinishes() {
        let id = UUID()
        let store = HealthImportPersistence<UUID>(identity: { $0 }, isLocalExport: { record, local in local.contains(record) }, prepare: { _ in XCTFail() },
            query: { $0(.init(health: [], local: [id])) }, save: { _, _ in XCTFail() })
        store.persist([id]) { XCTAssertTrue($0) }
    }

    func testAttachmentCompletionWaitsForRouteAndReportsFailure() {
        var routeCompletion: ((Bool) -> Void)?
        var checkpoints: [String] = []
        var result: Bool?
        HealthAttachmentBatch.run(keys: ["steps", "route"], completed: [], attach: { key, done in
            if key == "route" { routeCompletion = done } else { done(true) }
        }, checkpoint: { checkpoints.append($0); return true }, completion: { result = $0 })
        XCTAssertNil(result)
        XCTAssertEqual(checkpoints, ["steps"])
        routeCompletion?(false)
        XCTAssertEqual(result, false)
        XCTAssertEqual(checkpoints, ["steps"])
    }

    func testRetrySkipsCompletedSamplesAndRepairsOnlyFailedRoute() {
        var state: Set<String> = []
        var calls: [String] = []
        func run(routeSucceeds: Bool, expected: Bool) {
            HealthAttachmentBatch.run(keys: ["steps", "route"], completed: state, attach: { key, done in
                calls.append(key); done(key != "route" || routeSucceeds)
            }, checkpoint: { state.insert($0); return true }, completion: { XCTAssertEqual($0, expected) })
        }
        run(routeSucceeds: false, expected: false)
        run(routeSucceeds: true, expected: true)
        XCTAssertEqual(calls, ["steps", "route", "route"])
        XCTAssertEqual(state, ["steps", "route"])
    }

    func testDeniedOptionalAttachmentDoesNotPreventOtherAuthorizedAttachments() {
        var checkpoints: [String] = []
        HealthAttachmentBatch.run(keys: ["heartRate", "steps", "route"], completed: [], attach: { key, done in done(key != "heartRate") },
            checkpoint: { checkpoints.append($0); return true }, completion: { XCTAssertFalse($0) })
        XCTAssertEqual(checkpoints, ["steps", "route"])
    }

    func testCheckpointFailureSurfacesIncompleteExport() {
        HealthAttachmentBatch.run(keys: ["steps"], completed: [], attach: { _, done in done(true) },
            checkpoint: { _ in false }, completion: { XCTAssertFalse($0) })
    }

    func testRetryLedgerSurvivesRecreationAndStoresOnlyScopedIdentityState() throws {
        let suite = "HealthSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID(), parent = UUID()
        let first = HealthExportLedger(defaults: defaults)
        try first.set(.init(parent: parent, completed: ["steps"]), for: id)
        let second = HealthExportLedger(defaults: defaults)
        XCTAssertEqual(try second.entry(for: id), .init(parent: parent, completed: ["steps"]))
        XCTAssertEqual(try second.pendingIDs(), [id])
        try second.set(nil, for: id)
        XCTAssertTrue(try first.pendingIDs().isEmpty)
    }

    func testCorruptOrUnknownLedgerStateFailsClosed() throws {
        let suite = "HealthSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = HealthExportLedger(defaults: defaults)
        let key = "com.wcc.movefeet.healthExportRetry.v1"
        defaults.set(Data("invalid".utf8), forKey: key)
        XCTAssertThrowsError(try ledger.pendingIDs())
        XCTAssertThrowsError(try ledger.set(.init(), for: UUID()))
        defaults.set(Data("{\"not-a-uuid\":{\"completed\":[]}}".utf8), forKey: key)
        XCTAssertThrowsError(try ledger.pendingIDs())
        defaults.removeObject(forKey: key)
        XCTAssertThrowsError(try ledger.set(.init(completed: ["unexpected"]), for: UUID()))
    }

    func testSavedParentCannotBeCreatedAgainWhenLookupReturnsNothing() {
        XCTAssertFalse(HealthExportRecovery.canCreate(ledgerParent: UUID(), localReference: nil))
        XCTAssertFalse(HealthExportRecovery.canCreate(ledgerParent: nil, localReference: UUID()))
        XCTAssertTrue(HealthExportRecovery.canCreate(ledgerParent: nil, localReference: nil))
    }

    func testRecoveredParentMustMatchDatesActivityAndLedgerIdentity() {
        let start = Date(timeIntervalSince1970: 100), end = Date(timeIntervalSince1970: 200), parent = UUID()
        func validate(start candidateStart: Date = start, activity: UInt = 37, ledger: UUID? = parent) -> Bool {
            HealthExportRecovery.canReuse(expectedStart: start, expectedEnd: end, expectedActivity: 37,
                start: candidateStart, end: end, activity: activity, parent: parent, ledgerParent: ledger)
        }
        XCTAssertTrue(validate())
        XCTAssertTrue(validate(ledger: nil))
        XCTAssertFalse(validate(start: end))
        XCTAssertFalse(validate(activity: 52))
        XCTAssertFalse(validate(ledger: UUID()))
    }

    func testPartialAttachmentRecoverySkipsAttachedAndReusesSavedOrphanSamples() {
        let attached = UUID(), orphan = UUID()
        let plan = HealthSampleRecovery.plan(expected: ["steps.0", "steps.1", "steps.2"],
            saved: ["steps.0": [attached], "steps.1": [orphan]], attached: [attached])
        XCTAssertEqual(plan, [.attach(orphan), .create(2)])
    }

    func testAmbiguousSampleRecoveryFailsWithoutCreatingDuplicates() {
        XCTAssertNil(HealthSampleRecovery.plan(expected: ["steps.0"], saved: ["steps.0": [UUID(), UUID()]], attached: []))
    }

    func testFullyAttachedGroupRequiresNoSampleCreationOrAttachment() {
        let id = UUID()
        XCTAssertEqual(HealthSampleRecovery.plan(expected: ["steps.0"], saved: ["steps.0": [id]], attached: [id]), [])
    }

    func testRetryFingerprintIsStableAcrossKeyOrderingAndRejectsEditedAttachments() throws {
        let original = try HealthExportFingerprint.digest(["distance": 1000, "steps": 500])
        let repeated = try HealthExportFingerprint.digest(["steps": 500, "distance": 1000])
        let edited = try HealthExportFingerprint.digest(["distance": 1000, "steps": 600])
        XCTAssertEqual(original, repeated)
        XCTAssertTrue(HealthExportFingerprint.canResume(recorded: original, current: repeated))
        XCTAssertFalse(HealthExportFingerprint.canResume(recorded: original, current: edited))
        // Older entries are reconciled against the parent and saved samples by the adapter.
        XCTAssertTrue(HealthExportFingerprint.canResume(recorded: nil, current: original))
        XCTAssertEqual(original.count, 64)
    }

    func testRetryFingerprintSurvivesLedgerRecreation() throws {
        let suite = "HealthSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID(), parent = UUID()
        let digest = try HealthExportFingerprint.digest(["steps": 500])
        try HealthExportLedger(defaults: defaults).set(.init(parent: parent, completed: ["steps"], contentDigest: digest), for: id)
        let restored = try XCTUnwrap(HealthExportLedger(defaults: defaults).entry(for: id))
        XCTAssertEqual(restored.contentDigest, digest)
        XCTAssertFalse(HealthExportFingerprint.canResume(recorded: restored.contentDigest,
            current: try HealthExportFingerprint.digest(["steps": 600])))
    }

    func testRecoveredParentMustMatchImmutableDistanceAndEnergy() {
        let start = Date(timeIntervalSince1970: 100), end = Date(timeIntervalSince1970: 200), parent = UUID()
        func matches(distance: Double?, energy: Double?) -> Bool {
            HealthExportRecovery.canReuse(expectedStart: start, expectedEnd: end, expectedActivity: 37,
                start: start, end: end, activity: 37, parent: parent, ledgerParent: nil,
                expectedDistance: 1000, distance: distance, expectedEnergy: 70, energy: energy)
        }
        XCTAssertTrue(matches(distance: 1000, energy: 70))
        XCTAssertFalse(matches(distance: 2000, energy: 70))
        XCTAssertFalse(matches(distance: 1000, energy: 80))
        XCTAssertFalse(matches(distance: nil, energy: 70))
        XCTAssertFalse(matches(distance: 1000, energy: nil))
    }

    func testAllHealthRouteSegmentsAreReadBeforeImportCompletes() throws {
        var first: ((Result<[Int], Error>) -> Void)?
        var second: ((Result<[Int], Error>) -> Void)?
        var result: Result<[Int], Error>?
        var queried: [Int] = []
        HealthRouteCollection.collect(routes: [1, 2], query: { route, finish in
            queried.append(route)
            if route == 1 { first = finish } else { second = finish }
        }, completion: { result = $0 })
        XCTAssertEqual(queried, [1])
        XCTAssertNil(result)
        first?(.success([10, 11]))
        XCTAssertEqual(queried, [1, 2])
        XCTAssertNil(result)
        second?(.success([20, 21]))
        XCTAssertEqual(try result?.get(), [10, 11, 20, 21])
    }

    func testFailureReadingLaterRouteRejectsPartialImportAndDoesNotCommitAnchor() {
        enum Fault: Error { case route }
        let batches = HealthImportBatchQueue()
        var queried: [Int] = []
        var failed = false
        batches.enqueue(process: { done in
            HealthRouteCollection.collect(routes: [1, 2, 3], query: { route, finish in
                queried.append(route)
                if route == 1 { finish(.success([10])) } else { finish(.failure(Fault.route)) }
            }, completion: { (result: Result<[Int], Error>) in
                done((try? result.get()) != nil)
            })
        }, commit: { XCTFail("Partial route must not advance anchor") }, failure: { failed = true })
        XCTAssertEqual(queried, [1, 2])
        XCTAssertTrue(failed)
        XCTAssertTrue(batches.blocked)
    }

    func testWorkoutWithoutRoutesImportsEmptyRouteSuccessfully() throws {
        var result: Result<[Int], Error>?
        HealthRouteCollection.collect(routes: [] as [Int], query: { _, _ in XCTFail("No route query expected") },
            completion: { result = $0 })
        XCTAssertEqual(try result?.get(), [])
    }

}
