import Foundation
import CoreStore

extension DataManager {
    struct RestoreReport {
        let workouts: [Workout]
        let events: [Event]
        let skippedWorkouts: Int
        let skippedEvents: Int

        var importedWorkouts: Int { workouts.count }
        var importedEvents: Int { events.count }
        var summary: String {
            "Imported \(importedWorkouts) workouts and \(importedEvents) events. Skipped \(skippedWorkouts) existing workouts and \(skippedEvents) existing events."
        }
    }

    enum RestoreStage { case workouts, events }

    /// All reads, duplicate decisions, inserts and relationship updates share one transaction queue.
    /// Throwing from a fetch, either stage or the final commit rolls back the complete restore.
    static func restore(
        workouts: [TempWorkout],
        events: [TempEvent],
        in stack: DataStack,
        afterStage: @escaping (RestoreStage) throws -> Void = { _ in },
        completion: @escaping (Result<RestoreReport, Error>) -> Void
    ) {
        let completion = safeClosure(from: completion)
        do {
            try BackupValidation.validate(workouts: workouts, events: events)
        } catch {
            completion(.failure(error))
            return
        }

        stack.perform(asynchronous: { transaction -> RestoreReport in
            var insertedWorkouts: [Workout] = []
            var insertedEvents: [Event] = []
            var skippedWorkouts = 0
            var skippedEvents = 0

            for object in workouts {
                if try transaction.fetchOne(From<Workout>().where(\._uuid == object.uuid)) != nil {
                    skippedWorkouts += 1
                } else {
                    insertedWorkouts.append(insertWorkout(object, in: transaction))
                }
            }
            try afterStage(.workouts)

            for object in events {
                let ids = object.workouts
                let linkedWorkouts = try transaction.fetchAll(
                    From<Workout>().where(Where<Workout>(\._uuid, isMemberOf: ids))
                )
                guard Set(linkedWorkouts.compactMap { $0._uuid.value }) == Set(ids) else {
                    throw BackupValidation.InvalidData(field: "missing event workout")
                }

                if let existing = try transaction.fetchOne(From<Event>().where(\._uuid == object.uuid)) {
                    // Overlapping backups may contain additional members of an existing event.
                    // Keep its current metadata and links, and attach every restored member.
                    let event = transaction.edit(existing)!
                    var members = event._workouts.value
                    for workout in linkedWorkouts where !members.contains(workout) {
                        members.append(workout)
                    }
                    event._workouts .= members.sorted { $0._startDate.value < $1._startDate.value }
                    skippedEvents += 1
                } else {
                    insertedEvents.append(try insertEvent(object, workoutIDs: ids, in: transaction))
                }
            }
            try afterStage(.events)
            return RestoreReport(workouts: insertedWorkouts, events: insertedEvents,
                                 skippedWorkouts: skippedWorkouts, skippedEvents: skippedEvents)
        }) { result in
            switch result {
            case .success(let report):
                completion(.success(RestoreReport(
                    workouts: stack.fetchExisting(report.workouts),
                    events: stack.fetchExisting(report.events),
                    skippedWorkouts: report.skippedWorkouts,
                    skippedEvents: report.skippedEvents
                )))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
