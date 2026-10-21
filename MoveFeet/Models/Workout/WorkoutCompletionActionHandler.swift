//
//  WorkoutCompletionActionHandler.swift
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
import UIKit

class WorkoutCompletionActionHandler {
    private let snapshotProvider: () -> TempWorkout?
    private var snapshot: TempWorkout?
    private weak var builder: WorkoutBuilder?
    private var didPerformAction = false
    private var saveOperation: RecordingSaveOperation<Workout>?
    var onFinalAction: (() -> Void)?

    init(snapshot: TempWorkout, builder: WorkoutBuilder) {
        self.snapshot = snapshot
        self.snapshotProvider = { snapshot }
        self.builder = builder
    }

    init(snapshotProvider: @escaping () -> TempWorkout?, builder: WorkoutBuilder) {
        self.snapshotProvider = snapshotProvider
        self.builder = builder
    }

    private func resolveSnapshot() -> TempWorkout? {
        if let snapshot { return snapshot }
        snapshot = snapshotProvider()
        return snapshot
    }

    private func showBanner(_ text: String) {
        Task { @MainActor in
            let banner = TextBanner(text: text)
            banner.duration = 5
            banner.show()
        }
    }

    func saveWorkout(completion: @escaping (Bool) -> Void = { _ in }) {
        guard !didPerformAction else { return }
        guard let snapshot = resolveSnapshot(), let id = snapshot.uuid else {
            builder?.saveFailed()
            showBanner(LS["NewWorkoutCompletion.Save.Error"])
            completion(false)
            return
        }
        didPerformAction = true
        let operation = RecordingSaveOperation<Workout>(
            lookup: { DataManager.queryObject(from: $0) as Workout? },
            save: { callback in
                DataManager.saveWorkout(object: snapshot) { success, error, saved in
                    DispatchQueue.main.async { callback(success && error == nil ? saved : nil) }
                }
            },
            export: { saved, callback in
                HealthStoreManager.saveHealthWorkout(for: saved) { error, healthWorkout in
                    DispatchQueue.main.async { callback(error == nil && healthWorkout != nil) }
                }
            },
            didSaveLocally: { [weak self] in self?.builder?.didSaveLocally() }
        )
        saveOperation = operation
        operation.begin(id: id, healthEnabled: UserPreferences.synchronizeWorkoutsWithAppleHealth.value) { [self] outcome in
            guard outcome != .localFailure else {
                didPerformAction = false
                builder?.saveFailed()
                showBanner(LS["NewWorkoutCompletion.Save.Error"])
                completion(false)
                return
            }
            onFinalAction?()
            // Health's adapter may report partial authorization as an error. Do not imply
            // that local save failed or offer another local insert in that case.
            if outcome == .savedHealthFailure {
                showBanner("Workout saved on this iPhone. Apple Health export failed or is incomplete. You can retry Health sync later.")
            } else {
                showBanner(LS["NewWorkoutCompletion.Save.Success"])
            }
            completion(true)
            Task { @MainActor in
                UIApplication.shared.topMostViewController?.dismiss(animated: true)
            }
        }
    }

    @discardableResult
    func continueWorkout() -> Bool {
        guard !didPerformAction, let snapshot = resolveSnapshot(), let builder else { return false }
        didPerformAction = true
        builder.continueWorkout(from: snapshot)
        showBanner(LS["NewWorkoutCompletion.Continue.Success"])
        return true
    }

    @discardableResult
    func discardWorkout() -> Bool {
        guard !didPerformAction, let builder, builder.discardWorkout() else { return false }
        didPerformAction = true
        onFinalAction?()
        return true
    }
}
