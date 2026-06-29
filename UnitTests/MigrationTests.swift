//
//  MigrationTests.swift
//
//  OutRun
//  Copyright (C) 2026 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import CoreStore
import SQLite3
import XCTest
@testable import MoveFeet

final class MigrationTests: XCTestCase {

    private static var cleanedTemporaryStoreRoot = false

    func testV3ToV4HeartRateMigrationConvertsLegacyDoubleSamples() throws {
        try withTemporaryStoreURL { storeURL in
            try seedV3to4Store(at: storeURL, heartRate: 142.9)
            try assertMigratedHeartRates(in: storeURL, equal: [142])
        }
    }

    func testV3ToV4HeartRateMigrationFallsBackForMalformedLegacySamples() throws {
        try withTemporaryStoreURL { storeURL in
            try seedV3to4Store(at: storeURL, heartRate: 142.9)
            try replaceStoredHeartRate(at: storeURL, with: "not-a-number")
            try assertMigratedHeartRates(in: storeURL, equal: [0])
        }
    }

    func testV4HeartRateMigrationConvertsSupportedLegacyValues() {
        XCTAssertEqual(OutRunV4.migratedHeartRate(from: 142.9), 142)
        XCTAssertEqual(OutRunV4.migratedHeartRate(from: NSNumber(value: 143.8)), 143)
        XCTAssertEqual(OutRunV4.migratedHeartRate(from: nil), 0)
        XCTAssertEqual(OutRunV4.migratedHeartRate(from: "142.9"), 0)
    }

    func testV4HeartRateMigrationDoesNotForceCastLegacyValues() throws {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()
        let v4SourceURL = repositoryRoot.appendingPathComponent("MoveFeet/Models/Data/DataModels/Versions/OutRunV4.swift")
        let v4Source = try String(contentsOf: v4SourceURL, encoding: .utf8)
        let forceCast = "as" + "! Double"

        XCTAssertFalse(
            v4Source.contains(forceCast),
            "OutRunV4 migration must not force-cast legacy heart-rate values; migration code should tolerate unexpected persisted values."
        )
    }

    func testTempV3BackupWorkoutEventConversionMatchesV3ToV4MigrationShape() throws {
        let tempV3Source = try tempV3Source()

        XCTAssertFalse(
            tempV3Source.contains("fatalError()"),
            "TempV3 backup workout-event conversion must not crash on legacy event values that the CoreStore V3to4 migration imports."
        )
        XCTAssertTrue(
            tempV3Source.contains("eventType - 4"),
            "TempV3 backup workout-event conversion must map legacy non-pause event types with eventType - 4, matching OutRunV4 V3to4 migration semantics."
        )
    }

    func testTempV3BackupWorkoutEventConversionMapsLegacyNonPauseEvents() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(TempV3.WorkoutEvent(uuid: nil, eventType: 4, startDate: timestamp, endDate: timestamp).asTemp.eventType, .lap)
        XCTAssertEqual(TempV3.WorkoutEvent(uuid: nil, eventType: 5, startDate: timestamp, endDate: timestamp).asTemp.eventType, .marker)
        XCTAssertEqual(TempV3.WorkoutEvent(uuid: nil, eventType: 6, startDate: timestamp, endDate: timestamp).asTemp.eventType, .segment)
        XCTAssertEqual(TempV3.WorkoutEvent(uuid: nil, eventType: 99, startDate: timestamp, endDate: timestamp).asTemp.eventType, .unknown)
    }

    func testTempV3BackupWorkoutConversionKeepsPauseEventsOutOfWorkoutEvents() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(60)
        let pauseStart = start.addingTimeInterval(10)
        let pauseEnd = start.addingTimeInterval(20)
        let lapDate = start.addingTimeInterval(30)

        let workout = TempV3.Workout(
            uuid: nil,
            workoutType: Workout.WorkoutType.running.rawValue,
            startDate: start,
            endDate: end,
            distance: 100,
            steps: nil,
            isRace: false,
            isUserModified: false,
            comment: nil,
            burnedEnergy: nil,
            healthKitUUID: nil,
            workoutEvents: [
                TempV3.WorkoutEvent(uuid: nil, eventType: 0, startDate: pauseStart, endDate: pauseStart),
                TempV3.WorkoutEvent(uuid: nil, eventType: 2, startDate: pauseEnd, endDate: pauseEnd),
                TempV3.WorkoutEvent(uuid: nil, eventType: 4, startDate: lapDate, endDate: lapDate)
            ],
            locations: [],
            heartRates: []
        )

        let converted = workout.asTemp

        XCTAssertEqual(converted.pauses.count, 1)
        XCTAssertEqual(converted.pauses.first?.pauseType, .manual)
        XCTAssertEqual(converted.workoutEvents.map(\.eventType), [.lap])
    }

    private func tempV3Source() throws -> String {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()
        let tempV3SourceURL = repositoryRoot.appendingPathComponent("MoveFeet/Models/Data/Temp/Versions/TempV3.swift")
        return try String(contentsOf: tempV3SourceURL, encoding: .utf8)
    }

    private func withTemporaryStoreURL(_ body: (URL) throws -> Void) throws {
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutRunMigrationTests", isDirectory: true)

        if !Self.cleanedTemporaryStoreRoot {
            try? FileManager.default.removeItem(at: storeRoot)
            Self.cleanedTemporaryStoreRoot = true
        }

        let storeDirectory = storeRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        try body(storeDirectory.appendingPathComponent("OutRun.sqlite"))
    }

    private func seedV3to4Store(at storeURL: URL, heartRate: Double) throws {
        let seedStack = DataStack(oRMigrationChain: OutRunV3to4.migrationChain, oRDataModel: OutRunV3to4.self)

        try addStorage(
            SQLiteStore(
                fileURL: storeURL,
                migrationMappingProviders: OutRunV3to4.migrationChain.compactMap { $0.mappingProvider },
                localStorageOptions: .none
            ),
            to: seedStack
        )

        try seedStack.perform(synchronous: { transaction in
            let sample = transaction.create(Into<OutRunV3to4.WorkoutHeartRateDataSample>())
            sample.uuid .= UUID()
            sample.timestamp .= Date(timeIntervalSince1970: 1_700_000_000)
            sample.heartRate .= heartRate
        })
    }

    private func replaceStoredHeartRate(at storeURL: URL, with value: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw sqliteError(database, message: "Failed to open seeded migration store")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "UPDATE ZWORKOUTHEARTRATESAMPLE SET ZHEARTRATE = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database, message: "Failed to prepare heart-rate corruption statement")
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = value.withCString { valuePointer -> Int32 in
            guard sqlite3_bind_text(statement, 1, valuePointer, -1, nil) == SQLITE_OK else {
                return sqlite3_errcode(database)
            }

            return sqlite3_step(statement)
        }

        guard stepResult == SQLITE_DONE else {
            throw sqliteError(database, message: "Failed to corrupt seeded heart-rate value")
        }
    }

    private func assertMigratedHeartRates(
        in storeURL: URL,
        equal expectedHeartRates: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let migratedStack = DataStack(oRMigrationChain: OutRunV4.migrationChain, oRDataModel: OutRunV4.self)

        try addStorage(
            SQLiteStore(
                fileURL: storeURL,
                migrationMappingProviders: OutRunV4.migrationChain.compactMap { $0.mappingProvider },
                localStorageOptions: .none
            ),
            to: migratedStack
        )

        let migratedSamples = try migratedStack.fetchAll(From<OutRunV4.WorkoutHeartRateDataSample>())
        let heartRates = migratedSamples.map { $0._heartRate.value }

        XCTAssertEqual(heartRates, expectedHeartRates, file: file, line: line)
    }

    private func sqliteError(_ database: OpaquePointer?, message: String) -> NSError {
        let detail = database.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "unknown SQLite error"
        return NSError(
            domain: "MigrationTests.SQLite",
            code: Int(sqlite3_errcode(database)),
            userInfo: [NSLocalizedDescriptionKey: "\(message): \(detail)"]
        )
    }

    private func addStorage(_ storage: SQLiteStore, to dataStack: DataStack) throws {
        let storageExpectation = expectation(description: "Add SQLite storage")
        var setupResult: SetupResult<SQLiteStore>?

        _ = dataStack.addStorage(storage) { result in
            setupResult = result
            storageExpectation.fulfill()
        }

        wait(for: [storageExpectation], timeout: 10)

        switch try XCTUnwrap(setupResult) {
        case .success:
            break
        case .failure(let error):
            throw error
        }
    }

}
