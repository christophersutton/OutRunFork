//
//  WorkoutSnapshot.swift
//
//  OutRun
//
//  An immutable, value-type snapshot of a workout for the UI layer.
//
//  Persistence uses thread-confined CoreStore objects (`Workout`); reading them off their designated
//  queue traps at runtime ("accessed outside its designated queue"). A snapshot is built ONCE, on the
//  object's queue, and is thereafter a plain value any view or thread can hold safely. This is the seam
//  that decouples the SwiftUI layer from CoreStore's threading model.
//

import Foundation

struct WorkoutSnapshot: Identifiable, Hashable {

    let id: UUID
    let workoutType: Workout.WorkoutType
    let distance: Double                 // metres
    let startDate: Date
    let endDate: Date
    let activeDuration: TimeInterval
    let pauseDuration: TimeInterval
    let steps: Int?
    let burnedEnergy: Double?            // kcal
    let ascend: Double                   // metres
    let descend: Double                  // metres
    let isRace: Bool
    let comment: String?
    let isUserModified: Bool
    let healthKitUUID: UUID?
    let dayIdentifier: String
    let hasRouteData: Bool
    let hasHeartRateData: Bool

    /// Builds a snapshot by reading every needed field from a CoreStore `Workout`.
    /// MUST be called on the workout's designated queue (e.g. the main queue for `ListMonitor` objects,
    /// or inside a `dataStack.perform` transaction for transaction-bound objects).
    init(_ workout: Workout) {
        self.id = workout.uuid ?? UUID()
        self.workoutType = workout.workoutType
        self.distance = workout.distance
        self.startDate = workout.startDate
        self.endDate = workout.endDate
        self.activeDuration = workout.activeDuration
        self.pauseDuration = workout.pauseDuration
        self.steps = workout.steps
        self.burnedEnergy = workout.burnedEnergy
        self.ascend = workout.ascend
        self.descend = workout.descend
        self.isRace = workout.isRace
        self.comment = workout.comment
        self.isUserModified = workout.isUserModified
        self.healthKitUUID = workout.healthKitUUID
        self.dayIdentifier = workout.dayIdentifier
        self.hasRouteData = workout.hasRouteData
        self.hasHeartRateData = workout.hasHeartRateData
    }
}
