//
//  SettingsState.swift
//
//  OutRun
//
//  Observable view model backing the SwiftUI settings screens. Stored properties mirror the values in
//  `UserPreferences`; they are loaded once in `init()` and written straight back through each `didSet`,
//  so the static preference store stays the single source of truth while SwiftUI gets reactivity for free
//  (e.g. the auto-import row can disable itself the moment `syncWorkouts` flips).
//

import Foundation
import Observation

@MainActor
@Observable
final class SettingsState {

    // MARK: User settings

    /// The users name.
    var name: String {
        didSet { UserPreferences.name.value = name.isEmpty ? nil : name }
    }

    /// The users weight stored in kilograms (the canonical unit used by `UserPreferences.weight`).
    var weight: Double? {
        didSet { UserPreferences.weight.value = weight }
    }

    // MARK: Recording preferences

    var standardWorkoutType: Int {
        didSet { UserPreferences.standardWorkoutType.value = standardWorkoutType }
    }

    var shouldShowMap: Bool {
        didSet { UserPreferences.shouldShowMap.value = shouldShowMap }
    }

    /// The desired GPS accuracy in meters; `nil` represents the system standard, `-1` means GPS is off.
    var gpsAccuracy: Double? {
        didSet { UserPreferences.gpsAccuracy.value = gpsAccuracy }
    }

    var displayRollingSpeed: Bool {
        didSet { UserPreferences.displayRollingSpeed.value = displayRollingSpeed }
    }

    // MARK: Apple Health preferences

    var syncWorkouts: Bool {
        didSet { UserPreferences.synchronizeWorkoutsWithAppleHealth.value = syncWorkouts }
    }

    var syncWeight: Bool {
        didSet { UserPreferences.synchronizeWeightWithAppleHealth.value = syncWeight }
    }

    var autoImport: Bool {
        didSet { UserPreferences.automaticallyImportNewHealthWorkouts.value = autoImport }
    }

    // MARK: Unit preferences

    /// Each unit preference is exposed as its concrete `Unit` subtype; `nil` means "use the system standard".
    var distanceUnit: UnitLength? {
        didSet { UserPreferences.distanceMeasurementType.value = distanceUnit }
    }

    var altitudeUnit: UnitLength? {
        didSet { UserPreferences.altitudeMeasurementType.value = altitudeUnit }
    }

    var speedUnit: UnitSpeed? {
        didSet { UserPreferences.speedMeasurementType.value = speedUnit }
    }

    var energyUnit: UnitEnergy? {
        didSet { UserPreferences.energyMeasurementType.value = energyUnit }
    }

    var weightUnit: UnitMass? {
        didSet { UserPreferences.weightMeasurementType.value = weightUnit }
    }

    // MARK: Init

    init() {
        self.name = UserPreferences.name.value ?? ""
        self.weight = UserPreferences.weight.value

        self.standardWorkoutType = UserPreferences.standardWorkoutType.value
        self.shouldShowMap = UserPreferences.shouldShowMap.value
        self.gpsAccuracy = UserPreferences.gpsAccuracy.value
        self.displayRollingSpeed = UserPreferences.displayRollingSpeed.value

        self.syncWorkouts = UserPreferences.synchronizeWorkoutsWithAppleHealth.value
        self.syncWeight = UserPreferences.synchronizeWeightWithAppleHealth.value
        self.autoImport = UserPreferences.automaticallyImportNewHealthWorkouts.value

        self.distanceUnit = UserPreferences.distanceMeasurementType.value
        self.altitudeUnit = UserPreferences.altitudeMeasurementType.value
        self.speedUnit = UserPreferences.speedMeasurementType.value
        self.energyUnit = UserPreferences.energyMeasurementType.value
        self.weightUnit = UserPreferences.weightMeasurementType.value
    }

    // MARK: Convenience accessors

    /// The standard workout type resolved to its enum value for display.
    var standardWorkoutTypeValue: Workout.WorkoutType {
        Workout.WorkoutType(rawValue: standardWorkoutType)
    }

    /// The weight measurement preference, used for unit symbols / conversions in the UI.
    var weightMeasurementType: MeasurementUserPreference<UnitMass> {
        UserPreferences.weightMeasurementType
    }
}
