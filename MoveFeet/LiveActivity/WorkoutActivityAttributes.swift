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
        public var paceOrSpeedText: String
        public var caloriesText: String
        public var statusTitle: String
        public var statusKind: String

        public init(
            timerStart: Date,
            pauseTime: Date?,
            isPaused: Bool,
            distanceText: String,
            paceOrSpeedText: String,
            caloriesText: String,
            statusTitle: String,
            statusKind: String
        ) {
            self.timerStart = timerStart
            self.pauseTime = pauseTime
            self.isPaused = isPaused
            self.distanceText = distanceText
            self.paceOrSpeedText = paceOrSpeedText
            self.caloriesText = caloriesText
            self.statusTitle = statusTitle
            self.statusKind = statusKind
        }
    }

    public var workoutTypeRawValue: Int
    public var usesPace: Bool

    public init(workoutTypeRawValue: Int, usesPace: Bool) {
        self.workoutTypeRawValue = workoutTypeRawValue
        self.usesPace = usesPace
    }
}
