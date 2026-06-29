//
//  HealthKitBlockingQueryTests.swift
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

import XCTest

final class HealthKitBlockingQueryTests: XCTestCase {

    func testHealthUUIDQueryPathDoesNotUseSynchronousMainHops() throws {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()

        let dataManagerURL = repositoryRoot.appendingPathComponent("MoveFeet/Models/Data/DataManager+Query.swift")
        let dataManagerSource = try String(contentsOf: dataManagerURL)
        let healthUUIDQuery = try XCTUnwrap(
            dataManagerSource.range(of: "public static func queryExistingHealthUUIDs")
        )
        let healthUUIDQuerySource = String(dataManagerSource[healthUUIDQuery.lowerBound...])

        XCTAssertFalse(
            healthUUIDQuerySource.contains("threadSafeSyncReturn"),
            "DataManager.queryExistingHealthUUIDs must use asynchronous CoreStore work, not a synchronous main-thread hop."
        )
        XCTAssertFalse(
            healthUUIDQuerySource.contains(".wait()"),
            "DataManager.queryExistingHealthUUIDs must not block while querying CoreStore."
        )

        let healthKitCallSites = [
            "MoveFeet/Models/HealthKit/HealthStoreManager+Observer.swift",
            "MoveFeet/Models/HealthKit/HealthStoreManager+Query.swift"
        ]

        for sourceFile in healthKitCallSites {
            let fileURL = repositoryRoot.appendingPathComponent(sourceFile)
            let source = try String(contentsOf: fileURL)

            XCTAssertFalse(
                source.contains("DataManager.queryExistingHealthUUIDs()"),
                "\(sourceFile) must not synchronously query existing HealthKit UUIDs."
            )
        }
    }

    func testHealthKitManagersDoNotSynchronouslyWaitForQueries() throws {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()
        let sourceFiles = [
            "MoveFeet/Models/HealthKit/HealthStoreManager.swift",
            "MoveFeet/Models/HealthKit/HealthStoreManager+Query.swift",
            "MoveFeet/Models/HealthKit/HealthStoreManager+Observer.swift"
        ]
        let blockingWaitCall = "." + "wait" + "()"

        for sourceFile in sourceFiles {
            let fileURL = repositoryRoot.appendingPathComponent(sourceFile)
            let source = try String(contentsOf: fileURL)

            XCTAssertFalse(
                source.contains(blockingWaitCall),
                "\(sourceFile) must not synchronously block HealthKit callback queues."
            )
        }
    }

}
