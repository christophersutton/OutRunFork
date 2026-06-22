//
//  MigrationTests.swift
//
//  OutRun
//  Copyright (C) 2022 Tim Fraedrich <timfraedrich@icloud.com>
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

final class MigrationTests: XCTestCase {

    func testV3ToV4HeartRateMigrationAvoidsForceCastAndPreservesDoubleConversion() throws {
        let outRunV4Source = try sourceContents(at: "OutRun/Models/Data/DataModels/Versions/OutRunV4.swift")

        XCTAssertFalse(
            outRunV4Source.contains("sourceObject[\"heartRate\"] as! Double"),
            "The V3to4 -> V4 heart-rate migration must not force-cast legacy values."
        )
        XCTAssertTrue(
            outRunV4Source.contains("sourceObject[\"heartRate\"] as? Double"),
            "The migration should safely accept valid legacy Double heart-rate values."
        )
        XCTAssertTrue(
            outRunV4Source.contains("destinationObject[\"heartRate\"] = Int(heartRate)"),
            "Valid legacy Double heart-rate values should still migrate to the V4 Int field."
        )
    }

    func testMigrationTestsAreNotXcodeTemplatePlaceholders() throws {
        let migrationTestsSource = try sourceContents(at: "UnitTests/MigrationTests.swift")

        let templateFunctionalTestName = "func test" + "Example()"
        let templatePerformanceTestName = "func test" + "PerformanceExample()"
        let templateFunctionalComment = "This is an example of a " + "functional test case"

        XCTAssertFalse(migrationTestsSource.contains(templateFunctionalTestName))
        XCTAssertFalse(migrationTestsSource.contains(templatePerformanceTestName))
        XCTAssertFalse(migrationTestsSource.contains(templateFunctionalComment))
    }

    private func sourceContents(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

}
