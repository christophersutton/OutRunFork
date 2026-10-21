import Foundation
import CoreStore

extension DataManager {
    typealias AddStorage = (DataStack, SQLiteStore, @escaping (SetupResult<SQLiteStore>) -> Void) -> Progress?
    typealias MapIntermediate = (ORIntermediateDataModel.Type, DataStack) -> Bool

    /// Uses only the supplied store, allowing failure/retry tests without opening the user's store.
    /// A failed migration may have advanced the on-disk schema; retry starts from that schema.
    static func prepareStorage(
        dataModel: ORDataModel.Type = OutRunV4.self,
        storage: SQLiteStore,
        completedIntermediate: ORDataModel.Type? = nil,
        addStorage: @escaping AddStorage = { $0.addStorage($1, completion: $2) },
        mapIntermediate: @escaping MapIntermediate = completeIntermediateMapping,
        migration: @escaping (Progress) -> Void,
        completion: @escaping (Result<DataStack, SetupError>) -> Void
    ) {
        let currentVersion = storage.currentORModel(from: dataModel.migrationChain)
        let relevant = dataModel.migrationChain.filter { type in
            // A successfully mapped intermediate remains the on-disk version until
            // the NEXT store is opened. Do not reopen it forever during this attempt.
            if let completedIntermediate, type == completedIntermediate { return false }
            return type == dataModel || (currentVersion.map {
                type is ORIntermediateDataModel.Type && (type.isSuccessor(to: $0) || type == $0)
            } ?? false)
        }
        // ORDataModel's contract includes itself in its migration chain.
        let destination = relevant.first ?? dataModel
        let candidate = DataStack(oRMigrationChain: dataModel.migrationChain, oRDataModel: destination)
        let finish = safeClosure(from: completion)

        let progress = addStorage(candidate, storage) { result in
            switch result {
            case .failure(let error):
                candidate.unsafeRemoveAllPersistentStores {
                    finish(.failure(.failedToAddStorage(error: error)))
                }
            case .success:
                if let intermediate = destination as? ORIntermediateDataModel.Type,
                   !mapIntermediate(intermediate, candidate) {
                    candidate.unsafeRemoveAllPersistentStores {
                        finish(.failure(.intermediateMappingActionsFailed(version: intermediate)))
                    }
                    return
                }
                if destination == dataModel {
                    finish(.success(candidate))
                } else {
                    // Close the old coordinator before migrating the same SQLite file again.
                    candidate.unsafeRemoveAllPersistentStores {
                        let nextStorage = SQLiteStore(
                            fileURL: storage.fileURL,
                            migrationMappingProviders: storage.migrationMappingProviders,
                            localStorageOptions: .none
                        )
                        prepareStorage(dataModel: dataModel, storage: nextStorage, completedIntermediate: destination,
                                       addStorage: addStorage, mapIntermediate: mapIntermediate,
                                       migration: migration, completion: finish)
                    }
                }
            }
        }
        if let progress {
            DispatchQueue.main.async { migration(progress) }
        }
    }

    static func completeIntermediateMapping(_ model: ORIntermediateDataModel.Type, _ stack: DataStack) -> Bool {
        if model == OutRunV3to4.self {
            // V3to4 writes dayIdentifier and all converted pauses in ONE commit. Its original
            // action inserts pauses unconditionally, so replay after a later-stage failure would
            // duplicate them. Empty dayIdentifier is the existing schema's unprocessed sentinel.
            // Read that durable result rather than keeping a process-only "completed" flag.
            do {
                let state = try stack.perform(synchronous: { transaction -> (pending: Int, completed: Int) in
                    let eligible = try transaction.fetchAll(From<OutRunV3to4.Workout>())
                        .filter { !$0.workoutEvents.value.isEmpty }
                    return (eligible.filter { $0.dayIdentifier.value.isEmpty }.count,
                            eligible.filter { !$0.dayIdentifier.value.isEmpty }.count)
                })
                if state.pending == 0 { return true }
                // An inconsistent intermediate store needs recovery, not another round of inserts.
                if state.completed > 0 { return false }
            } catch {
                return false
            }
        }
        return model.intermediateMappingActions(stack)
    }
}
