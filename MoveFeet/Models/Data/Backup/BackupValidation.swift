import Foundation

/// Validate the whole payload before opening a write transaction. Never generate identities while
/// restoring a current backup: missing identities would make a second restore create new records.
enum BackupValidation {
    struct InvalidData: LocalizedError {
        let field: String
        var errorDescription: String? { "The backup contains invalid data (\(field))." }
    }

    static func validate(workouts: [TempWorkout], events: [TempEvent]) throws {
        func require(_ condition: Bool, _ field: String) throws {
            if !condition { throw InvalidData(field: field) }
        }
        func nonnegative(_ value: Double) -> Bool { value.isFinite && value >= 0 }
        func valid(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }

        var seenWorkouts = Set<UUID>()
        var childIDs = [Set<UUID>](repeating: [], count: 4)
        for workout in workouts {
            try require(workout.uuid != nil, "workout identity")
            try require(valid(workout.startDate) && valid(workout.endDate) && workout.startDate <= workout.endDate, "workout dates")
            try require([workout.distance, workout.ascend, workout.descend, workout.activeDuration, workout.pauseDuration].allSatisfy(nonnegative), "workout measurements")
            try require(workout.steps.map { $0 >= 0 } ?? true, "steps")
            try require(workout.burnedEnergy.map(nonnegative) ?? true, "energy")

            let isNewIdentity = seenWorkouts.insert(workout.uuid!).inserted
            func checkIDs(_ ids: [UUID?], kind: Int) throws {
                var local = Set<UUID>()
                for id in ids {
                    guard let id else { throw InvalidData(field: "sample identity") }
                    try require(local.insert(id).inserted, "repeated sample identity")
                    if isNewIdentity {
                        try require(childIDs[kind].insert(id).inserted, "sample shared by workouts")
                    }
                }
            }
            try checkIDs(workout._pauses.map(\.uuid), kind: 0)
            try checkIDs(workout._workoutEvents.map(\.uuid), kind: 1)
            try checkIDs(workout._routeData.map(\.uuid), kind: 2)
            try checkIDs(workout._heartRates.map(\.uuid), kind: 3)

            for pause in workout._pauses {
                try require(valid(pause.startDate) && valid(pause.endDate) && pause.startDate <= pause.endDate, "pause dates")
            }
            for event in workout._workoutEvents {
                try require(valid(event.timestamp), "workout event timestamp")
            }
            for sample in workout._routeData {
                try require(valid(sample.timestamp), "route timestamp")
                try require(sample.latitude.isFinite && (-90...90).contains(sample.latitude) && sample.longitude.isFinite && (-180...180).contains(sample.longitude), "route coordinate")
                // Core Location uses negative values to represent unavailable accuracy/speed/course.
                try require([sample.altitude, sample.horizontalAccuracy, sample.verticalAccuracy, sample.speed, sample.direction].allSatisfy(\.isFinite), "route measurements")
            }
            for sample in workout._heartRates {
                try require(valid(sample.timestamp) && sample.heartRate >= 0, "heart rate")
            }
        }

        for event in events {
            try require(event.uuid != nil, "event identity")
            try require(event.startDate.map(valid) ?? true, "event start date")
            try require(event.endDate.map(valid) ?? true, "event end date")
            if let start = event.startDate, let end = event.endDate {
                try require(start <= end, "event dates")
            }
        }
    }
}
