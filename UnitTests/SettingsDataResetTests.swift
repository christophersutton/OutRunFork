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

}
