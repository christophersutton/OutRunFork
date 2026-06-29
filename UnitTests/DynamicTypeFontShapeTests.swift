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

        let auditedFiles = try swiftFiles(under: sourceRoot.appendingPathComponent("OutRun"))

        let allowedFixedSwiftUIFontSnippets: [String: Set<String>] = [
            // Visual brand/date treatments keep explicit sizes because they are composite display text;
            // normal labels/body copy and workout stats must use Dynamic Type.
            "MoveFeet/Views/SwiftUI/Onboarding/OnboardingView.swift": [
                ".font(Font.system(size: 42, weight: .heavy).lowercaseSmallCaps())"
            ],
            "MoveFeet/Views/SwiftUI/WorkoutDetail/WorkoutDetailView.swift": [
                // Symbol-only affordances: these are icon sizes, not text fonts.
                ".font(.system(size: 34, weight: .semibold))",
                ".font(.system(size: 15, weight: .bold))"
            ]
        ]

        var violations: [String] = []

        for sourceURL in auditedFiles {
            let relativePath = sourceURL.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let allowedSnippets = allowedFixedSwiftUIFontSnippets[relativePath, default: []]

            for line in source.components(separatedBy: .newlines) {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !allowedSnippets.contains(trimmedLine) else { continue }

                if trimmedLine.contains(".font(.system(size:") || trimmedLine.contains("Font.system(size:") {
                    violations.append("\(relativePath): \(trimmedLine)")
                }

                if trimmedLine.contains(".systemFont(ofSize:") || trimmedLine.contains("UIFont.systemFont(ofSize:") {
                    violations.append("\(relativePath): use UIFont.preferredFont(forTextStyle:) or UIFontMetrics(...).scaledFont(for:) instead of fixed UIFont systemFont(ofSize:) shorthand: \(trimmedLine)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Audited text surfaces should use semantic/scaled Dynamic Type fonts. Violations:\n\(violations.joined(separator: "\n"))"
        )
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var files: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard (try fileURL.resourceValues(forKeys: Set(resourceKeys)).isRegularFile) == true else { continue }
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }
}
