//
//  CloseButtonAccessibilityTests.swift
//  OutRun
//

import XCTest

final class CloseButtonAccessibilityTests: XCTestCase {

    func testIconOnlyCloseButtonsDeclareLocalizedButtonAccessibilityLabels() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let cases = [
            (
                "OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift",
                #"""
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(LS["Close"]))
"""#
            ),
            (
                "OutRun/Views/SwiftUI/Debug/DebugView.swift",
                #"""
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(LS["Close"]))
"""#
            ),
            (
                "OutRun/Views/SwiftUI/PolicyView.swift",
                #"""
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.orSecondary)
                    }
                    .accessibilityLabel(Text(LS["Close"]))
"""#
            ),
            (
                "OutRun/Views/SwiftUI/ChangelogView.swift",
                #"""
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.orSecondary)
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LS["Close"]))
"""#
            )
        ]

        for (relativePath, expectedButtonSnippet) in cases {
            let sourceURL = sourceRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)

            XCTAssertTrue(
                source.contains(expectedButtonSnippet),
                "\(relativePath) must apply its localized accessibility label to the icon-only close button."
            )
        }
    }

}
