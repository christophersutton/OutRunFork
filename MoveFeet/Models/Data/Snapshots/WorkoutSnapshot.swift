//
//  WorkoutSnapshot.swift
//
//  OutRun
//
//  An immutable, value-type snapshot of a workout for the UI layer.
//
//  Persistence uses thread-confined CoreStore objects (`Workout`); reading them off their designated
//  queue traps at runtime ("accessed outside its designated queue"). A snapshot is built ONCE, on the
//  object's queue, and is thereafter a plain value any view or thread can hold safely. This boundary
//  decouples the SwiftUI layer from CoreStore's threading model.
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

    /// Builds a snapshot by reading every needed field from a CoreStore `Workout`.
    /// MUST be called on the workout's designated queue (e.g. the main queue for `ListMonitor` objects,
    /// or inside a `dataStack.perform` transaction for transaction-bound objects). Use raw CoreStore
    /// properties here: the public `ORWorkoutInterface` accessors wrap every scalar in `threadSafeSyncReturn`,
    /// which is unnecessary on the monitor queue and expensive when rebuilding a large timeline.
    init(_ workout: Workout) {
        self.id = workout._uuid.value ?? UUID()
        self.workoutType = workout._workoutType.value
        self.distance = workout._distance.value
        self.startDate = workout._startDate.value
        self.endDate = workout._endDate.value
        self.activeDuration = workout._activeDuration.value
        self.pauseDuration = workout._pauseDuration.value
        self.steps = workout._steps.value
        self.burnedEnergy = workout._burnedEnergy.value
        self.ascend = workout._ascend.value
        self.descend = workout._descend.value
        self.isRace = workout._isRace.value
        self.comment = workout._comment.value
        self.isUserModified = workout._isUserModified.value
        self.healthKitUUID = workout._healthKitUUID.value
        self.dayIdentifier = workout._dayIdentifier.value
        self.hasRouteData = workout.hasRouteData
    }
}
