//
//  DataManager+Query.swift
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
import CoreStore
import CoreLocation

extension DataManager {
    
    // MARK: - General
    
    /**
     Queries an object comforming to `ORDataType` with the provided `UUID` from the database.
     - parameter whereClause: the `CoreStore.Where` clause used for selection of the object
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the workout needs to be queried during a tranaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `ORDataType` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObject<ObjectType: ORDataType>(from whereClause: Where<ObjectType>, transaction: AsynchronousDataTransaction? = nil) -> ObjectType? {
        
        let object = try? (transaction as FetchableSource? ?? dataStack).fetchOne(From<ObjectType>().where(whereClause))
        return object
    }
    
    /**
     Queries an object comforming to `ORDataType` with the provided `UUID` from the database.
     - parameter whereClause: the `CoreStore.Where` clause used for selection of the object
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the workout needs to be queried during a tranaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `ORDataType` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObjects<ObjectType: ORDataType>(from whereClause: Where<ObjectType>, transaction: AsynchronousDataTransaction? = nil) -> [ObjectType] {
        
        let objects = try? (transaction as FetchableSource? ?? dataStack).fetchAll(From<ObjectType>().where(whereClause))
        return objects ?? []
    }
    
    /**
     Queries an object comforming to `ORDataType` with the provided `UUID` from the database.
     - parameter uuid: the `UUID` of the object that is supposed to be returned; if `nil` this function will return immediately with no value
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the workout needs to be queried during a tranaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `ORDataType` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObject<ObjectType: ORDataType>(from uuid: UUID?, transaction: AsynchronousDataTransaction? = nil) -> ObjectType? {
        
        guard let uuid = uuid else {
            return nil
        }
        
        return queryObject(from: \._uuid == uuid, transaction: transaction)
    }
    
    /**
     Queries an object comforming to `ORDataType` with the provided object's uuid from the database.
     - parameter anyObject: any object representing the wanted database object to be returned
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the workout needs to be queried during a tranaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `ORDataType` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObject<ObjectType: ORDataType>(from anyObject: ORDataInterface, transaction: AsynchronousDataTransaction? = nil) -> ObjectType? {
        
        return queryObject(from: anyObject.uuid, transaction: transaction)
    }
    
    /**
     Queries the count for objects of the given `ORDataType` and `UUID` returning whether it has duplicates in the database.
     - parameter uuid: the `UUID` of the workout being checked for duplicates; if `nil` this function will return immediately with `false`
     - parameter objectType: the type of the object being checked for duplicates
     - returns: `true` if the queried count is anything other than 0 meaning there are workouts with the given `UUID` present in the database.
     */
    public static func objectHasDuplicate<ObjectType: ORDataType>(uuid: UUID?, objectType: ObjectType.Type) -> Bool {
        
        guard let uuid = uuid else {
            return false
        }
        
        if let count = try? dataStack.fetchCount(From<ObjectType>().where(\._uuid == uuid)) {
            return count != 0
        }
        
        return false
        
    }
    
    /**
     Fetches the count of saved objects of a specific `ORObjectType` inside the database.
     - parameter of: the kind of `ORObjectType` to fetch the count of
     - returns: the number of counted objects as an `Int`
     */
    public static func fetchCount<ObjectType: ORDataType>(of _: ObjectType.Type) -> Int {
        let count = try? dataStack.fetchCount(From<ObjectType>())
        return count ?? 0
    }

    // MARK: - Debug Summary

    public struct DebugSummary: Sendable {

        public let databaseStorageSize: Int?
        public let cacheDiskSize: Int?
        public let workoutCount: Int
        public let routeDataSampleCount: Int
        public let workoutEventCount: Int
        public let heartRateDataSampleCount: Int
        public let eventCount: Int

    }

    /**
     Asynchronously queries the value-only database and cache information shown by the debug view.
     CoreStore counts and synchronous disk-size reads are performed on CoreStore's asynchronous
     transaction queue so no thread-confined database objects or blocking file-size work escapes to SwiftUI.
     - returns: a sendable debug summary value.
     */
    public static func debugSummary() async -> DebugSummary {
        await withCheckedContinuation { continuation in
            dataStack.perform(asynchronous: { (transaction) -> DebugSummary in
                DebugSummary(
                    databaseStorageSize: diskSize,
                    cacheDiskSize: CustomImageCache.mapImageCache.diskSize,
                    workoutCount: (try? transaction.fetchCount(From<Workout>())) ?? 0,
                    routeDataSampleCount: (try? transaction.fetchCount(From<WorkoutRouteDataSample>())) ?? 0,
                    workoutEventCount: (try? transaction.fetchCount(From<WorkoutEvent>())) ?? 0,
                    heartRateDataSampleCount: (try? transaction.fetchCount(From<WorkoutHeartRateDataSample>())) ?? 0,
                    eventCount: (try? transaction.fetchCount(From<Event>())) ?? 0
                )
            }) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure:
                    continuation.resume(returning: DebugSummary(
                        databaseStorageSize: nil,
                        cacheDiskSize: nil,
                        workoutCount: 0,
                        routeDataSampleCount: 0,
                        workoutEventCount: 0,
                        heartRateDataSampleCount: 0,
                        eventCount: 0
                    ))
                }
            }
        }
    }
    
    // MARK: - Workout Route
    
    /**
     Queries the route of a workout and converts each route sample into the corresponding `CLLocationDegrees`.
     - parameter workout: the object the route is going to be queried from, any `ORWorkoutInterface` will be accepted
     - parameter completion: the closure being called upon completion of the query
     - parameter success: indicates whether or not the query succeeded
     - parameter error: provides more detail on a query failure if one occured
     - parameter coordinates: the queried array of `CLLocationCoordinate2D`
     */
    public static func asyncLocationCoordinatesQuery(for workout: ORWorkoutInterface, completion: @escaping (_ error: LocationQueryError?, _ coordinates: [CLLocationCoordinate2D]) -> Void) {
        
        var error: LocationQueryError?
        
        dataStack.perform(asynchronous: { (transaction) -> [CLLocationCoordinate2D] in
            
            guard let workout = (workout as? Workout) ?? queryObject(from: workout.uuid, transaction: transaction) else {
                error = .notSaved
                return []
            }
            
            let samples = workout._routeData.value
            guard !samples.isEmpty else {
                error = .noRouteData
                return []
            }
            
            return samples.map { (sample) -> CLLocationCoordinate2D in
                CLLocationCoordinate2D(
                    latitude: sample._latitude.value,
                    longitude: sample._longitude.value
                )
            }
            
        }) { (result) in
            switch result {
            case .success(let coordinates):
                completion(error, coordinates)
            case .failure(let error):
                completion(.databaseError(error: error), [])
            }
        }
    }
    
    // MARK: - Workout Detail Snapshot

    /**
     Asynchronously builds an immutable, value-type `WorkoutDetailSnapshot` for the SwiftUI workout detail
     screen. The snapshot (scalar stats, route coordinates, and chart series) is built entirely on the
     CoreStore transaction queue using raw `_x.value` accessors, so no thread-confined CoreStore object ever
     escapes to the UI layer.
     - parameter id: the `UUID` of the workout to snapshot
     - returns: the snapshot, or `nil` if the workout could not be found or the transaction failed
     */
    public static func workoutDetailSnapshot(for id: UUID?) async -> WorkoutDetailSnapshot? {

        await withCheckedContinuation { continuation in

            dataStack.perform(asynchronous: { (transaction) -> WorkoutDetailSnapshot? in

                guard let workout: Workout = queryObject(from: id, transaction: transaction) else {
                    return nil
                }
                return WorkoutDetailSnapshot(workout)

            }) { (result) in
                switch result {
                case .success(let snapshot):
                    continuation.resume(returning: snapshot)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Backup
    
    /**
     Queries the data required to create a backup.
     - parameter inclusionType: the type of data that is supposed to be included in the backup
     - parameter completion: a closure providing the queried data and an optional error if something went wrong
     */
    public static func queryBackupData(for inclusionType: ExportManager.DataInclusionType, completion: @escaping (_ error: BackupQueryError?, _ data: Data?) -> Void) {
        
        var fetchSucceeded = false
        
        dataStack.perform(asynchronous: { (transaction) -> Data? in
            
            do {
                
                let tempWorkouts: [TempWorkout]
                let tempEvents: [TempEvent]
                
                switch inclusionType {
                case .all:
                    tempWorkouts = try transaction.fetchAll(From<Workout>()).map { $0.asTemp }
                    tempEvents = try transaction.fetchAll(From<Event>()).map { $0.asTemp }
                    
                case .someWorkouts(let includedWorkouts):
                    tempWorkouts = includedWorkouts.compactMap({ workoutRep -> Workout? in
                        queryObject(from: workoutRep, transaction: transaction)
                    }).map { $0.asTemp }
                    tempEvents = []
                    
                case .someEvents(let includedEvents):
                    var workouts = [Workout]()
                    let events = includedEvents.compactMap({ eventRep -> Event? in
                        let event: Event? = queryObject(from: eventRep, transaction: transaction)
                        if let event = event {
                            for workout in event._workouts.value where !workouts.contains(workout) {
                                workouts.append(workout)
                            }
                        }
                        return event
                    })
                    tempWorkouts = workouts.map { $0.asTemp }
                    tempEvents = events.map { $0.asTemp }
                }
                
                fetchSucceeded = true
                
                let backup = Backup(workouts: tempWorkouts, events: tempEvents)
                
                let json = try JSONEncoder().encode(backup)
                return json
                
            } catch {
                return nil
            }
            
        }) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    guard let data = data else {
                        completion(fetchSucceeded ? .encodeFailed : .fetchFailed, nil)
                        return
                    }
                    completion(nil, data)
                case .failure(let error):
                    completion(.databaseError(error: error), nil)
                }
            }
        }
        
        
    }
    
    // MARK: - HealthKit
    
    /**
     Queries the uuids corresponding to HealthKit workouts imported from or saved to AppleHealth and associated with workouts saved in the app.
     - parameter completion: the closure being called on the main thread with the queried UUIDs
     */
    public static func queryExistingHealthUUIDs(completion: @escaping ([UUID]) -> Void) {
        let completion = safeClosure(from: completion)

        dataStack.perform(asynchronous: { transaction -> [UUID] in
            return (try? transaction.queryAttributes(
                From<Workout>()
                    .select(NSDictionary.self, .attribute(\._healthKitUUID))
                    .where(\._healthKitUUID != nil))
                .compactMap { $0.first?.value as? UUID }
            ) ?? []
        }) { result in
            switch result {
            case .success(let uuids):
                completion(uuids)
            case .failure:
                completion([])
            }
        }
    }
}
