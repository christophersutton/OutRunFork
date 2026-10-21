import XCTest
#if STORAGE_VALIDATION_PORTABLE
@testable import StorageValidationHarness
#else
@testable import MoveFeet
#endif

final class BackupValidationTests: XCTestCase {
    func testV4JSONRoundtripPreservesAllCurrentFieldsAndIdentities() throws {
        let workout = StorageFixtures.workout()
        let event = StorageFixtures.event(workouts: [workout])
        let encoded = try JSONEncoder().encode(Backup(workouts: [workout], events: [event]))
        let decoded = try JSONDecoder().decode(Backup.self, from: encoded)
        XCTAssertEqual(decoded.version, "V4")
        try BackupValidation.validate(workouts: decoded.workoutData, events: decoded.eventData)
        XCTAssertEqual(try json(workout), try json(decoded.workoutData[0]))
        XCTAssertEqual(try json(event), try json(decoded.eventData[0]))
        XCTAssertEqual(decoded.eventData[0].workouts, [workout.uuid!])
        XCTAssertEqual(decoded.workoutData[0]._pauses[0].uuid, workout._pauses[0].uuid)
        XCTAssertEqual(decoded.workoutData[0]._routeData[0].uuid, workout._routeData[0].uuid)
        XCTAssertEqual(decoded.workoutData[0]._heartRates[0].uuid, workout._heartRates[0].uuid)
        XCTAssertEqual(decoded.workoutData[0]._workoutEvents[0].uuid, workout._workoutEvents[0].uuid)
        XCTAssertFalse(decoded.workoutData[0].finishedRecording)
    }

    func testEmptyBackupIsValid() throws {
        try BackupValidation.validate(workouts: [], events: [])
    }

    func testUnavailableCoreLocationMeasurementsArePreserved() throws {
        let workout = StorageFixtures.workout()
        workout._routeData[0].horizontalAccuracy = -1
        try BackupValidation.validate(workouts: [workout], events: [])
    }

    func testMissingTopLevelIdentitiesAreRejected() {
        let workout = StorageFixtures.workout()
        workout.uuid = nil
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [workout], events: []))
        let event = StorageFixtures.event(workouts: [])
        event.uuid = nil
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [], events: [event]))
    }

    func testInvalidWorkoutValuesAreRejectedEvenAfterAValidWorkout() {
        let changes: [(TempWorkout) -> Void] = [
            { $0.distance = -1 }, { $0.activeDuration = .nan }, { $0.pauseDuration = .infinity },
            { $0.ascend = -1 }, { $0.descend = .infinity }, { $0.steps = -1 },
            { $0.burnedEnergy = -1 }, { $0.endDate = $0.startDate.addingTimeInterval(-1) },
            { $0.startDate = Date(timeIntervalSinceReferenceDate: .nan) }
        ]
        for change in changes {
            let invalid = StorageFixtures.workout()
            change(invalid)
            XCTAssertThrowsError(try BackupValidation.validate(workouts: [StorageFixtures.workout(), invalid], events: []))
        }
    }

    func testInvalidNestedDataIsRejected() {
        let changes: [(TempWorkout) -> Void] = [
            { $0._routeData[0].latitude = 91 }, { $0._routeData[0].longitude = -181 },
            { $0._routeData[0].altitude = .nan }, { $0._routeData[0].speed = .infinity },
            { $0._routeData[0].timestamp = Date(timeIntervalSinceReferenceDate: .infinity) },
            { $0._heartRates[0].heartRate = -1 },
            { $0._pauses[0].endDate = $0._pauses[0].startDate.addingTimeInterval(-1) },
            { $0._workoutEvents[0].timestamp = Date(timeIntervalSinceReferenceDate: .nan) },
            { $0._heartRates[0].uuid = nil }, { $0._routeData[0].uuid = nil },
            { $0._pauses[0].uuid = nil }, { $0._workoutEvents[0].uuid = nil }
        ]
        for change in changes {
            let workout = StorageFixtures.workout()
            change(workout)
            XCTAssertThrowsError(try BackupValidation.validate(workouts: [workout], events: []))
        }
    }

    func testRepeatedOrSharedSampleIdentitiesAreRejected() {
        let first = StorageFixtures.workout()
        let second = StorageFixtures.workout()
        second._pauses[0].uuid = first._pauses[0].uuid
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [first, second], events: []))
        first._heartRates.append(first._heartRates[0])
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [first], events: []))
    }

    func testRepeatedWorkoutIdentitiesCanBeSkippedWithoutChangingSampleIdentities() throws {
        let workout = StorageFixtures.workout()
        try BackupValidation.validate(workouts: [workout, workout], events: [])
    }

    func testInvalidEventDatesAreRejected() {
        let event = StorageFixtures.event(workouts: [])
        event.endDate = StorageFixtures.start.addingTimeInterval(-1)
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [], events: [event]))
        event.endDate = nil
        event.startDate = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [], events: [event]))
    }

    func testInvalidDuplicateIsStillRejected() {
        let valid = StorageFixtures.workout()
        let invalid = StorageFixtures.workout(id: valid.uuid!)
        invalid.distance = -1
        XCTAssertThrowsError(try BackupValidation.validate(workouts: [valid, invalid], events: []))
    }

    private func json<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(object)
    }
}
