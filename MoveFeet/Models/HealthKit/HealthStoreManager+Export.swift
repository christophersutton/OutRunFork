import Foundation
import HealthKit
import CoreStore

extension HealthStoreManager {
    static let exportOperations = HealthSerialOperations()
    static let exportLedger = HealthExportLedger()
    private static let exportVersionKey = "com.wcc.movefeet.exportVersion"

    static func exportContentDigest(for workout: ORWorkoutInterface) throws -> String {
        let content = TempWorkout(from: workout)
        // These local-only values and the reference written during export do not change Health data.
        content.healthKitUUID = nil
        content.comment = nil
        content.isRace = false
        content.dayIdentifier = ""
        return try HealthExportFingerprint.digest(content)
    }

    /// Always reconcile against app-owned Health objects, even if the process
    /// died between a Health save and the local reference/ledger write.
    static func performHealthExport(for workout: ORWorkoutInterface, completion: @escaping (HealthError?, HKWorkout?) -> Void) {
        guard UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { completion(.insufficientAuthorisation, nil); return }
        guard let id = workout.uuid else { completion(.invalidInput, nil); return }
        let entry: HealthExportLedger.Entry?
        let digest: String
        do {
            entry = try exportLedger.entry(for: id)
            digest = try exportContentDigest(for: workout)
        } catch { completion(.exportRecoveryRequired, nil); return }
        guard HealthExportFingerprint.canResume(recorded: entry?.contentDigest, current: digest) else {
            completion(.exportRecoveryRequired, nil); return
        }

        requestAuthorisation(read: [HealthType.Workout] + workoutWriteTypes,
                             write: workoutWriteTypes) { ready in
            guard ready, authorizationStatus(for: HealthType.Workout) == .sharingAuthorized else {
                completion(.insufficientAuthorisation, nil); return
            }
            guard UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { completion(.insufficientAuthorisation, nil); return }
            // Existing linked imports/history are preserved without attachments.
            if let reference = workout.healthKitUUID, entry == nil {
                queryHealthObject(of: HealthType.Workout, with: reference) { sample, error in
                    guard let parent = sample as? HKWorkout else { completion(.exportRecoveryRequired, nil); return }
                    completion(nil, parent)
                }
                return
            }
            let external = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id.uuidString])
            let owned = HKQuery.predicateForObjects(from: HKSource.default())
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [external, owned])
            let query = HKSampleQuery(sampleType: HealthType.Workout, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                DispatchQueue.main.async {
                    guard UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { completion(.insufficientAuthorisation, nil); return }
                    guard error == nil, let parents = samples as? [HKWorkout], parents.count <= 1 else {
                        completion(.exportRecoveryRequired, nil); return
                    }
                    if let parent = parents.first {
                        guard HealthExportRecovery.canReuse(expectedStart: workout.startDate, expectedEnd: workout.endDate,
                            expectedActivity: workout.workoutType.healthKitType.rawValue, start: parent.startDate,
                            end: parent.endDate, activity: parent.workoutActivityType.rawValue,
                            parent: parent.uuid, ledgerParent: entry?.parent,
                            expectedDistance: workout.distance, distance: parent.totalDistance?.doubleValue(for: .meter()),
                            expectedEnergy: workout.burnedEnergy, energy: parent.totalEnergyBurned?.doubleValue(for: .kilocalorie())) else {
                            completion(.exportRecoveryRequired, parent); return
                        }
                        // Pre-existing exports have no new attachment identifiers.
                        // Leave their samples untouched to preserve Health history.
                        guard parent.metadata?[exportVersionKey] as? Int == 1 else {
                            do { try exportLedger.set(.init(parent: parent.uuid), for: id) }
                            catch { completion(.exportIncomplete, parent); return }
                            persistHealthReference(id: id, parent: parent.uuid) { success in
                                guard success else { completion(.exportIncomplete, parent); return }
                                do { try exportLedger.set(nil, for: id) }
                                catch { completion(.exportIncomplete, parent); return }
                                completion(nil, parent)
                            }
                            return
                        }
                        finishExport(workout, parent: parent, id: id, entry: entry, digest: digest, completion: completion)
                    } else {
                        guard HealthExportRecovery.canCreate(ledgerParent: entry?.parent, localReference: workout.healthKitUUID) else {
                            completion(.exportRecoveryRequired, nil); return
                        }
                        do { try exportLedger.set(.init(contentDigest: digest), for: id) }
                        catch { completion(.exportRecoveryRequired, nil); return }
                        let parent = HKWorkout(activityType: workout.workoutType.healthKitType,
                            start: workout.startDate, end: workout.endDate, workoutEvents: createWorkoutEvents(from: workout),
                            totalEnergyBurned: createHealthQuantity(value: workout.burnedEnergy, unit: .kilocalorie()),
                            totalDistance: createHealthQuantity(value: workout.distance, unit: .meter()), device: HKDevice.local(),
                            metadata: [HKMetadataKeyExternalUUID: id.uuidString, HKMetadataKeyWasUserEntered: workout.isUserModified,
                                       exportVersionKey: 1])
                        healthStore.save(parent) { success, error in
                            DispatchQueue.main.async {
                                guard success, error == nil else { completion(.healthKitError(error: error), nil); return }
                                finishExport(workout, parent: parent, id: id, entry: nil, digest: digest, completion: completion)
                            }
                        }
                    }
                }
            }
            healthStore.execute(query)
        }
    }

    private static func finishExport(_ workout: ORWorkoutInterface, parent: HKWorkout, id: UUID,
                                     entry: HealthExportLedger.Entry?, digest: String, completion: @escaping (HealthError?, HKWorkout?) -> Void) {
        var state = entry ?? .init()
        // Entries made before content fingerprints must revalidate every sample group.
        if state.contentDigest == nil { state.completed = [] }
        state.contentDigest = digest
        state.parent = parent.uuid
        do { try exportLedger.set(state, for: id) }
        catch { completion(.exportIncomplete, parent); return }
        persistHealthReference(id: id, parent: parent.uuid) { success in
            guard success else { completion(.exportIncomplete, parent); return }
            attachExport(workout, parent: parent, id: id, state: state, completion: completion)
        }
    }

    private static func persistHealthReference(id: UUID, parent: UUID, completion: @escaping (Bool) -> Void) {
        DataManager.dataStack.perform(asynchronous: { transaction in
            guard let workout = try transaction.fetchOne(From<Workout>().where(\._uuid == id)),
                  workout._healthKitUUID.value == nil || workout._healthKitUUID.value == parent,
                  let edit = transaction.edit(workout) else { throw HealthError.exportRecoveryRequired }
            edit._healthKitUUID .= parent
        }) { result in
            DispatchQueue.main.async {
                switch result {
                case .success: completion(true)
                case .failure: completion(false)
                }
            }
        }
    }

    private static func attachExport(_ workout: ORWorkoutInterface, parent: HKWorkout, id: UUID,
                                     state initialState: HealthExportLedger.Entry,
                                     completion: @escaping (HealthError?, HKWorkout?) -> Void) {
        var state = initialState
        let distance = createHealthQuantitySample(of: workout.workoutType.healthKitDistanceType,
            quantityValue: workout.distance, quantityUnit: .meter(), associatedWorkout: parent)
        let energy = createHealthQuantitySample(of: HealthType.ActiveEnergyBurned,
            quantityValue: workout.burnedEnergy, quantityUnit: .kilocalorie(), associatedWorkout: parent)
        let steps = createHealthQuantitySample(of: HealthType.StepCount,
            quantityValue: Double(workout.steps), quantityUnit: .count(), associatedWorkout: parent)
        let groups: [String: [HKQuantitySample]] = ["distance": [distance].compactMap { $0 },
            "energy": [energy].compactMap { $0 }, "steps": [steps].compactMap { $0 },
            "heartRate": createHeartRateSamples(from: workout).sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.quantity.doubleValue(for: HealthUnit.HeartRate) < $1.quantity.doubleValue(for: HealthUnit.HeartRate)
            }]
        var denied = false
        HealthAttachmentBatch.run(keys: ["distance", "energy", "steps", "heartRate", "route"], completed: state.completed,
            attach: { key, attached in
                guard UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { attached(false); return }
                if key == "route" {
                    guard !workout.routeData.isEmpty else { attached(true); return }
                    guard authorizationStatus(for: HealthType.Route) == .sharingAuthorized else { denied = true; attached(false); return }
                    let identifier = "movefeet.\(id.uuidString).route"
                    queryHealthObjects(of: HealthType.Route, attachedTo: parent) { (routes: [HKWorkoutRoute]?, error) in
                        guard error == nil, let routes = routes else { attached(false); return }
                        if routes.contains(where: { $0.metadata?[HKMetadataKeyExternalUUID] as? String == identifier }) { attached(true); return }
                        createWorkoutRoute(from: workout, andAttachTo: parent, identifier: identifier) { success, error in
                            DispatchQueue.main.async { attached(success && error == nil) }
                        }
                    }
                    return
                }
                let samples = groups[key] ?? []
                guard let type = samples.first?.quantityType else { attached(true); return }
                guard authorizationStatus(for: type) == .sharingAuthorized else { denied = true; attached(false); return }
                reconcileAndAttach(samples, type: type, key: key, localID: id, parent: parent, completion: attached)
            }, checkpoint: { key in
                state.completed.insert(key)
                do { try exportLedger.set(state, for: id); return true }
                catch { return false }
            }, completion: { success in
                if success {
                    do { try exportLedger.set(nil, for: id) }
                    catch { completion(.exportIncomplete, parent); return }
                    completion(nil, parent)
                } else {
                    completion(denied ? .exportOptionalDataDenied : .exportIncomplete, parent)
                }
            })
    }

    /// Reuse even saved-but-unattached samples after an interrupted add operation.
    /// All lookups are constrained to this app's source and exact export identifiers.
    private static func reconcileAndAttach(_ samples: [HKQuantitySample], type: HKQuantityType,
                                          key: String, localID: UUID, parent: HKWorkout,
                                          completion: @escaping (Bool) -> Void) {
        let identifiers = samples.indices.map { "movefeet.\(localID.uuidString).\(key).\($0)" }
        queryHealthObjects(of: type, attachedTo: parent) { (attached: [HKQuantitySample]?, error) in
            guard error == nil, let attached = attached else { completion(false); return }
            let attachedIDs = Set(attached.map { $0.uuid })
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForObjects(from: HKSource.default()),
                HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: identifiers)
            ])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, saved, error in
                DispatchQueue.main.async {
                    guard error == nil, let saved = saved as? [HKQuantitySample] else { completion(false); return }
                    let expected = Dictionary(uniqueKeysWithValues: zip(identifiers, samples))
                    guard saved.allSatisfy({ existing in
                        guard let identifier = existing.metadata?[HKMetadataKeyExternalUUID] as? String,
                              let sample = expected[identifier] else { return false }
                        return existing.startDate == sample.startDate && existing.endDate == sample.endDate &&
                            existing.quantity.compare(sample.quantity) == .orderedSame
                    }) else { completion(false); return }
                    let savedIDs = Dictionary(grouping: saved, by: { $0.metadata?[HKMetadataKeyExternalUUID] as? String ?? "" })
                        .mapValues { $0.map { $0.uuid } }
                    guard let plan = HealthSampleRecovery.plan(expected: identifiers, saved: savedIDs, attached: attachedIDs) else {
                        completion(false); return
                    }
                    var toAttach: [HKQuantitySample] = []
                    for action in plan {
                        switch action {
                        case .attach(let id):
                            guard let existing = saved.first(where: { $0.uuid == id }) else { completion(false); return }
                            toAttach.append(existing)
                        case .create(let index):
                            let sample = samples[index], identifier = identifiers[index]
                            toAttach.append(HKQuantitySample(type: sample.quantityType, quantity: sample.quantity,
                                start: sample.startDate, end: sample.endDate, device: sample.device,
                                metadata: [HKMetadataKeyExternalUUID: identifier,
                                           HKMetadataKeySyncIdentifier: identifier, HKMetadataKeySyncVersion: 1]))
                        }
                    }
                    guard !toAttach.isEmpty else { completion(true); return }
                    guard UserPreferences.synchronizeWorkoutsWithAppleHealth.value else { completion(false); return }
                    healthStore.add(toAttach, to: parent) { success, error in
                        DispatchQueue.main.async { completion(success && error == nil) }
                    }
                }
            }
            healthStore.execute(query)
        }
    }

}
