//
//  DynamicTypeFontShapeTests.swift
//  OutRun
//

import XCTest

final class DynamicTypeFontShapeTests: XCTestCase {

    func testAuditedTextSurfacesUseDynamicTypeScaledFonts() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let auditedFiles = [
            "OutRun/Controllers/General/DetailViewController.swift",
            "OutRun/Extensions/UIKit/UISegmentedControl.swift",
            "OutRun/Views/SwiftUI/ChangelogView.swift",
            "OutRun/Views/SwiftUI/Onboarding/OnboardingStepViews.swift",
            "OutRun/Views/SwiftUI/Onboarding/OnboardingView.swift",
            "OutRun/Views/SwiftUI/PolicyView.swift",
            "OutRun/Views/SwiftUI/Shell/MainTabView.swift",
            "OutRun/Views/SwiftUI/Shell/RootView.swift",
            "OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift",
            "OutRun/Views/SwiftUI/Timeline/WorkoutTimelineView.swift",
            "OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailCharts.swift",
            "OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailSupport.swift",
            "OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift",
            "OutRun/Views/Workout/NewWorkoutControllerActionButton.swift"
        ]

        let allowedFixedSwiftUIFontSnippets: [String: Set<String>] = [
            // Visual brand/number treatments keep explicit sizes because they are composite display text;
            // they are separate from normal labels/body copy covered by this Dynamic Type slice.
            "OutRun/Views/SwiftUI/Onboarding/OnboardingView.swift": [
                ".font(Font.system(size: 42, weight: .heavy).lowercaseSmallCaps())"
            ],
            "OutRun/Views/SwiftUI/Onboarding/OnboardingStepViews.swift": [
                // Symbol-only info affordance: this is an icon size, not a text font.
                ".font(.system(size: 14))"
            ],
            "OutRun/Views/SwiftUI/Timeline/WorkoutTimelineView.swift": [
                ".font(Font.system(size: 32, weight: .heavy).lowercaseSmallCaps())"
            ],
            "OutRun/Views/SwiftUI/Timeline/WorkoutTimelineRow.swift": [
                "let base = Font.system(size: size, weight: .bold)"
            ],
            "OutRun/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift": [
                // Symbol-only affordances: these are icon sizes, not text fonts.
                ".font(.system(size: 34, weight: .semibold))",
                ".font(.system(size: 15, weight: .bold))"
            ]
        ]

        var violations: [String] = []

        for relativePath in auditedFiles {
            let sourceURL = sourceRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let allowedSnippets = allowedFixedSwiftUIFontSnippets[relativePath, default: []]

            for line in source.components(separatedBy: .newlines) where line.contains(".font(.system(size:") || line.contains("Font.system(size:") {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !allowedSnippets.contains(trimmedLine) else { continue }
                violations.append("\(relativePath): \(trimmedLine)")
            }

            if source.contains("UIFont.systemFont(ofSize:") {
                violations.append("\(relativePath): use UIFont.preferredFont(forTextStyle:) or UIFontMetrics(...).scaledFont(for:) instead of UIFont.systemFont(ofSize:)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Audited text surfaces should use semantic/scaled Dynamic Type fonts. Violations:\n\(violations.joined(separator: "\n"))"
        )
    }
}
