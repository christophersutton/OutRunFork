import Foundation

/// Coordinates one local-first save. All calls and dependency completions run on main.
/// Lookup by the checkpoint's stable UUID closes the commit-before-checkpoint-clear crash window.
final class RecordingSaveOperation<Saved> {
    enum Outcome: Equatable { case localFailure, saved, savedHealthFailure, alreadySaved }
    private enum Stage { case idle, saving, exporting, finished }
    private var stage = Stage.idle
    private var attempt = 0
    private let lookup: (UUID) -> Saved?
    private let save: (@escaping (Saved?) -> Void) -> Void
    private let export: (Saved, @escaping (Bool) -> Void) -> Void
    private let didSaveLocally: () -> Void

    init(lookup: @escaping (UUID) -> Saved?,
         save: @escaping (@escaping (Saved?) -> Void) -> Void,
         export: @escaping (Saved, @escaping (Bool) -> Void) -> Void,
         didSaveLocally: @escaping () -> Void) {
        self.lookup = lookup
        self.save = save
        self.export = export
        self.didSaveLocally = didSaveLocally
    }

    @discardableResult
    func begin(id: UUID, healthEnabled: Bool, completion: @escaping (Outcome) -> Void) -> Bool {
        guard stage == .idle else { return false }
        stage = .saving
        attempt += 1
        let currentAttempt = attempt
        if lookup(id) != nil {
            stage = .finished
            didSaveLocally()
            completion(.alreadySaved)
            return true
        }
        save { [self] saved in
            guard stage == .saving, attempt == currentAttempt else { return }
            guard let saved else {
                stage = .idle
                completion(.localFailure)
                return
            }
            // Mark committed before callbacks, so no reentrant tap can insert another local record.
            stage = healthEnabled ? .exporting : .finished
            didSaveLocally()
            guard healthEnabled else { completion(.saved); return }
            export(saved) { [self] success in
                guard stage == .exporting else { return }
                stage = .finished
                completion(success ? .saved : .savedHealthFailure)
            }
        }
        return true
    }
}
