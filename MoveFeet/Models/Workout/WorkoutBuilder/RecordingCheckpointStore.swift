import Foundation

/// One atomic, versioned file. A failed read/write never deletes the previous checkpoint.
/// Generic so the durability contract can be tested without sensors or the application database.
final class RecordingCheckpointStore<Snapshot: Codable> {
    enum Phase: String, Codable { case recording, paused, reviewing, failedSave }
    struct Checkpoint: Codable {
        let version: Int
        let sessionID: UUID
        let phase: Phase
        let capturedAt: Date
        let snapshot: Snapshot

        init(sessionID: UUID, phase: Phase, capturedAt: Date, snapshot: Snapshot) {
            self.version = 1
            self.sessionID = sessionID
            self.phase = phase
            self.capturedAt = capturedAt
            self.snapshot = snapshot
        }
    }

    let url: URL
    init(url: URL) { self.url = url }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func load() throws -> Checkpoint? {
        guard exists else { return nil }
        let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: url))
        guard checkpoint.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return checkpoint
    }

    func save(_ checkpoint: Checkpoint) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(checkpoint)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var file = url
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try file.setResourceValues(attributes)
    }

    /// Identity check prevents an obsolete completion from clearing a newer session.
    func clear(sessionID: UUID) throws {
        guard let checkpoint = try load(), checkpoint.sessionID == sessionID else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Only for an explicit, confirmed discard (including an unreadable checkpoint).
    func discard() throws {
        if exists { try FileManager.default.removeItem(at: url) }
    }
}
