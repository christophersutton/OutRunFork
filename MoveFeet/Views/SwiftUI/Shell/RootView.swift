//
//  RootView.swift
//
//  OutRun
//
//  The SwiftUI root that replaces `AppDelegate`'s window-rooting. `RootRouter` drives a small boot state
//  machine — launch → (optional Core Data migration) → onboarding | main — by running `DataManager.setup`
//  exactly as the old AppDelegate did, then performs the post-launch permission re-check and the
//  post-update changelog gate. Onboarding completion and the Settings "delete all data" reset flip the
//  router's phase instead of swapping a `UIWindow.rootViewController`.
//

import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted after a full "delete all data" reset so the root returns to onboarding without a relaunch.
    static let outRunDidResetData = Notification.Name("OutRunDidResetData")
}

// MARK: - Router

@MainActor
@Observable
final class RootRouter {

    enum Phase: Equatable {
        case launching
        case migrating(Double)
        case storageFailed(String)
        case onboarding
        case main
    }

    var phase: Phase = .launching
    var changelogText: String?

    typealias SetupStorage = (@escaping (DataManager.SetupError?) -> Void, @escaping (Progress) -> Void) -> Void

    @ObservationIgnored private let setupStorage: SetupStorage
    @ObservationIgnored private let isSetUp: () -> Bool
    @ObservationIgnored private let hasRecordingRecovery: () -> Bool
    @ObservationIgnored private let presentRecordingRecovery: @MainActor () -> Bool
    @ObservationIgnored private var storageReady = false
    @ObservationIgnored private var setupInFlight = false
    @ObservationIgnored private var setupAttempt = UUID()
    @ObservationIgnored private var didBoot = false
    @ObservationIgnored private var didScheduleHealthObservers = false
    @ObservationIgnored private var didOfferRecordingRecovery = false
    @ObservationIgnored private var resetObserver: NSObjectProtocol?

    init(
        setupStorage: @escaping SetupStorage = { completion, migration in
            DataManager.setup(completion: completion, migration: migration)
        },
        isSetUp: @escaping () -> Bool = { UserPreferences.isSetUp.value },
        hasRecordingRecovery: @escaping () -> Bool = {
            RecordingCheckpointStore<TempWorkout>(url: WorkoutBuilder.recoveryURL).exists
        },
        presentRecordingRecovery: @escaping @MainActor () -> Bool = { RootRouter.presentRecoveryController() }
    ) {
        self.setupStorage = setupStorage
        self.isSetUp = isSetUp
        self.hasRecordingRecovery = hasRecordingRecovery
        self.presentRecordingRecovery = presentRecordingRecovery
    }

    deinit {
        if let resetObserver {
            NotificationCenter.default.removeObserver(resetObserver)
        }
    }

    /// Kicks off Core Data setup (idempotent). Mirrors the legacy AppDelegate boot sequence.
    func boot() {
        guard !didBoot else { return }
        didBoot = true

        // A full data reset (Settings → delete all data) returns the running app to onboarding.
        resetObserver = NotificationCenter.default.addObserver(
            forName: .outRunDidResetData, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.storageReady else { return }
                self.changelogText = nil
                self.phase = .onboarding
            }
        }

        beginStorageSetup()
    }

    func retryStorageSetup() {
        guard case .storageFailed = phase else { return }
        beginStorageSetup()
    }

    private func beginStorageSetup() {
        guard !setupInFlight else { return }
        phase = .launching
        storageReady = false
        setupInFlight = true
        setupAttempt = UUID()
        let attempt = setupAttempt

        setupStorage(
            { [weak self] error in
                Task { @MainActor in
                    guard let self, self.setupAttempt == attempt, self.setupInFlight else { return }
                    self.setupInFlight = false
                    if let error {
                        self.phase = .storageFailed(error.debugDescription)
                    } else {
                        self.storageReady = true
                        self.finishBoot()
                    }
                }
            },
            { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.setupAttempt == attempt, self.setupInFlight else { return }
                    self.phase = .migrating(progress.fractionCompleted)
                }
                progress.setProgressHandler { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.setupAttempt == attempt, self.setupInFlight else { return }
                        self.phase = .migrating(progress.fractionCompleted)
                    }
                }
            }
        )
    }

    /// Called by `OnboardingView.onComplete` after `OnboardingState.finish()` has persisted setup.
    func completeOnboarding() {
        guard storageReady else { return }
        // `OnboardingState.finish()` has already registered the HealthKit observers and written
        // `lastVersion`, so just flip the root. (Calling `HealthStoreManager.setupObservers()` again here
        // would register a second set of anchored queries.) No changelog on a fresh setup — `finish()` set
        // `lastVersion = Config.version`, so a brand-new user only sees a changelog after their first update.
        phase = .main
        offerRecordingRecovery()
    }

    // MARK: Boot internals

    private func finishBoot() {
        guard storageReady else { return }
        if isSetUp() {
            phase = .main
            scheduleHealthObserverSetup()
            runPostLaunch()
        } else {
            phase = .onboarding
        }
    }

    private func scheduleHealthObserverSetup() {
        guard !didScheduleHealthObservers else { return }
        didScheduleHealthObservers = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard UserPreferences.isSetUp.value else { return }
            HealthStoreManager.setupObservers()
        }
    }

    private func runPostLaunch() {
        Task { @MainActor in
            // Wait (briefly, bounded to ~1s) for the hosting controller to be presentable before running the
            // permission-alert chain — on a fast boot the window/root may not be attached for a turn or two,
            // and we must not silently skip the permission re-check just because it resolved too early.
            var presenter = UIApplication.shared.topMostViewController
            var attempts = 0
            while presenter == nil && attempts < 20 {
                try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms
                presenter = UIApplication.shared.topMostViewController
                attempts += 1
            }
            if let presenter {
                AppDelegate.checkPermissionStatus(controller: presenter) { [weak self] in
                    Task { @MainActor in self?.presentChangelogIfNeeded() }
                }
            } else {
                presentChangelogIfNeeded()
            }
        }
    }

    /// Runs only after storage boot and permission/changelog presentation have finished.
    func offerRecordingRecovery() {
        guard phase == .main, changelogText == nil, !didOfferRecordingRecovery,
              hasRecordingRecovery() else { return }
        didOfferRecordingRecovery = true
        Task { @MainActor in
            // UIKit dismissal and SwiftUI root transitions need a presentation turn.
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard phase == .main, changelogText == nil, hasRecordingRecovery() else { return }
                if presentRecordingRecovery() { return }
            }
            // A user-opened modal may delay this beyond launch. The normal + path still offers recovery.
        }
    }

    /// True once recording is already open or has been presented. An alert over an existing
    /// recording also counts, so dismissing it cannot cause a second controller to be created.
    private static func presentRecoveryController() -> Bool {
        guard let presenter = UIApplication.shared.topMostViewController else { return false }
        var ancestor: UIViewController? = presenter
        while let controller = ancestor {
            if controller is NewWorkoutViewController { return true }
            ancestor = controller.presentingViewController
        }
        guard !(presenter is UIAlertController), presenter.presentingViewController == nil,
              !presenter.isBeingDismissed, presenter.presentedViewController == nil,
              presenter.viewIfLoaded?.window != nil else { return false }
        // Recording owns Review / confirmed Discard / Later and UUID deduplication.
        presenter.present(NewWorkoutViewController(), animated: true)
        return true
    }

    private func presentChangelogIfNeeded() {
        guard phase == .main else { return }
        defer { if changelogText == nil { offerRecordingRecovery() } }
        if AppDelegate.lastVersion.value != Config.version && AppDelegate.lastVersion.value != nil {
            if let changeLog = Config.changeLogs[Config.version] {
                changelogText = changeLog
            }
            AppDelegate.lastVersion.value = Config.version
        } else if AppDelegate.lastVersion.value == nil {
            AppDelegate.lastVersion.value = Config.version
        }
    }
}

// MARK: - Root view

struct RootView: View {

    @State private var router = RootRouter()

    var body: some View {
        ZStack {
            switch router.phase {
            case .launching:
                LaunchView()
            case .migrating(let progress):
                MigrationView(progress: progress)
            case .storageFailed(let detail):
                StorageFailureView(detail: detail, retry: { router.retryStorageSetup() })
            case .onboarding:
                OnboardingView(onComplete: { router.completeOnboarding() })
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: router.phase)
        .task { router.boot() }
        .fullScreenCover(isPresented: changelogPresented, onDismiss: { router.offerRecordingRecovery() }) {
            ChangelogView(changelog: router.changelogText ?? "")
                .presentationBackground(.clear)   // let the changelog's own dimming show the app behind it
        }
    }

    private var changelogPresented: Binding<Bool> {
        Binding(
            get: { router.changelogText != nil },
            set: { if !$0 { router.changelogText = nil } }
        )
    }
}

// MARK: - Launch & migration

/// Branded placeholder shown while `DataManager.setup` runs (matches the `LaunchScreen` background).
private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.orBackground.ignoresSafeArea()
            ProgressView()
                .tint(Color.orAccent)
        }
    }
}

/// SwiftUI replacement for the UIKit `ProgressViewController` shown during a Core Data migration.
private struct MigrationView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.orBackground.ignoresSafeArea()
            VStack(spacing: 10) {
                Text(LS["Loading-DoNotClose"])
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Color.orPrimary)
                    .multilineTextAlignment(.center)
                ProgressView(value: progress)
                    .tint(Color.orAccent)
            }
            .padding(.horizontal, 40)
        }
    }
}

/// Storage failure is a blocking boot destination. It offers no reset or delete action.
private struct StorageFailureView: View {
    let detail: String
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(Color.orAccent)
                Text("Unable to open your workout data")
                    .font(.title2.bold())
                Text("Move: Feet cannot continue until its local storage is available. Retry after freeing device storage or restarting the app.")
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                Text("If this keeps happening, contact support for recovery help. Keep the app installed to preserve its local data.")
                Link("Contact support", destination: URL(string: "mailto:support@wavelength.computer?subject=Move:%20Feet%20storage%20recovery")!)
                DisclosureGroup("Technical details") {
                    Text(detail).font(.caption).textSelection(.enabled)
                }
            }
            .foregroundStyle(Color.orPrimary)
            .padding(28)
        }
        .background(Color.orBackground.ignoresSafeArea())
    }
}
