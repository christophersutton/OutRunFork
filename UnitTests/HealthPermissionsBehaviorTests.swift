import XCTest
import HealthKit
@testable import MoveFeet

final class HealthPermissionsBehaviorTests: XCTestCase {
    @MainActor
    func testOptOutDoesNotCallHealthAuthorizationAPI() {
        let original = HealthStoreManager.authorizationRequest
        defer { HealthStoreManager.authorizationRequest = original }
        HealthStoreManager.authorizationRequest = { _, _, _ in XCTFail("Opt-out must not call HealthKit") }
        let completed = expectation(description: "opt out")
        PermissionManager.standard.checkHealthPermission(workouts: false, weight: false) { ready in
            XCTAssertTrue(ready)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }

    @MainActor
    func testReadAuthorizationCompletionDoesNotRequireSharingAuthorization() {
        let original = HealthStoreManager.authorizationRequest
        let available = HealthStoreManager.healthDataAvailable
        defer {
            HealthStoreManager.authorizationRequest = original
            HealthStoreManager.healthDataAvailable = available
        }
        HealthStoreManager.healthDataAvailable = { true }
        HealthStoreManager.authorizationRequest = { write, read, done in
            XCTAssertTrue(write.isEmpty)
            XCTAssertEqual(read, [HealthStoreManager.HealthType.Workout])
            // This callback only says the sheet completed, including read-only
            // or denied reads. No sharing-status gate may be applied afterward.
            done(true, nil)
        }
        let completed = expectation(description: "read request")
        HealthStoreManager.requestReadAuthorisation(for: [HealthStoreManager.HealthType.Workout]) { ready in
            XCTAssertTrue(ready)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }

    @MainActor
    func testOnboardingCanFinishAfterDecliningHealth() {
        let state = OnboardingState()
        state.shouldSyncWorkouts = true
        state.shouldSyncWeight = true
        state.locationPermissionGranted = true
        state.motionPermissionGranted = true
        state.appleHealthRequestCompleted = false
        XCTAssertTrue(state.permissionsValid)
    }
}
