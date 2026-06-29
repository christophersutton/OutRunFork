//
//  MapImageRenderSuspensionTests.swift
//  OutRun
//

import XCTest

final class MapImageRenderSuspensionTests: XCTestCase {

    func testMapImageManagerUsesLogicalSuspensionInsteadOfRawDispatchQueueSuspension() throws {
        let source = try sourceFile(relativePath: "MoveFeet/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift")
        let suspendBody = try methodBody(named: "suspendRenderProcess", in: source)
        let resumeBody = try methodBody(named: "resumeRenderProcess", in: source)

        for forbiddenCall in [
            "processQueue.suspend()",
            "snapshotQueue.suspend()",
            "processQueue.resume()",
            "snapshotQueue.resume()"
        ] {
            XCTAssertFalse(
                source.contains(forbiddenCall),
                "WorkoutMapImageManager must not use raw DispatchQueue suspension for render throttling: \(forbiddenCall)"
            )
        }

        XCTAssertTrue(
            suspendBody.contains("guard internalStatus != .suspended else {"),
            "suspendRenderProcess() should be idempotent and avoid re-entering the suspended state."
        )
        XCTAssertTrue(
            suspendBody.contains("internalStatus = .suspended"),
            "suspendRenderProcess() should use the logical status gate to stop starting queued renders."
        )
        XCTAssertTrue(
            resumeBody.contains("guard internalStatus == .suspended else {"),
            "resumeRenderProcess() should be idempotent when called while not suspended."
        )
        XCTAssertTrue(
            resumeBody.contains("internalStatus = .idle"),
            "resumeRenderProcess() should reopen the logical render gate."
        )
        XCTAssertTrue(
            source.contains("if internalStatus == .suspended {\n            return\n        }"),
            "executeNextInQueue() must leave queued requests pending while render processing is logically suspended."
        )
    }

    func testScenePhaseCommentNoLongerDocumentsRawDispatchResumeTrapAvoidance() throws {
        let source = try sourceFile(relativePath: "MoveFeet/Views/SwiftUI/Shell/MoveFeetApp.swift")

        XCTAssertFalse(source.contains("raw, unbalanced `dispatch_suspend`/`dispatch_resume`"))
        XCTAssertFalse(source.contains("over-resume the queues and trap"))
    }

    private func sourceFile(relativePath: String) throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func methodBody(named methodName: String, in source: String) throws -> String {
        guard let signatureRange = source.range(of: "public static func \(methodName)()") else {
            XCTFail("Missing method: \(methodName)")
            return ""
        }
        guard let openingBrace = source[signatureRange.upperBound...].firstIndex(of: "{") else {
            XCTFail("Missing opening brace for method: \(methodName)")
            return ""
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            }
            index = source.index(after: index)
        }

        XCTFail("Missing closing brace for method: \(methodName)")
        return ""
    }
}
