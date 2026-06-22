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
import XCTest
@testable import OutRun

final class MigrationTests: XCTestCase {

    func testV3ToV4HeartRateMigrationConvertsLegacyDoubleSamples() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutRunMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appendingPathComponent("OutRun.sqlite")
        try seedV3to4Store(at: storeURL, heartRate: 142.9)

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

        XCTAssertEqual(migratedSamples.count, 1)
        XCTAssertEqual(migratedSamples.first?._heartRate.value, 142)
    }

    func testV4HeartRateMigrationDoesNotForceCastLegacyValues() throws {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()
        let v4SourceURL = repositoryRoot.appendingPathComponent("OutRun/Models/Data/DataModels/Versions/OutRunV4.swift")
        let v4Source = try String(contentsOf: v4SourceURL, encoding: .utf8)
        let forceCast = "as" + "! Double"

        XCTAssertFalse(
            v4Source.contains(forceCast),
            "OutRunV4 migration must not force-cast legacy heart-rate values; migration code should tolerate unexpected persisted values."
        )
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
