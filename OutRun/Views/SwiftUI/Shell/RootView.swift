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
        case onboarding
        case main
    }

    var phase: Phase = .launching
    var changelogText: String?

    @ObservationIgnored private var didBoot = false
    @ObservationIgnored private var didScheduleHealthObservers = false
    @ObservationIgnored private var resetObserver: NSObjectProtocol?

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
                self?.changelogText = nil
                self?.phase = .onboarding
            }
        }

        // `DataManager.setup`'s completion/migration closures are guaranteed to fire on the main queue,
        // but the migration progress handler's queue is unspecified — hop to MainActor uniformly.
        DataManager.setup(
            completion: { _ in
                Task { @MainActor in self.finishBoot() }
            },
            migration: { progress in
                Task { @MainActor in
                    if case .migrating = self.phase {} else { self.phase = .migrating(0) }
                }
                progress.setProgressHandler { progress in
                    Task { @MainActor in
                        if case .migrating = self.phase {
                            self.phase = .migrating(progress.fractionCompleted)
                        }
                    }
                }
            }
        )
    }

    /// Called by `OnboardingView.onComplete` after `OnboardingState.finish()` has persisted setup.
    func completeOnboarding() {
        // `OnboardingState.finish()` has already registered the HealthKit observers and written
        // `lastVersion`, so just flip the root. (Calling `HealthStoreManager.setupObservers()` again here
        // would register a second set of anchored queries.) No changelog on a fresh setup — `finish()` set
        // `lastVersion = Config.version`, so a brand-new user only sees a changelog after their first update.
        phase = .main
    }

    // MARK: Boot internals

    private func finishBoot() {
        if UserPreferences.isSetUp.value {
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

    private func presentChangelogIfNeeded() {
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
        .fullScreenCover(isPresented: changelogPresented) {
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
