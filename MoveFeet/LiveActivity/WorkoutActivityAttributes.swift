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

        public init(
            timerStart: Date,
            pauseTime: Date?,
            isPaused: Bool,
            distanceText: String
        ) {
            self.timerStart = timerStart
            self.pauseTime = pauseTime
            self.isPaused = isPaused
            self.distanceText = distanceText
        }
    }

    /// The person's Move accent as 0xRRGGBB, fixed for the activity's lifetime. Orange is Run's default.
    public var accentHex: UInt32

    public init(accentHex: UInt32 = 0xFF8A00) {
        self.accentHex = accentHex
    }
}
