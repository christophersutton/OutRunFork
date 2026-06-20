//
//  OnboardingView.swift
//
//  OutRun
//
//  SwiftUI onboarding flow replacing the UIKit `StartScreenViewController` (welcome) + `SetupViewController`
//  (the four-page pager). A welcome screen leads into a forward-only sequence of four gated steps —
//  Formalities, User Info, Apple Health, Permissions — with a page indicator and a contextual
//  Next/Skip/Finish button. On finish it persists the user's choices (`OnboardingState.finish()`) and calls
//  `onComplete`, which flips the SwiftUI root (`RootRouter`) from onboarding to the main tab shell.
//

import SwiftUI

struct OnboardingView: View {

    /// Invoked after setup is persisted; flips the SwiftUI root from onboarding to the main tab shell.
    let onComplete: () -> Void

    @State private var state = OnboardingState()
    @State private var showWelcome = true
    @State private var step: OnboardingStep = .formalities

    var body: some View {
        ZStack {
            Color.orBackground.ignoresSafeArea()

            if showWelcome {
                WelcomeStep { withAnimation { showWelcome = false } }
                    .transition(.opacity)
            } else {
                setupContainer
                    .transition(.opacity)
            }
        }
    }

    // MARK: Setup container

    private var setupContainer: some View {
        VStack(spacing: 0) {
            ScrollView {
                stepContent
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .formalities:  FormalitiesStep(state: state)
        case .userInfo:     UserInfoStep(state: state)
        case .appleHealth:  AppleHealthStep(state: state)
        case .permissions:  PermissionsStep(state: state)
        }
    }

    private var bottomBar: some View {
        HStack {
            PageIndicator(count: OnboardingStep.allCases.count, current: step.rawValue)
            Spacer()
            Button(nextButtonTitle) { advance() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(nextEnabled ? Color.orAccent : Color.orSecondary)
                .disabled(!nextEnabled)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 16)
    }

    private var nextButtonTitle: String {
        switch step {
        case .permissions: return LS["Finish"]
        case .appleHealth: return state.syncEnabled ? LS["Next"] : LS["Skip"]
        default:           return LS["Next"]
        }
    }

    private var nextEnabled: Bool {
        switch step {
        case .formalities: return state.formalitiesValid
        case .userInfo:    return state.userInfoValid
        case .appleHealth: return true                 // always allowed to proceed (skippable)
        case .permissions: return state.permissionsValid
        }
    }

    private func advance() {
        switch step {
        case .formalities: withAnimation { step = .userInfo }
        case .userInfo:    withAnimation { step = .appleHealth }
        case .appleHealth: withAnimation { step = .permissions }
        case .permissions:
            state.finish()
            onComplete()
        }
    }
}

// MARK: - Step model

enum OnboardingStep: Int, CaseIterable {
    case formalities, userInfo, appleHealth, permissions
}

// MARK: - Welcome

private struct WelcomeStep: View {

    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(LS["Setup.Headline"])
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.orPrimary)
                Text(LS["OutRun"])
                    .font(Font.system(size: 42, weight: .heavy).lowercaseSmallCaps())
                    .foregroundStyle(Color.orAccent)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 40)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 20) {
                    FeatureCard(image: "setupRoute", title: LS["Setup.Feature.Route.Title"], message: LS["Setup.Feature.Route.Message"])
                    FeatureCard(image: "setupChart", title: LS["Setup.Feature.Chart.Title"], message: LS["Setup.Feature.Chart.Message"])
                    FeatureCard(image: "setupLock", title: LS["Setup.Feature.Lock.Title"], message: LS["Setup.Feature.Lock.Message"])
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 40)
            }

            Button(action: onStart) {
                Text(LS["Setup.StartButton"].uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
    }
}

private struct FeatureCard: View {
    let image: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(Color.orAccent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orPrimary)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.orSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared step chrome

/// Large title + secondary message header used at the top of each setup step.
struct OnboardingStepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.orPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.orSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Static page dots (the legacy `UIPageControl` was non-interactive too).
private struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.orAccent : Color.orAccent.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

extension View {
    /// Wraps a step row in the app's rounded card styling.
    func onboardingCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orForeground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
