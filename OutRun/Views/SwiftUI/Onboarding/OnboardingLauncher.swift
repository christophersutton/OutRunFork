//
//  OnboardingLauncher.swift
//
//  OutRun
//
//  Bridges the SwiftUI `OnboardingView` into the UIKit shell. Builds a full-screen hosting controller for the
//  onboarding flow and, on completion, swaps the key window's root to a fresh `TabBarController` — which works
//  whether the onboarding host is the window root (first launch, from `AppDelegate`) or a presented modal
//  (after a "delete all data" reset from Settings), since replacing the window root discards either stack.
//

import SwiftUI
import UIKit

enum OnboardingLauncher {

    /// A full-screen onboarding host that transitions to the main app once setup is persisted.
    @MainActor
    static func makeHostingController() -> UIViewController {
        let host = UIHostingController(rootView: OnboardingView(onComplete: { finish() }))
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = .crossDissolve
        return host
    }

    /// Swaps the key window's root to a fresh `TabBarController` with a cross-dissolve.
    @MainActor
    static func finish() {
        guard let window = UIApplication.shared.keyWindow else { return }
        let tabBarController = TabBarController()
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = tabBarController
        }
    }
}
