import Foundation

/// Reject bad/cached input before it affects readiness, auto-pause, maps, or distance.
struct RecordingLocationGate {
    private(set) var lastTimestamp: Date?

    mutating func accept(latitude: Double, longitude: Double, accuracy: Double,
                         timestamp: Date, now: Date) -> Bool {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude), accuracy.isFinite, accuracy >= 0,
              timestamp.timeIntervalSince1970.isFinite,
              now.timeIntervalSince(timestamp) <= 15,
              timestamp.timeIntervalSince(now) <= 5,
              lastTimestamp.map({ timestamp > $0 }) ?? true else { return false }
        lastTimestamp = timestamp
        return true
    }
}
