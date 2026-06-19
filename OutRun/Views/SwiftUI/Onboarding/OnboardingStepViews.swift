//
//  OnboardingStepViews.swift
//
//  OutRun
//
//  The four onboarding steps (Formalities, User Info, Apple Health, Permissions) plus the small reusable row
//  views they share. Permission requests reuse the existing `PermissionManager.standard` (location/motion/
//  health), hopping back to the main actor before mutating observable state — the same pattern the rest of
//  the SwiftUI layer uses for callback-based managers.
//

import SwiftUI
import UIKit

// MARK: - Formalities

struct FormalitiesStep: View {

    @Bindable var state: OnboardingState
    @State private var policySheet: PolicySheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingStepHeader(title: LS["Setup.Formalities.Title"], message: LS["Setup.Formalities.Message"])
            VStack(spacing: 12) {
                OnboardingLinkToggleRow(title: LS["Settings.PrivacyPolicy"], isOn: $state.agreedToPrivacyPolicy) {
                    policySheet = .privacy
                }
                OnboardingLinkToggleRow(title: LS["Settings.TermsOfService"], isOn: $state.agreedToTermsOfService) {
                    policySheet = .terms
                }
            }
        }
        .sheet(item: $policySheet) { sheet in
            PolicyView(type: sheet.policyType)
        }
    }
}

private enum PolicySheet: Identifiable {
    case privacy, terms
    var id: Int { hashValue }
    var policyType: PolicyManager.PolicyType { self == .privacy ? .privacyPolicy : .termsOfService }
}

// MARK: - User info

struct UserInfoStep: View {

    @Bindable var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingStepHeader(title: LS["Setup.UserInfo.Title"], message: LS["Setup.UserInfo.Message"])
            VStack(spacing: 12) {
                OnboardingFieldRow(
                    title: LS["Setup.UserInfo.Username"],
                    placeholder: LS["Setup.UserInfo.Username.Placeholder"],
                    text: $state.username
                )

                HStack {
                    Text(LS["Setup.UserInfo.PreferredSystem"])
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.orPrimary)
                    Spacer()
                    Picker("", selection: $state.preferredMeasurementSystem) {
                        Text(LS["Setup.UserInfo.PreferredSystem.Metric"]).tag(0)
                        Text(LS["Setup.UserInfo.PreferredSystem.Imperial"]).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .onboardingCard()

                OnboardingFieldRow(
                    title: LS["Setup.UserInfo.Weight"],
                    placeholder: LS["Setup.UserInfo.Weight"],
                    text: $state.weightText,
                    unit: state.weightUnitSymbol,
                    keyboard: .decimalPad
                )
            }
        }
        .onChange(of: state.weightText) { state.recomputeWeightKg() }
        .onChange(of: state.preferredMeasurementSystem) { state.reformatWeightAfterSystemChange() }
    }
}

// MARK: - Apple Health

struct AppleHealthStep: View {

    @Bindable var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingStepHeader(title: LS["Setup.AppleHealth.Title"], message: LS["Setup.AppleHealth.Message"])
            VStack(spacing: 12) {
                OnboardingToggleRow(title: LS["Setup.AppleHealth.SyncWorkouts"], isOn: $state.shouldSyncWorkouts)
                OnboardingToggleRow(title: LS["Setup.AppleHealth.SyncWeight"], isOn: $state.shouldSyncWeight)
                OnboardingToggleRow(title: LS["Setup.AppleHealth.AutoImportWorkouts"], isOn: $state.shouldAutoImportWorkouts)
                    .disabled(!state.shouldSyncWorkouts)
                    .opacity(state.shouldSyncWorkouts ? 1 : 0.5)
            }
        }
        .onChange(of: state.shouldSyncWorkouts) {
            // Auto-import is meaningless without workout sync; force it off (mirrors the legacy behaviour).
            if !state.shouldSyncWorkouts { state.shouldAutoImportWorkouts = false }
        }
    }
}

// MARK: - Permissions

struct PermissionsStep: View {

    @Bindable var state: OnboardingState
    @State private var alertInfo: OnboardingAlertInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingStepHeader(title: LS["Setup.Permissions.Title"], message: LS["Setup.Permissions.Message"])
            VStack(spacing: 12) {
                OnboardingPermissionRow(
                    title: LS["Setup.Permission.Location"],
                    granted: state.locationPermissionGranted,
                    grant: requestLocation,
                    info: { showInfo(LS["Setup.Permission.Location"], LS["Setup.Permission.Location.Message"]) }
                )
                OnboardingPermissionRow(
                    title: LS["Setup.Permission.Motion"],
                    granted: state.motionPermissionGranted,
                    grant: requestMotion,
                    info: { showInfo(LS["Setup.Permission.Motion"], LS["Setup.Permission.Motion.Message"]) }
                )
                if state.syncEnabled {
                    OnboardingPermissionRow(
                        title: LS["Setup.Permission.AppleHealth"],
                        granted: state.appleHealthPermissionGranted,
                        grant: requestHealth,
                        info: { showInfo(LS["Setup.Permission.AppleHealth"], LS["Setup.Permission.AppleHealth.Message"]) }
                    )
                }
            }
        }
        .alert(
            alertInfo?.title ?? "",
            isPresented: Binding(get: { alertInfo != nil }, set: { if !$0 { alertInfo = nil } }),
            presenting: alertInfo
        ) { info in
            if info.showSettings {
                Button(LS["Open"]) { openSettings() }
                Button(LS["Cancel"], role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { info in
            Text(info.message)
        }
    }

    private func showInfo(_ title: String, _ message: String) {
        alertInfo = OnboardingAlertInfo(title: title, message: message, showSettings: false)
    }

    private func requestLocation() {
        PermissionManager.standard.checkLocationPermission { status in
            DispatchQueue.main.async {
                switch status {
                case .granted, .restricted:
                    state.locationPermissionGranted = true
                    if status == .restricted {
                        alertInfo = OnboardingAlertInfo(
                            title: LS["Setup.Permission.Location.Restricted.Title"],
                            message: LS["Setup.Permission.Location.Restricted.Message"],
                            showSettings: true
                        )
                    }
                default:
                    state.locationPermissionGranted = false
                    alertInfo = OnboardingAlertInfo(
                        title: LS["Error"],
                        message: LS["Setup.Permission.Location.Error"],
                        showSettings: true
                    )
                }
            }
        }
    }

    private func requestMotion() {
        PermissionManager.standard.checkMotionPermission { success in
            DispatchQueue.main.async {
                state.motionPermissionGranted = success
                if !success {
                    alertInfo = OnboardingAlertInfo(
                        title: LS["Error"],
                        message: LS["Setup.Permission.Motion.Error"],
                        showSettings: true
                    )
                }
            }
        }
    }

    private func requestHealth() {
        PermissionManager.standard.checkHealthPermission { success in
            DispatchQueue.main.async {
                state.appleHealthPermissionGranted = success
                if !success {
                    alertInfo = OnboardingAlertInfo(
                        title: LS["Setup.Permission.AppleHealth"],
                        message: LS["Setup.Permission.AppleHealth.Error"],
                        showSettings: false
                    )
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct OnboardingAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let showSettings: Bool
}

// MARK: - Reusable rows

private struct OnboardingFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var unit: String? = nil
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orPrimary)
            Spacer(minLength: 12)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
            if let unit {
                Text(unit).foregroundStyle(Color.orSecondary)
            }
        }
        .onboardingCard()
    }
}

private struct OnboardingToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orPrimary)
        }
        .tint(Color.orAccent)
        .onboardingCard()
    }
}

private struct OnboardingLinkToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let link: () -> Void

    var body: some View {
        HStack {
            Button(action: link) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orAccent)
                    .underline()
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.orAccent)
        }
        .onboardingCard()
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let granted: Bool
    let grant: () -> Void
    let info: () -> Void

    var body: some View {
        HStack {
            Button(action: info) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.orPrimary)
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orSecondary)
                }
            }
            Spacer()
            Button(action: grant) {
                Group {
                    if granted {
                        Image(systemName: "checkmark")
                    } else {
                        Text(LS["Grant"].uppercased())
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 64)
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(granted ? Color.orAccent : Color.orSecondary)
                .clipShape(Capsule())
            }
            .disabled(granted)
            .animation(.easeInOut(duration: 0.2), value: granted)
        }
        .onboardingCard()
    }
}
