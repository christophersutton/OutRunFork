import XCTest
#if canImport(MoveFeet)
@testable import MoveFeet
#else
@testable import RecordingCore
#endif

final class RecordingDurabilityTests: XCTestCase {
    struct Snapshot: Codable, Equatable { let distance: Double; let samples: [Int] }
    typealias Store = RecordingCheckpointStore<Snapshot>

    private func store() -> Store {
        Store(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("checkpoint.json"))
    }

    func testEveryRecoveryPhaseSurvivesFreshStoreInstance() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let id = UUID(), date = Date(timeIntervalSince1970: 1000)
        for phase: Store.Phase in [.recording, .paused, .reviewing, .failedSave] {
            let snapshot = Snapshot(distance: 1234, samples: [1, 2, 3])
            try store.save(.init(sessionID: id, phase: phase, capturedAt: date, snapshot: snapshot))
            let loaded = try XCTUnwrap(Store(url: store.url).load())
            XCTAssertEqual(loaded.sessionID, id)
            XCTAssertEqual(loaded.phase, phase)
            XCTAssertEqual(loaded.capturedAt, date)
            XCTAssertEqual(loaded.snapshot, snapshot)
        }
    }

    func testFailedReplacementPreservesLastCompleteCheckpoint() throws {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try store.save(.init(sessionID: id, phase: .recording, capturedAt: Date(), snapshot: .init(distance: 42, samples: [1])))
        let previous = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.save(.init(sessionID: id, phase: .recording, capturedAt: Date(), snapshot: .init(distance: .nan, samples: [1, 2]))))
        XCTAssertEqual(try Data(contentsOf: store.url), previous)
    }

    func testCorruptCheckpointIsKeptUntilConfirmedDiscard() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.clear(sessionID: UUID()))
        XCTAssertTrue(store.exists)
        try store.discard()
        XCTAssertFalse(store.exists)
    }

    func testObsoleteSaveCannotClearNewSession() throws {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try store.save(.init(sessionID: id, phase: .reviewing, capturedAt: Date(), snapshot: .init(distance: 42, samples: [])))
        try store.clear(sessionID: UUID())
        XCTAssertTrue(store.exists)
        try store.clear(sessionID: id)
        XCTAssertNil(try store.load())
    }

    func testCheckpointWriteFailureIsReported() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save(.init(sessionID: UUID(), phase: .paused, capturedAt: Date(), snapshot: .init(distance: 1, samples: []))))
    }

    func testGPSRejectsInvalidStaleDuplicateReversedAndFutureSamples() {
        let now = Date(timeIntervalSince1970: 1000)
        var gate = RecordingLocationGate()
        func accept(_ seconds: Double, accuracy: Double = 5, latitude: Double = 40) -> Bool {
            gate.accept(latitude: latitude, longitude: -74, accuracy: accuracy, timestamp: now.addingTimeInterval(seconds), now: now)
        }
        XCTAssertFalse(accept(-30))
        XCTAssertFalse(accept(0, accuracy: -1))
        XCTAssertFalse(accept(0, accuracy: .nan))
        XCTAssertFalse(accept(0, latitude: 91))
        XCTAssertFalse(accept(10))
        XCTAssertTrue(accept(-2))
        XCTAssertFalse(accept(-2))
        XCTAssertFalse(accept(-3))
        XCTAssertTrue(accept(-1))
        XCTAssertTrue(accept(0))
    }

    func testHealthOptOutSavesLocallyWithoutExport() {
        var events: [String] = []
        let operation = RecordingSaveOperation<Int>(lookup: { _ in nil }, save: { callback in events.append("save"); callback(1) },
            export: { _, callback in events.append("export"); callback(true) }, didSaveLocally: { events.append("clear") })
        operation.begin(id: UUID(), healthEnabled: false) { XCTAssertEqual($0, .saved); events.append("done") }
        XCTAssertEqual(events, ["save", "clear", "done"])
    }

    func testHealthFailureOccursAfterLocalCommitAndDoesNotResave() {
        var events: [String] = []
        let operation = RecordingSaveOperation<Int>(lookup: { _ in nil }, save: { callback in events.append("save"); callback(1) },
            export: { _, callback in events.append("export"); callback(false) }, didSaveLocally: { events.append("clear") })
        operation.begin(id: UUID(), healthEnabled: true) { XCTAssertEqual($0, .savedHealthFailure); events.append("done") }
        XCTAssertFalse(operation.begin(id: UUID(), healthEnabled: true) { _ in XCTFail() })
        XCTAssertEqual(events, ["save", "clear", "export", "done"])
    }

    func testHealthSuccessAndRepeatedCallbacksCompleteOnlyOnce() {
        var exported = 0, completed = 0, cleared = 0
        let operation = RecordingSaveOperation<Int>(lookup: { _ in nil }, save: { callback in callback(1); callback(1) },
            export: { _, callback in exported += 1; callback(true); callback(false) }, didSaveLocally: { cleared += 1 })
        operation.begin(id: UUID(), healthEnabled: true) { XCTAssertEqual($0, .saved); completed += 1 }
        XCTAssertEqual(exported, 1); XCTAssertEqual(completed, 1); XCTAssertEqual(cleared, 1)
    }

    func testLocalFailureRetainsRecoveryAndAllowsRetry() {
        var attempts = 0, cleared = 0, exports = 0
        let operation = RecordingSaveOperation<Int>(lookup: { _ in nil }, save: { callback in attempts += 1; callback(attempts == 1 ? nil : 1) },
            export: { _, callback in exports += 1; callback(true) }, didSaveLocally: { cleared += 1 })
        let id = UUID()
        operation.begin(id: id, healthEnabled: true) { XCTAssertEqual($0, .localFailure) }
        XCTAssertEqual(cleared, 0); XCTAssertEqual(exports, 0)
        operation.begin(id: id, healthEnabled: true) { XCTAssertEqual($0, .saved) }
        XCTAssertEqual(attempts, 2); XCTAssertEqual(cleared, 1); XCTAssertEqual(exports, 1)
    }

    func testCrashAfterCommitBeforeClearDoesNotInsertOrExportAgain() {
        let id = UUID()
        var cleared = 0
        let operation = RecordingSaveOperation<Int>(lookup: { XCTAssertEqual($0, id); return 1 },
            save: { _ in XCTFail("Already committed") }, export: { _, _ in XCTFail("Do not duplicate Health") }, didSaveLocally: { cleared += 1 })
        operation.begin(id: id, healthEnabled: true) { XCTAssertEqual($0, .alreadySaved) }
        XCTAssertEqual(cleared, 1)
    }

    func testDoubleTapDuringPendingLocalSaveIsIgnored() {
        var pending: ((Int?) -> Void)?, attempts = 0
        let operation = RecordingSaveOperation<Int>(lookup: { _ in nil }, save: { attempts += 1; pending = $0 },
            export: { _, _ in XCTFail() }, didSaveLocally: {})
        let id = UUID()
        XCTAssertTrue(operation.begin(id: id, healthEnabled: false) { XCTAssertEqual($0, .saved) })
        XCTAssertFalse(operation.begin(id: id, healthEnabled: false) { _ in XCTFail() })
        pending?(1)
        XCTAssertEqual(attempts, 1)
    }
}
