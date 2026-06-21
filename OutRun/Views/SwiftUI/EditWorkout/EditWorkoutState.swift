//
//  EditWorkoutState.swift
//
//  OutRun
//
//  Observable view model backing the SwiftUI edit/create-workout form — the replacement for the UIKit
//  `EditWorkoutController`. It holds plain form state (never a live CoreStore object) and owns the save
//  logic that was previously buried in the controller: building a `TempWorkout`/`NewWorkout` and routing
//  it through `DataManager` plus the optional Apple Health sync.
//
//  Threading: the view model is `@MainActor`. It re-resolves the live `Workout` only at save time, on the
//  main queue, via `DataManager.queryObject` (the same pattern `WorkoutDetailView` uses), and never holds
//  it across the form's lifetime. `DataManager` write completions are hopped back to main before any state
//  mutation, mirroring `WorkoutDetailView.toggleAppleHealth`.
//
//  Notable fix vs. the legacy controller: the duration was seeded with `endDate.distance(to: startDate)`,
//  i.e. `start - end`, which is negative for any normal workout. Here it is seeded as the (positive)
//  `endDate - startDate`.
//

import Foundation
import Observation

@MainActor
@Observable
final class EditWorkoutState {

    enum Mode {
        /// Create a brand-new manual workout.
        case create
        /// Edit the existing workout with this id.
        case edit(UUID)
    }

    // MARK: Stored form state

    @ObservationIgnored let mode: Mode

    /// The workout types offered in the picker, plus the existing type when needed so editing never
    /// silently reclassifies it.
    @ObservationIgnored let availableTypes: [Workout.WorkoutType]

    var workoutType: Workout.WorkoutType

    /// Raw text of the distance field, shown in the user's preferred unit (km/mi).
    var distanceText: String
    /// Raw text of the steps/strokes field.
    var stepsText: String

    var startDate: Date

    var durationHours: Int
    var durationMinutes: Int
    var durationSeconds: Int

    var isRace: Bool
    var comment: String

    /// Set to surface a blocking alert; cleared when the alert is dismissed.
    var errorMessage: String?

    // MARK: Init / seeding

    init(mode: Mode) {
        self.mode = mode

        // Defaults (create mode).
        var seededType = Workout.WorkoutType.running
        var seededDistanceText = ""
        var seededStepsText = ""
        var seededStart = Date()
        var seededDuration: TimeInterval = 0
        var seededRace = false
        var seededComment = ""

        if case .edit(let id) = mode, let workout: Workout = DataManager.queryObject(from: id) {
            // Reading these accessors is safe here: the object is main-context and we are on the main actor.
            seededType = workout.workoutType

            let preferredDistance = UserPreferences.distanceMeasurementType.convert(fromValue: workout.distance / 1000, toPrefered: true)
            seededDistanceText = Self.editableString(from: preferredDistance, fractionDigits: 2)

            if let steps = workout.steps {
                seededStepsText = Self.editableString(from: Double(steps), fractionDigits: 0)
            }

            seededStart = workout.startDate
            seededDuration = max(0, workout.endDate.timeIntervalSince(workout.startDate))   // fixed sign
            seededRace = workout.isRace
            seededComment = workout.comment ?? ""
        }

        self.workoutType = seededType
        self.distanceText = seededDistanceText
        self.stepsText = seededStepsText
        self.startDate = seededStart
        self.durationHours = Int(seededDuration) / 3600
        self.durationMinutes = (Int(seededDuration) % 3600) / 60
        self.durationSeconds = Int(seededDuration) % 60
        self.isRace = seededRace
        self.comment = seededComment

        var types = Workout.WorkoutType.supportedTypes
        if !types.contains(seededType) { types.append(seededType) }
        self.availableTypes = types
    }

    /// Formats a seed value for an editable text field: locale-correct decimal separator but **no** grouping
    /// separators. The shared `CustomNumberFormatting.string` uses grouping (e.g. "12,000"), which the
    /// `.none`-style `CustomNumberFormatting.number` parser then reads back as `nil` — so a seeded value the
    /// user never touches would otherwise be wiped on save. A grouping-free seed round-trips cleanly.
    private static func editableString(from value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(for: value) ?? ""
    }

    // MARK: Derived values

    var title: String {
        switch mode {
        case .create: return LS["EditWorkoutController.NewWorkout"]
        case .edit:   return LS["EditWorkoutController.EditWorkout"]
        }
    }

    /// Symbol for the distance field's trailing unit label (km/mi).
    var distanceUnitSymbol: String {
        CustomMeasurementFormatting.string(forUnit: UserPreferences.distanceMeasurementType.safeValue, short: true)
    }

    /// Label for the steps field.
    var stepsFieldTitle: String {
        LS["Workout.Steps"]
    }

    /// Distance in the canonical standard unit (kilometers), parsed from the preferred-unit text field.
    /// `nil` when the field is empty or unparseable.
    var distanceKilometers: Double? {
        guard let parsed = CustomNumberFormatting.number(from: distanceText) else { return nil }
        return UserPreferences.distanceMeasurementType.convert(fromValue: parsed, toPrefered: false, rounded: false)
    }

    var steps: Int? {
        guard let parsed = CustomNumberFormatting.number(from: stepsText) else { return nil }
        return Int(parsed)
    }

    var duration: TimeInterval {
        TimeInterval(durationHours * 3600 + durationMinutes * 60 + durationSeconds)
    }

    /// Save is allowed only with a parseable distance, a non-zero duration, and an end time that is not in
    /// the future — the exact gate the legacy controller used (now evaluated immediately, so a valid
    /// existing workout shows an enabled Save on first appearance).
    var isValid: Bool {
        distanceKilometers != nil && duration != 0 && startDate.addingTimeInterval(duration) <= Date()
    }

    // MARK: Save

    /// Persists the workout. On a successful database write, `completion` is called on the main queue with the
    /// resulting workout's id and an optional Apple Health error message: `nil` means the (optional) HealthKit
    /// sync also succeeded, while a non-nil string is the localized error the caller should surface before
    /// finalizing (the DB write already succeeded either way, so the id is always valid here). On a database
    /// failure, `errorMessage` is set and `completion` is **not** called (the form stays open to retry).
    func save(completion: @escaping (_ workoutID: UUID, _ healthError: String?) -> Void) {
        let endDate = startDate.addingTimeInterval(duration)
        let distanceInMeters = (distanceKilometers ?? 0) * 1000
        let commentValue = comment.isEmpty ? nil : comment
        let syncEnabled = UserPreferences.synchronizeWorkoutsWithAppleHealth.value

        switch mode {
        case .edit(let id):
            guard let workout: Workout = DataManager.queryObject(from: id) else {
                errorMessage = LS["EditWorkoutController.SaveWorkout.Error"]
                return
            }

            var tempWorkout = TempWorkout(from: workout)
            tempWorkout.workoutType = workoutType
            tempWorkout.startDate = startDate
            tempWorkout.endDate = endDate
            tempWorkout.distance = distanceInMeters
            tempWorkout.steps = steps
            tempWorkout.isRace = isRace
            tempWorkout.comment = commentValue

            DataManager.updateWorkout(object: tempWorkout) { _, error, updated in
                DispatchQueue.main.async {
                    guard let updated = updated, error == nil, let uuid = updated.uuid else {
                        self.errorMessage = LS["EditWorkoutController.SaveWorkout.Error"]
                        return
                    }
                    guard syncEnabled else { completion(uuid, nil); return }
                    HealthStoreManager.updateHealthWorkout(for: updated) { healthError in
                        DispatchQueue.main.async {
                            if healthError != nil {
                                // Drop the now-stale health reference (matches the legacy controller).
                                if let healthKitUUID = updated.healthKitUUID {
                                    DataManager.removeHealthReference(reference: healthKitUUID)
                                }
                                completion(uuid, LS["EditWorkoutController.AlterWorkout.AppleHealth.Error"])
                            } else {
                                completion(uuid, nil)
                            }
                        }
                    }
                }
            }

        case .create:
            let newWorkout = NewWorkout(
                workoutType: workoutType,
                distance: distanceInMeters,
                steps: steps,
                startDate: startDate,
                endDate: endDate,
                isRace: isRace,
                comment: commentValue,
                isUserModified: true,
                finishedRecording: true,
                heartRates: [],
                routeData: [],
                pauses: [],
                workoutEvents: []
            )

            DataManager.saveWorkout(object: newWorkout) { _, error, saved in
                DispatchQueue.main.async {
                    guard let saved = saved, error == nil, let uuid = saved.uuid else {
                        self.errorMessage = LS["EditWorkoutController.SaveWorkout.Error"]
                        return
                    }
                    guard syncEnabled else { completion(uuid, nil); return }
                    HealthStoreManager.saveHealthWorkout(for: saved) { healthError, _ in
                        DispatchQueue.main.async {
                            completion(uuid, healthError != nil ? LS["EditWorkoutController.SaveWorkout.AppleHealth.Error"] : nil)
                        }
                    }
                }
            }
        }
    }
}
