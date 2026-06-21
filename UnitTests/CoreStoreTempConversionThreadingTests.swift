//
//  CoreStoreTempConversionThreadingTests.swift
//  OutRun
//

import XCTest
@testable import OutRun

final class CoreStoreTempConversionThreadingTests: XCTestCase {

    func testCurrentBackupEncodingUsesV4VersionCode() throws {
        let backup = Backup(workouts: [], events: [])
        let data = try JSONEncoder().encode(backup)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            "Encoded backup should be a JSON object."
        )

        XCTAssertEqual(
            json["version"] as? String,
            BackupV4.versionCode,
            "Current backups must advertise the V4 schema so import decodes the payload through BackupV4."
        )
        XCTAssertNoThrow(try JSONDecoder().decode(BackupV4.self, from: data))
    }

    func testCoreStoreAsTempConversionsReadRawStorageWithoutPublicThreadSafeAccessors() throws {
        let cases: [(type: String, path: String, forbiddenAccessors: [String])] = [
            (
                type: "Workout",
                path: "OutRun/Models/Data/DataModels/Workout.swift",
                forbiddenAccessors: [
                    "uuid", "workoutType", "distance", "steps", "startDate", "endDate",
                    "burnedEnergy", "isRace", "comment", "isUserModified", "healthKitUUID",
                    "finishedRecording", "ascend", "descend", "activeDuration", "pauseDuration",
                    "dayIdentifier", "heartRates", "routeData", "pauses", "workoutEvents"
                ]
            ),
            (
                type: "Event",
                path: "OutRun/Models/Data/DataModels/Event.swift",
                forbiddenAccessors: ["uuid", "title", "comment", "startDate", "endDate", "workouts"]
            ),
            (
                type: "WorkoutPause",
                path: "OutRun/Models/Data/DataModels/WorkoutPause.swift",
                forbiddenAccessors: ["uuid", "startDate", "endDate", "pauseType"]
            ),
            (
                type: "WorkoutEvent",
                path: "OutRun/Models/Data/DataModels/WorkoutEvent.swift",
                forbiddenAccessors: ["uuid", "eventType", "timestamp"]
            ),
            (
                type: "WorkoutRouteDataSample",
                path: "OutRun/Models/Data/DataModels/WorkoutRouteDataSample.swift",
                forbiddenAccessors: [
                    "uuid", "timestamp", "latitude", "longitude", "altitude",
                    "horizontalAccuracy", "verticalAccuracy", "speed", "direction"
                ]
            ),
            (
                type: "WorkoutHeartRateDataSample",
                path: "OutRun/Models/Data/DataModels/WorkoutHeartRateDataSample.swift",
                forbiddenAccessors: ["uuid", "heartRate", "timestamp"]
            )
        ]

        for testCase in cases {
            let source = try readSource(at: testCase.path)
            let body = try asTempBody(for: testCase.type, in: source)

            XCTAssertFalse(
                body.contains("threadSafeSyncReturn"),
                "\(testCase.type).asTemp must not call threadSafeSyncReturn while mapping CoreStore objects for backup/export."
            )
            XCTAssertTrue(
                body.contains(".value"),
                "\(testCase.type).asTemp should read raw CoreStore `_x.value` storage on the transaction queue."
            )

            for accessor in testCase.forbiddenAccessors {
                XCTAssertFalse(
                    containsIdentifier(accessor, in: body),
                    "\(testCase.type).asTemp must read _\(accessor).value directly instead of the public \(accessor) accessor."
                )
            }
        }
    }

    private func readSource(at relativePath: String) throws -> String {
        let unitTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = unitTestsDirectory.deletingLastPathComponent()
        let fileURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL)
    }

    private func asTempBody(for type: String, in source: String) throws -> String {
        let extensionMarker = "extension \(type): TempValueConvertible"
        let extensionRange = try XCTUnwrap(
            source.range(of: extensionMarker),
            "Missing \(extensionMarker)."
        )
        let extensionSource = source[extensionRange.lowerBound...]
        let asTempRange = try XCTUnwrap(
            extensionSource.range(of: "public var asTemp"),
            "Missing asTemp body for \(type)."
        )
        let asTempSource = extensionSource[asTempRange.lowerBound...]
        let openBrace = try XCTUnwrap(
            asTempSource.firstIndex(of: "{"),
            "Missing opening brace for \(type).asTemp."
        )

        var depth = 0
        var index = openBrace
        while index < asTempSource.endIndex {
            let character = asTempSource[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(asTempSource[openBrace...index])
                }
            }
            index = asTempSource.index(after: index)
        }

        XCTFail("Missing closing brace for \(type).asTemp.")
        return ""
    }

    private func containsIdentifier(_ identifier: String, in source: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: identifier) + "(?![A-Za-z0-9_]|\\s*:)"
        return source.range(of: pattern, options: .regularExpression) != nil
    }

}
