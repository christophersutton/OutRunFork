//
//  HealthStoreManager+Observer.swift
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
import HealthKit
import CoreStore

extension HealthStoreManager {
    private static let workoutAnchorData = UserPreference.Optional<Data>(key: "previousWorkoutAnchorData")
    private static let weightAnchorData = UserPreference.Optional<Data>(key: "previousWeightAnchorData")
    private static var workoutQuery: HKAnchoredObjectQuery?
    private static var weightQuery: HKAnchoredObjectQuery?
    private static var preferencesObserver: NSObjectProtocol?
    private static var workoutSetupPending = false
    private static var weightSetupPending = false
    private static let workoutBatches = HealthImportBatchQueue()
    private static let weightBatches = HealthImportBatchQueue()

    private static func anchor(_ preference: UserPreference.Optional<Data>) -> HKQueryAnchor? {
        guard let data = preference.value else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func commit(_ anchor: HKQueryAnchor?, to preference: UserPreference.Optional<Data>) {
        guard let anchor = anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        preference.value = data
    }

    /// Unlike the older convenience query, this distinguishes an empty database
    /// from a failed query. A failed duplicate check must never permit insertion.
    static func queryHealthImportIdentities(completion: @escaping (Set<UUID>?, Set<UUID>?) -> Void) {
        DataManager.dataStack.perform(asynchronous: { transaction -> (Set<UUID>, Set<UUID>) in
            let workouts = try transaction.fetchAll(From<Workout>())
            return (Set(workouts.compactMap { $0._healthKitUUID.value }),
                    Set(workouts.compactMap { $0._uuid.value }))
        }) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let ids): completion(ids.0, ids.1)
                case .failure: completion(nil, nil)
                }
            }
        }
    }

    private static func isLocalExport(_ workout: HKWorkout, localIDs: Set<UUID>) -> Bool {
        guard workout.sourceRevision.source == HKSource.default(),
              let value = workout.metadata?[HKMetadataKeyExternalUUID] as? String,
              let id = UUID(uuidString: value) else { return false }
        return localIDs.contains(id)
    }

    private static let importPersistence = HealthImportPersistence<HealthWorkout>(
        identity: { $0.hkWorkout.uuid },
        isLocalExport: { isLocalExport($0.hkWorkout, localIDs: $1) },
        prepare: { if $0.uuid == nil { $0.uuid = $0.hkWorkout.uuid } },
        query: { completion in
            queryHealthImportIdentities { health, local in
                guard let health = health, let local = local else { completion(nil); return }
                completion(HealthImportIdentities(health: health, local: local))
            }
        }, save: { workouts, completion in
            DataManager.saveWorkouts(objects: workouts) { success, _, _ in completion(success) }
        })

    /// Serializes duplicate checks and writes for both UI and observer imports.
    /// New imported rows have stable IDs; existing row identities remain unchanged.
    static func persistHealthWorkouts(_ workouts: [HealthWorkout], completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { importPersistence.persist(workouts, completion: completion) }
    }

    private static func stopWorkoutObserver() {
        if let query = workoutQuery { healthStore.stop(query) }
        workoutQuery = nil
        workoutBatches.reset()
    }

    /// Retain handles before execution, including while authorization is in flight.
    /// Health read permission is private; request completion permits querying, not
    /// an assertion that the user granted read access.
    static func setupObservers() {
        DispatchQueue.main.async {
            if preferencesObserver == nil {
                preferencesObserver = NotificationCenter.default.addObserver(
                    forName: UserDefaults.didChangeNotification, object: nil, queue: .main
                ) { _ in reconcileObserverPreferences() }
            }
            reconcileObserverPreferences()
            if UserPreferences.synchronizeWorkoutsWithAppleHealth.value,
               workoutQuery == nil, !workoutSetupPending {
                workoutSetupPending = true
                requestReadAuthorisation(for: workoutReadTypes) { ready in
                    workoutSetupPending = false
                    guard ready, UserPreferences.synchronizeWorkoutsWithAppleHealth.value, workoutQuery == nil else { return }
                    workoutBatches.reset()
                    let predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
                        Workout.WorkoutType.supportedTypes.map { HKQuery.predicateForWorkouts(with: $0.healthKitType) })
                    let query = HKAnchoredObjectQuery(type: HealthType.Workout, predicate: predicate,
                        anchor: anchor(workoutAnchorData), limit: HKObjectQueryNoLimit, resultsHandler: receiveWorkouts)
                    query.updateHandler = receiveWorkouts
                    workoutQuery = query
                    healthStore.execute(query)
                }
            }
            if UserPreferences.synchronizeWeightWithAppleHealth.value,
               weightQuery == nil, !weightSetupPending {
                weightSetupPending = true
                requestReadAuthorisation(for: [HealthType.BodyMass]) { ready in
                    weightSetupPending = false
                    guard ready, UserPreferences.synchronizeWeightWithAppleHealth.value, weightQuery == nil else { return }
                    weightBatches.reset()
                    let query = HKAnchoredObjectQuery(type: HealthType.BodyMass, predicate: nil,
                        anchor: anchor(weightAnchorData), limit: HKObjectQueryNoLimit, resultsHandler: receiveWeight)
                    query.updateHandler = receiveWeight
                    weightQuery = query
                    healthStore.execute(query)
                }
            }
        }
    }

    private static let receiveWeight: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { query, samples, deleted, newAnchor, error in
        DispatchQueue.main.async {
            guard weightQuery === query, UserPreferences.synchronizeWeightWithAppleHealth.value else { return }
            guard error == nil, samples != nil, deleted != nil else {
                healthStore.stop(query)
                weightQuery = nil
                weightBatches.reset()
                return
            }
            weightBatches.enqueue(process: { finish in
                queryMostRecentWeightSample(completion: finish)
            }, commit: {
                commit(newAnchor, to: weightAnchorData)
            }, failure: {
                healthStore.stop(query)
                weightQuery = nil
            })
        }
    }

    private static func reconcileObserverPreferences() {
        if !UserPreferences.synchronizeWorkoutsWithAppleHealth.value { stopWorkoutObserver() }
        if !UserPreferences.synchronizeWeightWithAppleHealth.value, let query = weightQuery {
            healthStore.stop(query)
            weightQuery = nil
            weightBatches.reset()
        }
    }

    private static let receiveWorkouts: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { query, samples, deleted, newAnchor, error in
        DispatchQueue.main.async {
            guard workoutQuery === query, UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { return }
            guard error == nil, let samples = samples, deleted != nil else { stopWorkoutObserver(); return }
            workoutBatches.enqueue(process: { finish in
                guard UserPreferences.automaticallyImportNewHealthWorkouts.value else { finish(true); return }
                queryHealthImportIdentities { existing, local in
                    guard workoutQuery === query, UserPreferences.synchronizeWorkoutsWithAppleHealth.value,
                          let ids = existing, let local = local else { finish(false); return }
                    let workouts = samples.compactMap { $0 as? HKWorkout }.filter {
                        !ids.contains($0.uuid) && !isLocalExport($0, localIDs: local)
                    }
                    createHealthWorkoutsResult(from: workouts) { result in
                        switch result {
                        case .success(let converted):
                            guard workoutQuery === query, UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { finish(false); return }
                            persistHealthWorkouts(converted, completion: finish)
                        case .failure: DispatchQueue.main.async { finish(false) }
                        }
                    }
                }
            }, commit: {
                // Health deletions never delete local data or clear identities: an
                // absent Health parent must not cause an automatic re-export.
                commit(newAnchor, to: workoutAnchorData)
            }, failure: {
                healthStore.stop(query)
                workoutQuery = nil
                // Keep the old anchor. No later batch can commit past this failure.
            })
        }
    }
}
