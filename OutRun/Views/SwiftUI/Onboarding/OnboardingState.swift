//
//  OnboardingState.swift
//
//  OutRun
//
//  Observable view model backing the SwiftUI onboarding flow (the replacement for the UIKit
//  `StartScreenViewController` + `SetupViewController` pager). Holds all of the user's setup choices and owns
//  `finish()`, which writes them through to `UserPreferences` — a faithful port of the legacy `finishSetup()`.
//
//  Weight is kept canonically in kilograms (`userWeightKg`); the displayed field text is in the user's chosen
//  system. The view drives `recomputeWeightKg()` / `reformatWeightAfterSystemChange()` via `.onChange` so the
//  physical weight stays constant when the Metric/Imperial control flips.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingState {

    // MARK: Formalities
    var agreedToPrivacyPolicy = false
    var agreedToTermsOfService = false

    // MARK: User info
    var username: String = ""
    /// 0 == metric, 1 == imperial. Defaults to the device locale.
    var preferredMeasurementSystem: Int = Locale.current.usesMetricSystem ? 0 : 1
    /// Raw text of the weight field, shown in the currently selected system's unit.
    var weightText: String = ""
    /// Canonical weight in kilograms; `nil` when the field is empty/unparseable.
    var userWeightKg: Double?

    // MARK: Apple Health
    var shouldSyncWorkouts = false
    var shouldSyncWeight = false
    var shouldAutoImportWorkouts = false

    // MARK: Permissions
    var locationPermissionGranted = false
    var motionPermissionGranted = false
    var appleHealthPermissionGranted = false

    // MARK: Derived

    var weightUnitSymbol: String {
        CustomMeasurementFormatting.string(forUnit: preferredMeasurementSystem == 0 ? UnitMass.kilograms : UnitMass.pounds, short: true)
    }

    var formalitiesValid: Bool { agreedToPrivacyPolicy && agreedToTermsOfService }
    var userInfoValid: Bool { userWeightKg != nil }
    var syncEnabled: Bool { shouldSyncWorkouts || shouldSyncWeight }

    /// Location and motion are always required; Apple Health is required only when the user opted into syncing.
    var permissionsValid: Bool {
        locationPermissionGranted && motionPermissionGranted && (appleHealthPermissionGranted || !syncEnabled)
    }

    // MARK: Weight conversion (driven from the view via .onChange)

    /// Re-derives the canonical kilogram weight from the field text under the current system.
    func recomputeWeightKg() {
        if let parsed = CustomNumberFormatting.number(from: weightText) {
            let unit: UnitMass = preferredMeasurementSystem == 0 ? .kilograms : .pounds
            userWeightKg = UnitConversion.conversion(of: parsed, from: unit, to: UnitMass.kilograms)
        } else {
            userWeightKg = nil
        }
    }

    /// When the Metric/Imperial control flips, re-displays the same physical weight in the new unit.
    func reformatWeightAfterSystemChange() {
        guard let kg = userWeightKg else { return }
        let unit: UnitMass = preferredMeasurementSystem == 0 ? .kilograms : .pounds
        let value = UnitConversion.conversion(of: kg, from: UnitMass.kilograms, to: unit)
        weightText = Self.editableString(from: value)   // triggers recompute via the view's onChange
    }

    // MARK: Completion

    /// Faithful port of the legacy `SetupViewController.finishSetup()`, with one fix: imperial altitude is set
    /// to `.feet` (a supported value) instead of the out-of-range `.yards` the legacy wrote.
    func finish() {
        UserPreferences.name.value = username.isEmpty ? nil : username
        UserPreferences.weight.value = userWeightKg

        let localeDefaultSystem = Locale.current.usesMetricSystem ? 0 : 1
        if localeDefaultSystem != preferredMeasurementSystem {
            switch preferredMeasurementSystem {
            case 0: // user chose metric
                UserPreferences.distanceMeasurementType.value = .kilometers
                UserPreferences.altitudeMeasurementType.value = .meters
                UserPreferences.speedMeasurementType.value = .kilometersPerHour
                UserPreferences.weightMeasurementType.value = .kilograms
            default: // user chose imperial
                UserPreferences.distanceMeasurementType.value = .miles
                UserPreferences.altitudeMeasurementType.value = .feet   // fixed (legacy wrote .yards, out of range)
                UserPreferences.speedMeasurementType.value = .milesPerHour
                UserPreferences.weightMeasurementType.value = .pounds
            }
        }

        UserPreferences.synchronizeWorkoutsWithAppleHealth.value = shouldSyncWorkouts
        UserPreferences.synchronizeWeightWithAppleHealth.value = shouldSyncWeight
        UserPreferences.automaticallyImportNewHealthWorkouts.value = shouldAutoImportWorkouts

        UserPreferences.isSetUp.value = true
        HealthStoreManager.setupObservers()
        AppDelegate.lastVersion.value = Config.version
    }

    // MARK: Helpers

    /// Locale-correct but grouping-free formatting, so a value round-trips back through the `.none`-style
    /// `CustomNumberFormatting.number` parser (which reads grouped strings like "1,234" as `nil`).
    private static func editableString(from value: Double, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(for: value) ?? ""
    }
}
