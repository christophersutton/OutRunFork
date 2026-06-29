//
//  WorkoutMapImageRequestTests.swift
//  OutRun
//

import XCTest
@testable import MoveFeet

final class WorkoutMapImageRequestTests: XCTestCase {

    func testCacheIdentifierSeparatesLogicalSizePointSizeScaleAndAppearance() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let smallLight = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            usesDarkAppearance: false,
            completion: { _, _ in }
        )
        let wideLight = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 240, height: 90),
            scale: 2,
            usesDarkAppearance: false,
            completion: { _, _ in }
        )
        let smallRetinaLight = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 3,
            usesDarkAppearance: false,
            completion: { _, _ in }
        )
        let smallDark = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            usesDarkAppearance: true,
            completion: { _, _ in }
        )
        let statsLight = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .stats,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            usesDarkAppearance: false,
            completion: { _, _ in }
        )

        let smallLightID = try XCTUnwrap(smallLight.cacheIdentifier())

        XCTAssertTrue(smallLightID.contains(uuid.uuidString))
        XCTAssertTrue(smallLightID.contains("list"))
        XCTAssertTrue(smallLightID.contains("120x90"))
        XCTAssertTrue(smallLightID.contains("@2x"))
        XCTAssertTrue(smallLightID.contains("light"))
        XCTAssertNotEqual(smallLightID, wideLight.cacheIdentifier())
        XCTAssertNotEqual(smallLightID, smallRetinaLight.cacheIdentifier())
        XCTAssertNotEqual(smallLightID, smallDark.cacheIdentifier())
        XCTAssertNotEqual(smallLightID, statsLight.cacheIdentifier())
    }

    func testRequestEqualitySeparatesLogicalSizePointSizeScaleAndAppearance() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let base = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            usesDarkAppearance: false,
            completion: { _, _ in }
        )

        XCTAssertEqual(
            base,
            WorkoutMapImageRequest(
                workoutUUID: uuid,
                size: .list,
                pointSize: CGSize(width: 120, height: 90),
                scale: 2,
                usesDarkAppearance: false,
                completion: { _, _ in }
            )
        )
        XCTAssertNotEqual(
            base,
            WorkoutMapImageRequest(
                workoutUUID: uuid,
                size: .stats,
                pointSize: CGSize(width: 120, height: 90),
                scale: 2,
                usesDarkAppearance: false,
                completion: { _, _ in }
            )
        )
        XCTAssertNotEqual(
            base,
            WorkoutMapImageRequest(
                workoutUUID: uuid,
                size: .list,
                pointSize: CGSize(width: 121, height: 90),
                scale: 2,
                usesDarkAppearance: false,
                completion: { _, _ in }
            )
        )
        XCTAssertNotEqual(
            base,
            WorkoutMapImageRequest(
                workoutUUID: uuid,
                size: .list,
                pointSize: CGSize(width: 120, height: 90),
                scale: 3,
                usesDarkAppearance: false,
                completion: { _, _ in }
            )
        )
        XCTAssertNotEqual(
            base,
            WorkoutMapImageRequest(
                workoutUUID: uuid,
                size: .list,
                pointSize: CGSize(width: 120, height: 90),
                scale: 2,
                usesDarkAppearance: true,
                completion: { _, _ in }
            )
        )
    }

    func testTimelineRowDoesNotRequestMapImageWithoutRouteData() throws {
        let source = try mapTimelineSource(relativePath: "MoveFeet/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift")
        guard let guardRange = source.range(of: "guard snapshot.hasRouteData else { return }") else {
            XCTFail("WorkoutTimelineRow.loadRouteImageIfNeeded() must return before requesting map images when snapshot.hasRouteData is false.")
            return
        }
        let requestRange = try XCTUnwrap(source.range(of: "WorkoutMapImageRequest("))

        XCTAssertLessThan(guardRange.lowerBound, requestRange.lowerBound)
    }

    func testQueuePromotesExistingOrdinaryRequestWhenDuplicateHighPriorityArrives() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD"))
        let ordinary = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            highPriority: false,
            completion: { _, _ in }
        )
        let highPriority = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            highPriority: true,
            completion: { _, _ in }
        )

        let queue = WorkoutMapImageQueue()
        queue.add(ordinary)
        queue.add(highPriority)

        XCTAssertEqual(queue.pendingRequests.count, 1)
        XCTAssertTrue(try XCTUnwrap(queue.pendingRequests.first).highPriority)
    }

    func testQueueDoesNotPromoteExcludedInFlightRequest() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "99999999-AAAA-BBBB-CCCC-EEEEEEEEEEEE"))
        let ordinary = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            highPriority: false,
            completion: { _, _ in }
        )
        let highPriority = WorkoutMapImageRequest(
            workoutUUID: uuid,
            size: .list,
            pointSize: CGSize(width: 120, height: 90),
            scale: 2,
            highPriority: true,
            completion: { _, _ in }
        )

        let queue = WorkoutMapImageQueue()
        queue.add(ordinary)
        let inFlightRequest = try XCTUnwrap(queue.pendingRequests.first)

        XCTAssertFalse(queue.promote(highPriority, excluding: inFlightRequest))
        XCTAssertEqual(queue.pendingRequests.count, 1)
        XCTAssertFalse(try XCTUnwrap(queue.pendingRequests.first).highPriority)
    }

    func testDarkModeRequeueUsesCoalescingPath() throws {
        let source = try mapTimelineSource(relativePath: "MoveFeet/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift")

        XCTAssertFalse(
            source.contains("self.requestQueue.add(updatedAppearanceRequest)"),
            "Dark/light follow-up requests must not bypass enqueueUncached/requestCompletions coalescing."
        )
        XCTAssertTrue(
            source.contains("enqueueUncached(updatedAppearanceRequest"),
            "Dark/light follow-up requests should use the uncached coalescing path so later matching callers are completed."
        )
    }

    func testMapImageAndTimelineSizingDoNotReadScreenBounds() throws {
        let checkedFiles = [
            "MoveFeet/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift",
            "MoveFeet/Models/Workout/MapManagement/Images/WorkoutMapImageSize.swift",
            "MoveFeet/Models/Workout/MapManagement/Images/WorkoutMapImageRequest.swift",
            "MoveFeet/Models/Workout/MapManagement/Images/WorkoutMapImageManager.swift"
        ]

        for relativePath in checkedFiles {
            let source = try mapTimelineSource(relativePath: relativePath)
            XCTAssertFalse(
                source.contains("UIScreen.main.bounds"),
                "\(relativePath) must use concrete/container-driven point sizes instead of screen bounds."
            )
        }
    }

    private func mapTimelineSource(relativePath: String) throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sourceRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
