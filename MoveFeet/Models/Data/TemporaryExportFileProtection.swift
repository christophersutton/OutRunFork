//
//  TemporaryExportFileProtection.swift
//  OutRun
//

import Foundation

enum TemporaryExportFileProtection {

    static func write(data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try protectExistingTemporaryExportFile(at: url)
    }

    static func protectExistingTemporaryExportFile(at url: URL) throws {
        try protectExistingTemporaryExportFile(at: url, applyingMetadataWith: applyProtectionMetadata(to:))
    }

    static func protectExistingTemporaryExportFile(
        at url: URL,
        applyingMetadataWith applyMetadata: (URL) throws -> Void
    ) throws {
        do {
            try applyMetadata(url)
        } catch {
            removeTemporaryExportFile(at: url, after: error)
            throw error
        }
    }

    private static func applyProtectionMetadata(to url: URL) throws {
        try FileManager.default.setAttributes(
            [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(resourceValues)
    }

    private static func removeTemporaryExportFile(at url: URL, after protectionError: Error) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print(
                "[TemporaryExportFileProtection] Failed to remove temporary export file after protection metadata failure:",
                protectionError.localizedDescription,
                "cleanup error:",
                error.localizedDescription
            )
        }
    }

}
