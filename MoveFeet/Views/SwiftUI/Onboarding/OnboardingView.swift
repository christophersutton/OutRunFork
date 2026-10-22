//
//  OnboardingView.swift
//
//  OutRun
//
//  SwiftUI onboarding flow replacing the UIKit `StartScreenViewController` (welcome) + `SetupViewController`
//  (the four-page pager). A welcome screen leads into a sequence of four gated steps —
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
            if step != .formalities {
                Button(LS["Back"]) {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .formalities }
                }
                .foregroundStyle(Color.orAccentLabel)
            }
            PageIndicator(count: OnboardingStep.allCases.count, current: step.rawValue)
            Spacer()
            Button(nextButtonTitle) { advance() }
                .font(.system(.body, weight: .bold))
                .foregroundStyle(nextEnabled ? Color.orAccentLabel : Color.orSecondary)
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
                MoveRunMark()
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 16)
                Text(LS["Setup.Headline"])
                    .font(.moveHeadline)
                    .foregroundStyle(Color.orSecondary)
                (Text("move ").foregroundStyle(Color.orPrimary) + Text("run").foregroundStyle(Color.orAccentLabel))
                    .font(.custom(MoveTheme.FontName.black, size: 48, relativeTo: .largeTitle))
                    .tracking(-1.9)
                    .accessibilityLabel(LS["OutRun"])
            }
            .multilineTextAlignment(.center)
            .padding(.top, 40)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 20) {
                    FeatureCard(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", title: LS["Setup.Feature.Route.Title"], message: LS["Setup.Feature.Route.Message"])
                    FeatureCard(symbol: "chart.bar.xaxis", title: LS["Setup.Feature.Chart.Title"], message: LS["Setup.Feature.Chart.Message"])
                    FeatureCard(symbol: "lock.fill", title: LS["Setup.Feature.Lock.Title"], message: LS["Setup.Feature.Lock.Message"])
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 40)
            }

            Button(LS["Setup.StartButton"], action: onStart)
                .buttonStyle(.movePrimary)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.orOnAccent)
                .frame(width: 48, height: 48)
                .background(Color.orAccent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom(MoveTheme.FontName.bold, size: 17, relativeTo: .headline))
                    .foregroundStyle(Color.orPrimary)
                Text(message)
                    .font(.system(.subheadline, weight: .medium))
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
                .font(.moveHeadline)
                .foregroundStyle(Color.orPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(.subheadline, weight: .medium))
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
                // The current step is the Move ring; the rest are quiet dots.
                if index == current {
                    Circle()
                        .strokeBorder(Color.orAccent, lineWidth: 3)
                        .frame(width: 11, height: 11)
                } else {
                    Circle()
                        .fill(Color.orLine)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

extension View {
    /// Wraps a step row in the app's rounded card styling.
    func onboardingCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .moveCard()
    }
}
