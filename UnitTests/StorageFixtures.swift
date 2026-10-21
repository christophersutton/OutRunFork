import Foundation
#if STORAGE_VALIDATION_PORTABLE
@testable import StorageValidationHarness
#else
@testable import MoveFeet
#endif

enum StorageFixtures {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func workout(id: UUID = UUID()) -> TempWorkout {
        TempWorkout(
            uuid: id, workoutType: .hiking, distance: 2400, steps: 3210,
            startDate: start, endDate: start.addingTimeInterval(900), burnedEnergy: 180,
            isRace: true, comment: "Synthetic fixture", isUserModified: true,
            healthKitUUID: UUID(), finishedRecording: false,
            ascend: 35, descend: 20, activeDuration: 890, pauseDuration: 10,
            dayIdentifier: "20270115",
            heartRates: [.init(uuid: UUID(), heartRate: 142, timestamp: start.addingTimeInterval(20))],
            routeData: [.init(uuid: UUID(), timestamp: start.addingTimeInterval(20), latitude: 42,
                              longitude: -71, altitude: 18, horizontalAccuracy: 3,
                              verticalAccuracy: -1, speed: -1, direction: -1)],
            pauses: [.init(uuid: UUID(), startDate: start.addingTimeInterval(10),
                           endDate: start.addingTimeInterval(20), pauseType: .manual)],
            workoutEvents: [.init(uuid: UUID(), eventType: .lap, timestamp: start.addingTimeInterval(30))]
        )
    }

    static func event(workouts: [TempWorkout], id: UUID = UUID()) -> TempEvent {
        TempEvent(uuid: id, title: "Synthetic event", comment: "No personal data",
                  startDate: start, endDate: start.addingTimeInterval(900),
                  workouts: workouts.compactMap(\.uuid))
    }
}
