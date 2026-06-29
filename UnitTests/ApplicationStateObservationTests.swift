//
//  ApplicationStateObservationTests.swift
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
@testable import MoveFeet

final class ApplicationStateObservationTests: XCTestCase {

    override func tearDown() {
        ApplicationStateObservation.observations = [:]
        super.tearDown()
    }

    func testWorkoutBuilderStopsObservingApplicationStateOnDeinit() {
        ApplicationStateObservation.observations = [:]

        var builder: WorkoutBuilder? = WorkoutBuilder(workoutType: .running)

        XCTAssertEqual(
            ApplicationStateObservation.observations.count,
            1,
            "WorkoutBuilder should register for application-state updates during initialization."
        )

        weak var releasedBuilder: WorkoutBuilder?
        releasedBuilder = builder
        builder = nil

        XCTAssertNil(releasedBuilder, "The test must release the builder before checking observation cleanup.")
        XCTAssertTrue(
            ApplicationStateObservation.observations.isEmpty,
            "WorkoutBuilder deinit should explicitly remove its application-state observation entry."
        )
    }

    func testApplicationStateObservationRegistryMutationsAreLockProtected() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let observationURL = repositoryRoot.appendingPathComponent("MoveFeet/Models/ApplicationStateObservation.swift")
        let source = try String(contentsOf: observationURL, encoding: .utf8)
        let stateChangedSource = try sourceSlice(
            in: source,
            startingAt: "static func stateChanged(to state: ApplicationState)"
        )
        let callbackRange = try XCTUnwrap(stateChangedSource.range(of: "observer.didUpdateApplicationState(to: state)"))
        let preCallbackSource = String(stateChangedSource[..<callbackRange.lowerBound])

        XCTAssertTrue(
            source.contains("private static let observationsLock"),
            "ApplicationStateObservation should protect its shared observer registry with a lock."
        )
        XCTAssertTrue(
            source.contains("observationsLock.lock()"),
            "ApplicationStateObservation registry reads and writes should acquire the lock."
        )
        XCTAssertTrue(
            stateChangedSource.contains("activeObservers"),
            "stateChanged should snapshot live observers while locked, then notify that snapshot."
        )
        XCTAssertTrue(
            preCallbackSource.contains("observationsLock.unlock()"),
            "stateChanged should release the registry lock before invoking observer callbacks."
        )
    }

    func testApplicationStateCallbacksRunAfterRegistryUnlock() {
        ApplicationStateObservation.observations = [:]
        var callbackCount = 0

        let observer = TestApplicationStateObserver { _ in
            callbackCount += 1

            let registryReadCompleted = XCTestExpectation(description: "Registry read completed during callback")
            DispatchQueue.global(qos: .userInitiated).async {
                _ = ApplicationStateObservation.observations
                registryReadCompleted.fulfill()
            }

            XCTAssertEqual(
                XCTWaiter.wait(for: [registryReadCompleted], timeout: 1),
                .completed,
                "Application state callbacks should run after the registry lock has been released."
            )
        }

        ApplicationStateObservation.addObserver(observer)
        ApplicationStateObservation.stateChanged(to: .foreground)

        XCTAssertEqual(callbackCount, 1)
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

private final class TestApplicationStateObserver: ApplicationStateObserver {
    private let onUpdate: (ApplicationState) -> Void

    init(onUpdate: @escaping (ApplicationState) -> Void) {
        self.onUpdate = onUpdate
    }

    func didUpdateApplicationState(to state: ApplicationState) {
        self.onUpdate(state)
    }
}
