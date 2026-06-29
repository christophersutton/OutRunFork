//
//  TemporaryExportFileProtectionTests.swift
//  OutRun
//

import Foundation
import XCTest
@testable import MoveFeet

final class TemporaryExportFileProtectionTests: XCTestCase {

    func testBackupCreationUsesProtectedTemporaryExportWrite() throws {
        let source = try readSource(at: "MoveFeet/Models/Data/Backup/BackupManager.swift")
        let body = try functionBody(named: "createBackup(for inclusionType: DataInclusionType", in: source)

        XCTAssertTrue(
            body.contains("TemporaryExportFileProtection.write(data: data, to: url)"),
            "Backup creation should write .orbup data through the protected temporary export helper."
        )
        XCTAssertFalse(
            body.contains("try data.write(to: url)"),
            "Sensitive .orbup temp files should not be written with plain Data.write(to:)."
        )
    }

    func testGPXExportProtectsAndExcludesGeneratedURLsBeforeSharing() throws {
        let source = try readSource(at: "MoveFeet/Models/Data/ExportManager.swift")
        let body = try functionBody(named: "createGPXFiles(for inclusionType: DataInclusionType", in: source)

        XCTAssertTrue(
            body.contains("TemporaryExportFileProtection.protectExistingTemporaryExportFile(at: fullURL)"),
            "GPX files produced by CoreGPX should be protected and excluded from backup after creation."
        )

        let protectionRange = try XCTUnwrap(body.range(of: "TemporaryExportFileProtection.protectExistingTemporaryExportFile(at: fullURL)"))
        let appendRange = try XCTUnwrap(body.range(of: "urls.append(fullURL)"))
        XCTAssertLessThan(
            protectionRange.lowerBound,
            appendRange.lowerBound,
            "GPX files should be protected before their URLs are appended for sharing."
        )
    }

    func testSettingsBackupCleanupUsesLoggedDoCatchInsteadOfTryOptional() throws {
        let source = try readSource(at: "MoveFeet/Views/SwiftUI/Settings/SettingsView.swift")

        XCTAssertFalse(
            source.contains("try? FileManager.default.removeItem(at: url)"),
            "Settings backup cleanup should not silently ignore failures for sensitive temp files."
        )

        let body = try functionBody(named: "cleanupTemporaryBackup(at url: URL", in: source)
        XCTAssertTrue(body.contains("do {"), "Cleanup helper should use do/catch.")
        XCTAssertTrue(body.contains("catch"), "Cleanup helper should log cleanup errors.")
        XCTAssertTrue(body.contains("print("), "Cleanup helper should visibly log cleanup errors.")
        XCTAssertTrue(body.contains("FileManager.default.removeItem(at: url)"))
    }

    func testTemporaryExportProtectionHelperAppliesProtectionAndBackupExclusion() throws {
        let source = try readSource(at: "MoveFeet/Models/Data/TemporaryExportFileProtection.swift")

        XCTAssertTrue(
            source.contains(".completeFileProtectionUntilFirstUserAuthentication"),
            "Data writes should use explicit file-protection options that remain share-compatible after first unlock."
        )
        XCTAssertTrue(
            source.contains("FileAttributeKey.protectionKey"),
            "Existing CoreGPX-created files should receive explicit file-protection attributes."
        )
        XCTAssertTrue(
            source.contains("FileProtectionType.completeUntilFirstUserAuthentication"),
            "Post-write protection should match the write option."
        )
        XCTAssertTrue(
            source.contains("isExcludedFromBackup = true"),
            "Temporary exports should be excluded from device backup if they persist."
        )
        XCTAssertTrue(
            source.contains("setResourceValues"),
            "Backup exclusion should be applied to generated file URLs."
        )
        XCTAssertTrue(
            source.contains("removeItem(at: url)"),
            "Generated temporary exports should be removed if protection or backup-exclusion metadata cannot be applied."
        )
        XCTAssertTrue(
            source.contains("Failed to remove temporary export file after protection metadata failure"),
            "Cleanup failures for sensitive temporary exports should be logged."
        )
    }

    func testTemporaryExportWriteCreatesProtectedBackupExcludedFileAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TemporaryExportFileProtectionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let url = directory.appendingPathComponent("runtime.orbup")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        try TemporaryExportFileProtection.write(data: Data("sensitive export".utf8), to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        }

        let resourceValues = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)

        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testTemporaryExportProtectionRemovesFileWhenMetadataApplicationFails() throws {
        enum MetadataApplicationError: Error, Equatable {
            case injectedFailure
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TemporaryExportFileProtectionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let url = directory.appendingPathComponent("metadata-failure.orbup")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        try Data("sensitive export".utf8).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        XCTAssertThrowsError(
            try TemporaryExportFileProtection.protectExistingTemporaryExportFile(
                at: url,
                applyingMetadataWith: { _ in throw MetadataApplicationError.injectedFailure }
            )
        ) { error in
            XCTAssertEqual(error as? MetadataApplicationError, .injectedFailure)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "Temporary export file should be removed when protection metadata cannot be applied."
        )
    }

    private func readSource(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func functionBody(named signatureFragment: String, in source: String) throws -> String {
        let signatureRange = try XCTUnwrap(source.range(of: "func " + signatureFragment))
        let searchStart = signatureRange.upperBound
        let openingBrace = try XCTUnwrap(source[searchStart...].firstIndex(of: "{"))
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

        XCTFail("Could not find function body for \(signatureFragment)")
        return ""
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

}
