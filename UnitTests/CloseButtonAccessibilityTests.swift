//
//  CloseButtonAccessibilityTests.swift
//  OutRun
//

import XCTest

final class CloseButtonAccessibilityTests: XCTestCase {

    func testIconOnlyCloseButtonsDeclareLocalizedAccessibilityLabels() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let cases = [
            "OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift": "Image(systemName: \"xmark\")",
            "OutRun/Views/SwiftUI/Debug/DebugView.swift": "Image(systemName: \"xmark\")",
            "OutRun/Views/SwiftUI/PolicyView.swift": "Image(systemName: \"xmark.circle.fill\")",
            "OutRun/Views/SwiftUI/ChangelogView.swift": "Image(systemName: \"xmark.circle.fill\")"
        ]

        for (relativePath, imageExpression) in cases {
            let sourceURL = sourceRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let imageRange = try XCTUnwrap(
                source.range(of: imageExpression),
                "Expected \(relativePath) to contain \(imageExpression)."
            )
            let closeButtonSnippet = source[imageRange.lowerBound...]
                .prefix(400)

            XCTAssertTrue(
                closeButtonSnippet.contains(".accessibilityLabel(LS[\"Close\"])") || closeButtonSnippet.contains(".accessibilityLabel(Text(LS[\"Close\"]))"),
                "\(relativePath) must give its icon-only close button an explicit localized accessibility label."
            )
        }
    }

}
