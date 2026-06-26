//
//  WorkoutEditSnapshot.swift
//
//  OutRun
//
//  Immutable raw-value snapshot for seeding the edit-workout SwiftUI form without reading live CoreStore
//  `Workout` public accessors from presentation code. Build inside `DataManager.workoutEditSnapshot(for:)`.
//

import Foundation

struct WorkoutEditSnapshot {
    let workoutType: Workout.WorkoutType
    let distance: Double
    let steps: Int?
    let startDate: Date
    let endDate: Date
    let isRace: Bool
    let comment: String?

    /// MUST be called on the workout's designated CoreStore queue. Reads raw `_x.value` storage only, avoiding
    /// the public accessors that wrap `threadSafeSyncReturn`.
    init(_ workout: Workout) {
        self.workoutType = workout._workoutType.value
        self.distance = workout._distance.value
        self.steps = workout._steps.value
        self.startDate = workout._startDate.value
        self.endDate = workout._endDate.value
        self.isRace = workout._isRace.value
        self.comment = workout._comment.value
    }
}
