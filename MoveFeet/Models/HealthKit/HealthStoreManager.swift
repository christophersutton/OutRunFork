//
//  HealthStoreManager.swift
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

import HealthKit
import CoreLocation
import CoreStore

class HealthStoreManager {
    
    /// A reference to the `HKHealthStore`, the central database and API of HealthKit.
    static let healthStore = HKHealthStore()
    
    // MARK: - Constants
    
    /// A class containing static instances of `HKSampleType` for reference to HealthKit objects.
    class HealthType {
        
        static let Workout = HKObjectType.workoutType()
        static let ActiveEnergyBurned = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        static let DistanceWalkingRunning = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        static let Route = HKObjectType.seriesType(forIdentifier: HKWorkoutRouteTypeIdentifier)!
        static let BodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        static let HeartRate = HKObjectType.quantityType(forIdentifier: .heartRate)!
        static let StepCount = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        /// A static constant containing all HealthKit types implemented and thereby usable in OutRun.
        static let allImplementedTypes: [HKSampleType] = [
            HealthType.Workout,
            HealthType.ActiveEnergyBurned,
            HealthType.DistanceWalkingRunning,
            HealthType.Route,
            HealthType.BodyMass,
            HealthType.HeartRate,
            HealthType.StepCount
        ]
        
    }
    
    /// A class containing static instances of special `HKUnit` objects.
    class HealthUnit {
        
        static let HeartRate = HKUnit.count().unitDivided(by: HealthKit.HKUnit.minute())
        static let Kilogram = HKUnit(from: .kilogram)
        
    }
    
    // MARK: - Authorisation
    
    static func healthType(_ kind: HealthAccessPlan.Kind) -> HKSampleType {
        switch kind {
        case .workout: return HealthType.Workout
        case .route: return HealthType.Route
        case .distance: return HealthType.DistanceWalkingRunning
        case .energy: return HealthType.ActiveEnergyBurned
        case .steps: return HealthType.StepCount
        case .heartRate: return HealthType.HeartRate
        case .bodyMass: return HealthType.BodyMass
        }
    }
    static var workoutReadTypes: [HKSampleType] {
        HealthAccessPlan(workouts: true, weight: false).read.map(healthType)
    }
    static var workoutWriteTypes: [HKSampleType] {
        HealthAccessPlan(workouts: true, weight: false).write.map(healthType)
    }

    /// Completion reports that the authorization sheet completed, never read access.
    static func requestReadAuthorisation(for types: [HKSampleType], completion: @escaping (Bool) -> Void) {
        requestAuthorisation(read: types, write: [], completion: completion)
    }

    // Injectable only at the HealthKit boundary; production calls the system store.
    static var healthDataAvailable: () -> Bool = { HKHealthStore.isHealthDataAvailable() }
    static var authorizationRequest: (Set<HKSampleType>, Set<HKObjectType>, @escaping (Bool, Error?) -> Void) -> Void = {
        healthStore.requestAuthorization(toShare: $0, read: $1, completion: $2)
    }

    static func requestAuthorisation(read: [HKSampleType], write: [HKSampleType], completion: @escaping (Bool) -> Void) {
        let completion = safeClosure(from: completion)
        guard !read.isEmpty || !write.isEmpty else { completion(true); return }
        guard healthDataAvailable() else { completion(false); return }
        authorizationRequest(Set(write), Set<HKObjectType>(read)) { success, error in
            completion(success && error == nil)
        }
    }

    /// This helper is exclusively for writes. Read queries must not use sharing status.
    static func gainAuthorisation(for requestedTypes: [HKSampleType] = HealthType.allImplementedTypes, completion: @escaping (Bool, [HKSampleType]) -> Void) {
        requestAuthorisation(read: [], write: requestedTypes) { ready in
            let authorised = requestedTypes.filter { authorizationStatus(for: $0) == .sharingAuthorized }
            completion(ready && authorised.count == requestedTypes.count, authorised)
        }
    }

    /**
     A function to provide the current authorisation status of an HealthKit object type.
     - parameter type: the type that is supposed to be checked
     - returns: the authorisation status of the provided type
     */
    static func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        return HealthStoreManager.healthStore.authorizationStatus(for: type)
    }
    
    /**
     Checks the authorisation status for a HKObjektType and adds it to an array if unauthorised.
     - parameter type: the type to be checked and added
     - parameter array: the array the type is suppused to be added to
     - parameter onAuthorised: the closure being performed if authorisation is granted
     */
    static func checkAuthorisation(for samples: HKQuantitySample?..., authArray: inout [HKQuantitySample], unauthArray: inout [HKObjectType]) {
        
        for sample in samples {
            guard let sample = sample else { continue }
            if authorizationStatus(for: sample.quantityType) == .sharingAuthorized {
                authArray.append(sample)
            } else {
                unauthArray.append(sample.quantityType)
            }
        }
    }
    
    // MARK: - Saving
    
    /**
     Saves the provided workout to the healthStore.
     - parameter workout: the workout that is supposed to be saved
     - parameter completion: the closure performed upon the completion of saving
     */
    static func saveHealthWorkout(for workout: ORWorkoutInterface, completion: @escaping (HealthError?, HKWorkout?) -> Void) {
        DispatchQueue.main.async {
            // CoreStore values can change while Health callbacks are in flight. All parent,
            // sample and route writes in this operation must use one immutable value capture.
            let snapshot = TempWorkout(from: workout)
            exportOperations.enqueue { done in
                performHealthExport(for: snapshot) { error, parent in
                    completion(error, parent)
                    done()
                }
            }
        }
    }

    /**
     Saves the provided weight to the health store.
     - parameter weight: the measurement providing the weight data to be saved
     - parameter completion: the closure performed upon the completion of saving
     */
    static func saveWeight(for weight: NSMeasurement, completion: @escaping (HealthError?) -> Void) {
        
        guard UserPreferences.synchronizeWeightWithAppleHealth.value else { completion(.insufficientAuthorisation); return }
        guard weight.canBeConverted(to: UnitMass.kilograms),
              let kilograms = weight.converting(to: UnitMass.kilograms).value as Optional,
              let quantity = createHealthQuantity(value: kilograms, unit: HealthUnit.Kilogram)
        else { completion(.invalidInput); return }
        
        gainAuthorisation(for: [HealthType.BodyMass]) { authorisation, _ in
            guard authorisation, UserPreferences.synchronizeWeightWithAppleHealth.value else { completion(.insufficientAuthorisation); return }
            
            let timestamp = Date()
            
            let sample = HKQuantitySample(
                type: HealthType.BodyMass,
                quantity: quantity,
                start: timestamp,
                end: timestamp,
                metadata: [ HKMetadataKeyWasUserEntered : true ]
            )
            
            HealthStoreManager.healthStore.save(sample) { success, error in
                completion(success && error == nil ? nil : .healthKitError(error: error))
            }
        }
    }
    
    /**
     Saves all workouts in the database to Apple Health while ignoring the ones already saved.
     - parameter completion: the closure called upon completion of saving
     - parameter error: an optional `HealthError`, when nil the operation was successful
     - parameter allSavedAlready: a boolean indicating whether all workouts were saved to Health already
     */
    static func saveAllWorkouts(completion: @escaping (_ error: HealthError?, _ allSavedAlready: Bool) -> Void) {
        DispatchQueue.main.async {
            guard UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { completion(.insufficientAuthorisation, false); return }
            do {
                let pending = try exportLedger.pendingIDs()
                // Ordinary unsynced records have a nil Health UUID. Linked partial
                // exports are also included so Sync All repairs attachments.
                let unlinked: [Workout] = DataManager.queryObjects(from: \._healthKitUUID == nil)
                let linkedRetries: [Workout] = pending.compactMap { DataManager.queryObject(from: $0) }
                var seen = Set<UUID>()
                let workouts = (unlinked + linkedRetries).filter { workout in
                    guard let id = workout.uuid else { return false }
                    return seen.insert(id).inserted
                }
                guard !workouts.isEmpty else { completion(nil, true); return }
                var index = 0
                var failure: HealthError?
                func next() {
                    guard index < workouts.count else { completion(failure, false); return }
                    let workout = workouts[index]
                    index += 1
                    saveHealthWorkout(for: workout) { error, _ in
                        if let error = error { failure = error }
                        next()
                    }
                }
                next()
            } catch { completion(.exportRecoveryRequired, false) }
        }
    }

    // MARK: - Deletion
    
    /**
     Deletes the `HKWorkout` associated with the provided workout object from the health store.
     - parameter workout: the workout for which the associated health workout is supposed to be deleted
     - parameter completion: the closure being performed upon completion indicating if an error occured
     */
    static func deleteHealthWorkout(for workout: ORWorkoutInterface, completion: @escaping (HealthError?) -> Void) {

        deleteHealthWorkout(reference: workout.healthKitUUID, completion: completion)

    }

    /**
     Deletes the `HKWorkout` matching the provided HealthKit UUID.
     - parameter reference: the HealthKit UUID stored on a workout
     - parameter completion: the closure being performed upon completion indicating if an error occured
     */
    static func deleteHealthWorkout(reference: UUID?, completion: @escaping (HealthError?) -> Void) {

        guard let reference else { completion(.invalidInput); return }
        let completion = safeClosure(from: completion)
        
        gainAuthorisation(for: [HealthType.Workout]) { workoutAuthorisation, _ in
            guard workoutAuthorisation else { completion(.insufficientAuthorisation); return }
            
            queryHealthObject(of: HealthType.Workout, with: reference) { healthWorkout, error in
                guard let healthWorkout = healthWorkout as? HKWorkout else { completion(.healthKitError(error: error)); return }
                
                let assosicationPredicate = HKQuery.predicateForObjects(from: healthWorkout)
                
                let sampleTypesToDelete = HealthType.allImplementedTypes.filter { $0 != HealthType.Workout }
                let deletionGroup = DispatchGroup()
                
                sampleTypesToDelete.forEach { type in
                    deletionGroup.enter()
                    HealthStoreManager.healthStore.deleteObjects(of: type, predicate: assosicationPredicate) { _, _, _ in
                        deletionGroup.leave()
                    }
                }
                
                deletionGroup.notify(queue: .global(qos: .userInitiated)) {
                    HealthStoreManager.healthStore.delete(healthWorkout) { success, error in
                        guard success else { completion(.healthKitError(error: error)); return }
                        completion(nil)
                    }
                }
            }
        }
    }
    
    /**
     Deletes all objects created by this app from the health store.
     - parameter completion: the closure being performed upon completion
     */
    static func deleteAllObjects(completion: @escaping (HealthError?) -> Void) {
        
        let completion = safeClosure(from: completion)
        let predicate = HKQuery.predicateForObjects(from: HKSource.default())
        
        var deleteCount = 0
        
        gainAuthorisation { authorisation, authorisedTypes in
            guard authorisation else { completion(.insufficientAuthorisation); return }
            
            authorisedTypes.forEach { type in
                HealthStoreManager.healthStore.deleteObjects(of: type, predicate: predicate) { _, _, error in
                    deleteCount += 1
                    if deleteCount == HealthType.allImplementedTypes.count {
                        completion(authorisedTypes == HealthType.allImplementedTypes ? nil : .optionalAuthorisationMissing)
                    }
                }
            }
        }
    }
    
    // MARK: - Updating
    
    /**
     Updates the associated `HKWorkout` by resaving it with the new data and renewing the reference in the workout object.
     - parameter workout: the workout which is supposed to be updated in the health store
     - parameter completion: the closure being performed upon completion indicating if an error occured
     */
    static func updateHealthWorkout(for workout: ORWorkoutInterface, completion: @escaping (HealthError?) -> Void) {
        // Health workouts are immutable. Never automatically delete history to
        // mirror a local edit; the local record is the source of edited values.
        guard workout.healthKitUUID == nil else { completion(.existingHealthHistoryPreserved); return }
        saveHealthWorkout(for: workout) { error, _ in completion(error) }
    }

    // MARK: - Object Creation
    
    /**
     Creates an `HKQuantity` object from the provided data if the value is not `nil`
     - parameter value: the value of the quantity; if `nil` this function will not return a value
     - parameter unit: the unit of the quantity
     - returns: an object of type `HKQuantity` if the provided data was valid
     */
    static func createHealthQuantity(value: Double?, unit: HKUnit) -> HKQuantity? {
        
        guard let value = value else { return nil }
        
        return HKQuantity(
            unit: unit,
            doubleValue: value
        )
        
    }
    
    /**
     Creates an `HKQuantitySample` object from the provided data if the value is not `nil`.
     - parameter healthType: the type of the quantity sample
     - parameter quanitity: the quantity to be saved
     - parameter healthWorkout: the health workout this sample is supposed to be attached to
     - returns: an object of type `HKQuantitySample`
     */
    static func createHealthQuantitySample(of healthType: HKQuantityType?, quantity: HKQuantity?, associatedWorkout healthWorkout: HKWorkout) -> HKQuantitySample? {
        
        guard let healthType = healthType, let quantity = quantity else { return nil }
        
        return HKQuantitySample(
            type: healthType,
            quantity: quantity,
            start: healthWorkout.startDate,
            end: healthWorkout.endDate,
            device: healthWorkout.device,
            metadata: healthWorkout.metadata
        )
    }
    
    /**
     Creates an `HKQuantitySample` object from the provided data if the value is not `nil`.
     - parameter healthType: the type of the quantity sample
     - parameter quanitityValue: the value to be saved in the quantity sample; if `nil` this function will not return a value
     - parameter quantityUnit: the unit of the quantity sample
     - parameter healthWorkout: the health workout this sample is supposed to be attached to
     - returns: an object of type `HKQuantitySample` if the provided data was valid
     */
    static func createHealthQuantitySample(of healthType: HKQuantityType?, quantityValue: Double?, quantityUnit: HKUnit, associatedWorkout healthWorkout: HKWorkout) -> HKQuantitySample? {
        
        return createHealthQuantitySample(
            of: healthType,
            quantity: createHealthQuantity(
                value: quantityValue,
                unit: quantityUnit
            ),
            associatedWorkout: healthWorkout
        )
    }
    
    /**
     Creates `HKWorkoutEvent`s from the pause and workout event objects of a given workout
     - parameter workout: the workout object the pause and workout event objects are taken from
     - returns: the created array of `HKWorkoutEvent`
     */
    static func createWorkoutEvents(from workout: ORWorkoutInterface) -> [HKWorkoutEvent] {
        
        var workoutEvents = [HKWorkoutEvent]()
        
        workout.pauses.forEach { pause in
            
            var events = [
                HKWorkoutEvent(
                    type: .pause,
                    dateInterval: DateInterval(start: pause.startDate, duration: 0),
                    metadata: nil
                ),
                workout.endDate == pause.endDate ? nil : HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(start: pause.endDate, duration: 0),
                    metadata: nil
                )
            ]
            
            if pause.pauseType == .automatic {
                events.insert(
                    HKWorkoutEvent(
                        type: .motionPaused,
                        dateInterval: DateInterval(start: pause.startDate, duration: 0),
                        metadata: nil
                    ),
                    at: 1
                )
                events.append(
                    workout.endDate == pause.endDate ? nil : HKWorkoutEvent(
                        type: .motionResumed,
                        dateInterval: DateInterval(start: pause.endDate, duration: 0),
                        metadata: nil
                    )
                )
            }
            
            workoutEvents.append(contentsOf: events.filterNil())
        }
        
        workout.workoutEvents.forEach { event in
            guard let type = event.eventType.healthKitType else { return }
            workoutEvents.append(
                HKWorkoutEvent(
                    type: type,
                    dateInterval: DateInterval(start: event.timestamp, duration: 0),
                    metadata: nil
                )
            )
        }
        
        return workoutEvents
    }
    
    /**
     Builds the `HKWorkoutRoute` and attatches it to provided `HKWorkout`.
     - parameter workout: the workout object the route data is taken from
     - parameter healthWorkout: the health workout the route is supposed to be attached to
     */
    static func createWorkoutRoute(from workout: ORWorkoutInterface, andAttachTo healthWorkout: HKWorkout, identifier: String, completion: @escaping (Bool, Error?) -> Void) {
        guard !workout.routeData.isEmpty else { completion(true, nil); return }
        let locations = workout.routeData.compactMap { CLLocation(workout: $0) }
        guard locations.count == workout.routeData.count else { completion(false, HealthError.invalidInput); return }
        let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        builder.insertRouteData(locations) { success, error in
            guard success else { completion(false, error); return }
            builder.finishRoute(with: healthWorkout, metadata: [HKMetadataKeyExternalUUID: identifier]) { route, error in
                completion(route != nil && error == nil, error)
            }
        }
    }

    /**
     Creates health samples from the heart rate data of the provided workout.
     - parameter workout: the workout object the heart rate data is taken from
     - returns: the `HKQuantitySample`s generated from the heart rate data
     */
    static func createHeartRateSamples(from workout: ORWorkoutInterface) -> [HKQuantitySample] {
        
        return workout.heartRates.compactMap { heartRateSample -> HKQuantitySample? in
            guard let quantity = createHealthQuantity(value: Double(heartRateSample.heartRate), unit: HealthUnit.HeartRate) else { return nil }
            
            return HKQuantitySample(
                type: HealthType.HeartRate,
                quantity: quantity,
                start: heartRateSample.timestamp,
                end: heartRateSample.timestamp
            )
        }
    }
    
    /**
     Creates a `HealthWorkout` from an `HKWorkout` and queries additional data required to form the object.
     - returns: the finished `HealthWorkout`
     */
    static func createHealthWorkouts(from hkWorkouts: [HKWorkout], completion: @escaping ([HealthWorkout]) -> Void) {
        createHealthWorkoutsResult(from: hkWorkouts) { result in
            completion((try? result.get()) ?? [])
        }
    }

    static func createHealthWorkoutsResult(from hkWorkouts: [HKWorkout], completion: @escaping (Result<[HealthWorkout], HealthError>) -> Void) {
        guard !hkWorkouts.isEmpty else { completion(.success([])); return }
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.wcc.movefeet.healthConversion")
        var results = Array<HealthWorkout?>(repeating: nil, count: hkWorkouts.count)
        for (index, workout) in hkWorkouts.enumerated() {
            group.enter()
            createHealthWorkout(from: workout) { converted in
                queue.async { results[index] = converted; group.leave() }
            }
        }
        group.notify(queue: queue) {
            let result: Result<[HealthWorkout], HealthError> = results.allSatisfy { $0 != nil }
                ? .success(results.compactMap { $0 }) : .failure(.importConversionFailed)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func createHealthWorkout(from hkWorkout: HKWorkout, completion: @escaping (_ healthWorkout: HealthWorkout?) -> Void) {
        let stepsMapper: (Int?, HKQuantity, DateInterval) -> Int = { lastValue, quantity, _ in
            HealthImportValues.addingSteps(lastValue, Int(quantity.doubleValue(for: .count())))
        }
        let heartRateMapper: ([TempWorkoutHeartRateDataSample]?, HKQuantity, DateInterval) -> [TempWorkoutHeartRateDataSample] = { lastValue, quantity, timeInterval -> [TempWorkoutHeartRateDataSample] in
            var values = lastValue ?? []
            values.append(.init(
                uuid: nil,
                heartRate: Int(quantity.doubleValue(for: HealthUnit.HeartRate)),
                timestamp: timeInterval.start
            ))
            return values
        }
        
        let conversionGroup = DispatchGroup()
        let resultQueue = DispatchQueue(label: "com.tifraedrich.OutRun.HealthStoreManager.healthWorkout")
        var conversionFailed = false
        var steps: Int?
        var routeData = [CLLocation]()
        var heartRates = [TempWorkoutHeartRateDataSample]()

        conversionGroup.enter()
        queryAnchoredHealthSeriesData(of: HealthType.StepCount, attachedTo: hkWorkout, transform: stepsMapper) { queriedSteps, error in
            resultQueue.async {
                conversionFailed = conversionFailed || error != nil
                steps = queriedSteps
                conversionGroup.leave()
            }
        }

        conversionGroup.enter()
        queryAnchoredWorkoutRoute(attachedTo: hkWorkout) { queriedRouteData, error in
            resultQueue.async {
                conversionFailed = conversionFailed || error != nil
                routeData = queriedRouteData
                conversionGroup.leave()
            }
        }

        conversionGroup.enter()
        queryAnchoredHealthSeriesData(of: HealthType.HeartRate, attachedTo: hkWorkout, transform: heartRateMapper) { queriedHeartRates, error in
            resultQueue.async {
                conversionFailed = conversionFailed || error != nil
                heartRates = queriedHeartRates ?? []
                conversionGroup.leave()
            }
        }

        conversionGroup.notify(queue: resultQueue) {
            guard !conversionFailed else { completion(nil); return }
            completion(HealthWorkout(
                hkWorkout,
                steps: steps,
                route: routeData,
                heartRates: heartRates
            ))
        }
    }
}
