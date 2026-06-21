//
//  LiveStatsTimerTests.swift
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

final class LiveStatsTimerTests: XCTestCase {

    func testDurationAndBurnedEnergyUseOneSharedAutoconnectedCommonModeTimer() throws {
        let sourcePath = "OutRun/Models/Workout/WorkoutBuilder/Components/LiveStats.swift"
        let source = try readSource(at: sourcePath).removingLineComments()
        let timerPublishCalls = source.matches(of: "Timer.publish(")

        XCTAssertEqual(
            timerPublishCalls.count,
            1,
            "LiveStats should create one shared 1-second timer publisher for duration and burned-energy updates."
        )
        XCTAssertTrue(
            source.contains("Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common)"),
            "The shared live stats timer should stay on the main run loop in common mode and include a small tolerance for coalescing."
        )
        XCTAssertEqual(
            source.matches(of: ".autoconnect()").count,
            1,
            "The shared timer must autoconnect so the live-stat chains keep firing."
        )
        XCTAssertEqual(
            source.matches(of: ".share()").count,
            1,
            "The autoconnected timer should be shared between duration and burned-energy chains."
        )
        XCTAssertTrue(
            source.contains("let liveStatsTimer = Timer.publish"),
            "LiveStats should name a local shared timer before attaching the duration and burned-energy chains."
        )
        XCTAssertEqual(
            source.matches(of: "liveStatsTimer\n            .combineLatest").count,
            2,
            "Both duration and burned-energy mappings should subscribe to the same shared liveStatsTimer publisher."
        )
    }

    private func readSource(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

}

private extension String {

    func removingLineComments() -> String {
        components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func matches(of pattern: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = startIndex..<endIndex

        while let range = range(of: pattern, options: [], range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<endIndex
        }

        return ranges
    }

}
