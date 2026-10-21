import XCTest
#if STORAGE_VALIDATION_PORTABLE
@testable import StorageValidationHarness
#else
import CoreStore
@testable import MoveFeet
#endif

@MainActor
final class RootStorageFailureTests: XCTestCase {
    func testAddStorageAndIntermediateErrorsBlockNormalUIAndPreferenceReads() async throws {
        for error in [DataManager.SetupError.failedToAddStorage(error: .userCancelled),
                      .intermediateMappingActionsFailed(version: OutRunV3to4.self)] {
            var finish: ((DataManager.SetupError?) -> Void)?
            var preferenceReads = 0
            let router = RootRouter(setupStorage: { completion, _ in finish = completion }, isSetUp: {
                preferenceReads += 1
                return false
            })
            router.boot()
            try XCTUnwrap(finish)(error)
            await waitFor { if case .storageFailed = router.phase { return true }; return false }
            let failurePhase = router.phase
            router.completeOnboarding()
            NotificationCenter.default.post(name: .outRunDidResetData, object: nil)
            await Task.yield()
            await Task.yield()
            XCTAssertEqual(router.phase, failurePhase)
            XCTAssertEqual(preferenceReads, 0)
        }
    }

    func testRetryIsSerializedAndOnlySuccessfulSetupEntersOnboarding() async throws {
        var completions: [(DataManager.SetupError?) -> Void] = []
        let router = RootRouter(setupStorage: { completion, _ in completions.append(completion) }, isSetUp: { false })
        router.boot()
        router.boot()
        XCTAssertEqual(completions.count, 1)
        completions[0](.failedToAddStorage(error: .userCancelled))
        await waitFor { if case .storageFailed = router.phase { return true }; return false }
        router.retryStorageSetup()
        router.retryStorageSetup()
        XCTAssertEqual(completions.count, 2)
        XCTAssertEqual(router.phase, .launching)
        completions[1](nil)
        await waitFor { router.phase == .onboarding }
        router.completeOnboarding()
        XCTAssertEqual(router.phase, .main)
    }

    func testLateProgressAndOldCompletionCannotReplaceRetryResult() async {
        var completions: [(DataManager.SetupError?) -> Void] = []
        var migrations: [(Progress) -> Void] = []
        let router = RootRouter(setupStorage: { completion, migration in
            completions.append(completion)
            migrations.append(migration)
        }, isSetUp: { false })
        router.boot()
        migrations[0](Progress(totalUnitCount: 10))
        await waitFor { if case .migrating = router.phase { return true }; return false }
        completions[0](.failedToAddStorage(error: .userCancelled))
        await waitFor { if case .storageFailed = router.phase { return true }; return false }
        router.retryStorageSetup()
        completions[1](nil)
        await waitFor { router.phase == .onboarding }
        completions[0](.failedToAddStorage(error: .userCancelled))
        migrations[0](Progress(totalUnitCount: 100))
        migrations[1](Progress(totalUnitCount: 100))
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(router.phase, .onboarding)
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Router did not reach the expected phase")
    }
}
