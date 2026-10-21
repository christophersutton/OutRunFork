import XCTest
#if STORAGE_VALIDATION_PORTABLE
@testable import StorageValidationHarness
#else
@testable import MoveFeet
#endif

final class SettingsDataResetTests: XCTestCase {
    func testSettingsOnlyResetsPreferencesAndRoutesAfterConfirmedSuccess() {
        for (success, error) in [(false, nil), (false, DataManager.DeleteError.notSaved), (true, DataManager.DeleteError.notSaved), (true, nil)] {
            var preferences = ["configured": true]
            var actions: [String] = []
            SettingsDataReset.complete(success: success, error: error, resetPreferences: {
                preferences.removeAll()
                actions.append("preferences")
            }, didReset: { actions.append("route") }, showError: { actions.append("error") })
            if success && error == nil {
                XCTAssertTrue(preferences.isEmpty)
                XCTAssertEqual(actions, ["preferences", "route"])
            } else {
                XCTAssertEqual(preferences, ["configured": true])
                XCTAssertEqual(actions, ["error"])
            }
        }
    }

    func testSuccessfulDeleteRemovesDurableRecordingBeforeReturningToOnboarding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RecordingCheckpointStore<[Int]>(url: directory.appendingPathComponent("session.json"))
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(.init(sessionID: UUID(), phase: .reviewing, capturedAt: Date(), snapshot: [1, 2]))
        var didReset = false
        SettingsDataReset.complete(success: true, error: nil, discardRecording: { try store.discard() },
            resetPreferences: { XCTAssertFalse(store.exists) }, didReset: { didReset = true },
            showError: { XCTFail("Synthetic deletion should succeed") })
        XCTAssertTrue(didReset)
        XCTAssertFalse(store.exists)
    }

    func testFailedDatabaseDeleteKeepsRecordingAndFailedCheckpointCleanupDoesNotClaimReset() {
        enum Fault: Error { case cleanup }
        var cleanupCalls = 0
        var errors = 0
        SettingsDataReset.complete(success: false, error: .notSaved,
            discardRecording: { cleanupCalls += 1 }, resetPreferences: { XCTFail() },
            didReset: { XCTFail() }, showError: { errors += 1 })
        XCTAssertEqual(cleanupCalls, 0)
        SettingsDataReset.complete(success: true, error: nil,
            discardRecording: { cleanupCalls += 1; throw Fault.cleanup }, resetPreferences: { XCTFail() },
            didReset: { XCTFail() }, showError: { errors += 1 })
        XCTAssertEqual(cleanupCalls, 1)
        XCTAssertEqual(errors, 2)
    }

}
