//
//  CoreStorePresentationSnapshotTests.swift
//  OutRun
//

import XCTest

final class CoreStorePresentationSnapshotTests: XCTestCase {

    func testEditWorkoutSeedingUsesRawValueSnapshotInsteadOfLiveCoreStoreAccessors() throws {
        let stateSource = try readSource(at: "OutRun/Views/SwiftUI/EditWorkout/EditWorkoutState.swift")
        let initBody = try body(named: "init(mode: Mode)", in: stateSource)

        XCTAssertFalse(
            initBody.contains("DataManager.queryObject"),
            "EditWorkoutState edit seeding must not synchronously query a live CoreStore Workout."
        )
        for accessor in ["workoutType", "distance", "steps", "startDate", "endDate", "isRace", "comment"] {
            XCTAssertFalse(
                containsObjectMemberAccess("workout", accessor, in: initBody),
                "EditWorkoutState edit seeding must use WorkoutEditSnapshot, not Workout.\(accessor), because public accessors hop through threadSafeSyncReturn."
            )
        }
        XCTAssertTrue(
            initBody.contains("WorkoutEditSnapshot"),
            "EditWorkoutState edit seeding should accept a raw-value WorkoutEditSnapshot."
        )
    }

    func testWorkoutEditSnapshotReadsRawStorageAndAsyncQueryAPIExists() throws {
        let snapshotSource = try readSource(at: "OutRun/Models/Data/Snapshots/WorkoutEditSnapshot.swift")
        let snapshotInit = try body(named: "init(_ workout: Workout)", in: snapshotSource)

        for rawField in ["_workoutType", "_distance", "_steps", "_startDate", "_endDate", "_isRace", "_comment"] {
            XCTAssertTrue(
                snapshotInit.contains("\(rawField).value"),
                "WorkoutEditSnapshot must read \(rawField).value on the CoreStore transaction queue."
            )
        }
        for accessor in ["workoutType", "distance", "steps", "startDate", "endDate", "isRace", "comment"] {
            XCTAssertFalse(
                containsObjectMemberAccess("workout", accessor, in: snapshotInit),
                "WorkoutEditSnapshot must not read Workout.\(accessor); public accessors use threadSafeSyncReturn."
            )
        }

        let querySource = try readSource(at: "OutRun/Models/Data/DataManager+Query.swift")
        let queryBody = try body(named: "public static func workoutEditSnapshot(for id: UUID?) async -> WorkoutEditSnapshot?", in: querySource)
        XCTAssertTrue(queryBody.contains("dataStack.perform"))
        XCTAssertTrue(queryBody.contains("queryObject(from: id, transaction: transaction)"))
        XCTAssertTrue(queryBody.contains("WorkoutEditSnapshot(workout)"))
    }

    private func readSource(at relativePath: String) throws -> String {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()
        let fileURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL)
    }

    private func body(named declaration: String, in source: String) throws -> String {
        let declarationRange = try XCTUnwrap(
            source.range(of: declaration),
            "Missing declaration: \(declaration)."
        )
        let declarationSource = source[declarationRange.lowerBound...]
        let openBrace = try XCTUnwrap(
            declarationSource.firstIndex(of: "{"),
            "Missing opening brace for \(declaration)."
        )

        var depth = 0
        var index = openBrace
        while index < declarationSource.endIndex {
            let character = declarationSource[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(declarationSource[openBrace...index])
                }
            }
            index = declarationSource.index(after: index)
        }

        XCTFail("Missing closing brace for \(declaration).")
        return ""
    }

    private func containsObjectMemberAccess(_ object: String, _ member: String, in source: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: object) + "\\s*\\.\\s*" + NSRegularExpression.escapedPattern(for: member) + "(?![A-Za-z0-9_]|\\s*:)"
        return source.range(of: pattern, options: .regularExpression) != nil
    }
}
