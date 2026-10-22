//
//  WorkoutActivityAttributes.swift
//  MoveFeet
//

import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var timerStart: Date
        public var pauseTime: Date?
        public var isPaused: Bool
        public var distanceText: String
        /// Optional so content written by older versions still decodes.
        public var accentHex: UInt32?

        public init(
            timerStart: Date,
            pauseTime: Date?,
            isPaused: Bool,
            distanceText: String,
            accentHex: UInt32? = nil
        ) {
            self.timerStart = timerStart
            self.pauseTime = pauseTime
            self.isPaused = isPaused
            self.distanceText = distanceText
            self.accentHex = accentHex
        }
    }

    /// Initial accent, retained as a fallback for activities from older versions.
    public var accentHex: UInt32

    public init(accentHex: UInt32 = 0xFF8A00) {
        self.accentHex = accentHex
    }
}
