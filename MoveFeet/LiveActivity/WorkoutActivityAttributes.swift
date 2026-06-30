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

    public init() {}
}
