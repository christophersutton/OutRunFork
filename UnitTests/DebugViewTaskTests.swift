//
//  DebugViewTaskTests.swift
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

final class DebugViewTaskTests: XCTestCase {

    func testDebugViewUsesStructuredAsyncDebugSummaryAPI() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let debugViewURL = repositoryRoot.appendingPathComponent("OutRun/Views/SwiftUI/Debug/DebugView.swift")
        let debugViewSource = try String(contentsOf: debugViewURL, encoding: .utf8)
        let loadValuesSource = try sourceSlice(
            in: debugViewSource,
            startingAt: "private func loadValues() async"
        )

        XCTAssertFalse(
            loadValuesSource.contains("Task.detached"),
            "DebugView.loadValues() must use structured async flow instead of Task.detached."
        )
        XCTAssertFalse(
            loadValuesSource.contains("DataManager.fetchCount"),
            "DebugView.loadValues() must not perform direct CoreStore count reads; use DataManager.debugSummary()."
        )
        XCTAssertFalse(
            loadValuesSource.contains("CustomImageCache.mapImageCache.diskSize"),
            "DebugView.loadValues() must not read map cache disk size on the main actor; consume DataManager.DebugSummary.cacheDiskSize."
        )
        XCTAssertTrue(
            loadValuesSource.contains("await DataManager.debugSummary()"),
            "DebugView.loadValues() should await DataManager.debugSummary() for database and cache value data."
        )
        XCTAssertTrue(
            loadValuesSource.contains("summary.cacheDiskSize"),
            "DebugView.loadValues() should update cache UI from DataManager.DebugSummary.cacheDiskSize."
        )

        let dataManagerURL = repositoryRoot.appendingPathComponent("OutRun/Models/Data/DataManager+Query.swift")
        let dataManagerSource = try String(contentsOf: dataManagerURL, encoding: .utf8)
        let debugSummarySource = try sourceSlice(
            in: dataManagerSource,
            startingAt: "public static func debugSummary() async -> DebugSummary"
        )
        let performRange = try XCTUnwrap(
            debugSummarySource.range(of: "dataStack.perform(asynchronous:"),
            "DataManager.debugSummary() should run value reads on CoreStore's asynchronous transaction queue."
        )
        let prePerformSource = String(debugSummarySource[..<performRange.lowerBound])
        let asyncClosureSource = String(debugSummarySource[performRange.lowerBound...])

        XCTAssertTrue(
            dataManagerSource.contains("public struct DebugSummary: Sendable"),
            "DataManager should expose an explicit sendable debug summary value."
        )
        XCTAssertTrue(
            dataManagerSource.contains("public let cacheDiskSize: Int?"),
            "DataManager.DebugSummary should include map cache disk size so DebugView does not read it directly."
        )
        XCTAssertFalse(
            prePerformSource.contains("diskSize"),
            "DataManager.debugSummary() must not perform synchronous disk-size IO before dataStack.perform(asynchronous:)."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("databaseStorageSize: diskSize"),
            "DataManager.debugSummary() should read database disk size inside the asynchronous transaction closure."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("cacheDiskSize: CustomImageCache.mapImageCache.diskSize"),
            "DataManager.debugSummary() should read map cache disk size inside the asynchronous transaction closure."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("transaction.fetchCount(From<Workout>())"),
            "DataManager.debugSummary() should count workouts inside the CoreStore transaction."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("transaction.fetchCount(From<WorkoutRouteDataSample>())"),
            "DataManager.debugSummary() should count route samples inside the CoreStore transaction."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("transaction.fetchCount(From<WorkoutEvent>())"),
            "DataManager.debugSummary() should count workout events inside the CoreStore transaction."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("transaction.fetchCount(From<WorkoutHeartRateDataSample>())"),
            "DataManager.debugSummary() should count heart-rate samples inside the CoreStore transaction."
        )
        XCTAssertTrue(
            asyncClosureSource.contains("transaction.fetchCount(From<Event>())"),
            "DataManager.debugSummary() should count events inside the CoreStore transaction."
        )
    }

    private func sourceSlice(in source: String, startingAt declaration: String) throws -> String {
        let declarationRange = try XCTUnwrap(source.range(of: declaration))
        let openingBrace = try XCTUnwrap(source[declarationRange.lowerBound...].firstIndex(of: "{"))
        var depth = 0
        var index = openingBrace

        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[declarationRange.lowerBound...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        XCTFail("Could not find end of source slice starting at \(declaration).")
        return String(source[declarationRange.lowerBound...])
    }

}
