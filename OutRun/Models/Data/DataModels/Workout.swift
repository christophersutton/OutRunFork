//
//  Workout.swift
//
//  OutRun
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import CoreLocation
import HealthKit
import CoreStore

public typealias Workout = OutRunV4.Workout

public extension Workout {
    
    var hasRouteData: Bool {
        return !self.routeData.isEmpty
    }
    
    var hasHeartRateData: Bool {
        return !self.heartRates.isEmpty
    }
    
    enum WorkoutType: CaseIterable, CustomStringConvertible, CustomDebugStringConvertible, RawRepresentable, ImportableAttributeType, Codable {
        
        case running, walking, hiking, unknown

        static let supportedTypes: [WorkoutType] = [.running, .walking, .hiking]
        
        public init(rawValue: Int) {
            switch rawValue {
            case 0:
                self = .running
            case 1:
                self = .walking
            case 4:
                self = .hiking
            default:
                self = .unknown
            }
        }
        
        public init?(hkType: HKWorkoutActivityType) {
            switch hkType {
            case .running:
                self = .running
            case .walking:
                self = .walking
            case .hiking:
                self = .hiking
            default:
                return nil
            }
        }
        
        public var rawValue: Int {
            switch self {
            case .running:
                return 0
            case .walking:
                return 1
            case .hiking:
                return 4
            case .unknown:
                return -1
            }
        }
        
        public var description: String {
            switch self {
            case .running:
                return LS["Workout.Type.Running"]
            case .walking:
                return LS["Workout.Type.Walking"]
            case .hiking:
                return LS["Workout.Type.Hiking"]
            case .unknown:
                return LS["Workout.Type.Unknown"]
            }
        }
        
        public var debugDescription: String {
            switch self {
            case .running:
                return "Running"
            case .walking:
                return "Walking"
            case .hiking:
                return "Hiking"
            case .unknown:
                return "Unknown"
            }
        }
        
        public var METSpeedMultiplier: Double {
            switch self {
            case .running:
                return 1.035
            case .walking, .hiking:
                return 0.655
            case .unknown:
                return 0
            }
        }
        
        public var healthKitType: HKWorkoutActivityType {
            switch self {
            case .running:
                return .running
            case .walking:
                return .walking
            case .hiking:
                return .hiking
            default:
                return .other
            }
        }
        
        public var healthKitDistanceType: HKQuantityType? {
            switch self {
            case .running, .walking, .hiking:
                return HealthStoreManager.HealthType.DistanceWalkingRunning
            default:
                return nil
            }
        }
        
    }
    
}

// MARK: - CustomStringConvertible

extension Workout: CustomStringConvertible {
    
    public var description: String {
        
        var desc = "Workout("
        
        if let uuid = uuid {
            desc += "uuid: \(uuid), "
        }
        
        desc += "type: \(workoutType.debugDescription), start: \(startDate), end: \(endDate), distance: \(distance) m, activeDuration: \(activeDuration) s, pauseDuration: \(pauseDuration) s, pauses: \(pauses.count), events: \(events.count), heartRates: \(heartRates.count)"
        
        if let energy = burnedEnergy {
            desc += " burnedEnergy: \(energy) kcal"
        }
        
        return desc + ")"
    }
}

// MARK: - ORWorkoutInterface

extension Workout: ORWorkoutInterface {
    
    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var workoutType: Workout.WorkoutType { threadSafeSyncReturn { self._workoutType.value } }
    public var distance: Double { threadSafeSyncReturn { self._distance.value } }
    public var steps: Int? { threadSafeSyncReturn { self._steps.value } }
    public var startDate: Date { threadSafeSyncReturn { self._startDate.value } }
    public var endDate: Date { threadSafeSyncReturn { self._endDate.value } }
    public var burnedEnergy: Double? { threadSafeSyncReturn { self._burnedEnergy.value } }
    public var isRace: Bool { threadSafeSyncReturn { self._isRace.value } }
    public var comment: String? { threadSafeSyncReturn { self._comment.value } }
    public var isUserModified: Bool { threadSafeSyncReturn { self._isUserModified.value } }
    public var healthKitUUID: UUID? { threadSafeSyncReturn { self._healthKitUUID.value } }
    public var finishedRecording: Bool { threadSafeSyncReturn { self._finishedRecording.value } }
    public var ascend: Double { threadSafeSyncReturn { self._ascend.value } }
    public var descend: Double { threadSafeSyncReturn { self._descend.value } }
    public var activeDuration: Double { threadSafeSyncReturn { self._activeDuration.value } }
    public var pauseDuration: Double { threadSafeSyncReturn { self._pauseDuration.value } }
    public var dayIdentifier: String { threadSafeSyncReturn { self._dayIdentifier.value } }
    public var heartRates: [ORWorkoutHeartRateDataSampleInterface] { self._heartRates.value }
    public var routeData: [ORWorkoutRouteDataSampleInterface] { self._routeData.value }
    public var pauses: [ORWorkoutPauseInterface] { self._pauses.value }
    public var workoutEvents: [ORWorkoutEventInterface] { self._workoutEvents.value }
    public var events: [OREventInterface] {  Array(self._events.value) }
    
}

// MARK: - TempValueConvertible

extension Workout: TempValueConvertible {
    
    public var asTemp: TempWorkout {
        return TempWorkout(
            uuid: _uuid.value,
            workoutType: _workoutType.value,
            distance: _distance.value,
            steps: _steps.value,
            startDate: _startDate.value,
            endDate: _endDate.value,
            burnedEnergy: _burnedEnergy.value,
            isRace: _isRace.value,
            comment: _comment.value,
            isUserModified: _isUserModified.value,
            healthKitUUID: _healthKitUUID.value,
            finishedRecording: _finishedRecording.value,
            ascend: _ascend.value,
            descend: _descend.value,
            activeDuration: _activeDuration.value,
            pauseDuration: _pauseDuration.value,
            dayIdentifier: _dayIdentifier.value,
            heartRates: _heartRates.value.map { $0.asTemp },
            routeData: _routeData.value.map { $0.asTemp },
            pauses: _pauses.value.map { $0.asTemp },
            workoutEvents: _workoutEvents.value.map { $0.asTemp }
        )
    }
    
}
