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

    private typealias SnapshotProvider = () -> TempWorkout?

    private final class SnapshotResolver: @unchecked Sendable {
        private let snapshotProvider: SnapshotProvider
        private let lock = NSLock()
        private var snapshot: TempWorkout?

        init(snapshot: TempWorkout) {
            self.snapshotProvider = { Optional(snapshot) }
            self.snapshot = snapshot
        }

        init(snapshotProvider: @escaping SnapshotProvider) {
            self.snapshotProvider = snapshotProvider
        }

        func resolveSnapshot() -> TempWorkout? {
            lock.lock()
            defer { lock.unlock() }

            if let snapshot = snapshot {
                return snapshot
            }

            guard let snapshot = snapshotProvider() else {
                return nil
            }

            self.snapshot = snapshot
            return snapshot
        }
    }

    private final class BuilderReference: @unchecked Sendable {
        private weak var builder: WorkoutBuilder?

        init(builder: WorkoutBuilder) {
            self.builder = builder
        }

        @MainActor
        func continueWorkout(from snapshot: TempWorkout) -> Bool {
            guard let builder else {
                return false
            }

            builder.continueWorkout(from: snapshot)
            return true
        }

        @MainActor
        func discardWorkout() {
            builder?.discardWorkout()
        }
    }
    
    /// Builds the `TempWorkout` only for actions that actually need it.
    private let snapshotResolver: SnapshotResolver
    private let snapshotQueue = DispatchQueue(label: "outrun.workout.completion.snapshot", qos: .userInitiated)
    
    /// A weak reference to a `WorkoutBuilder` to continue the workout
    private let builderReference: BuilderReference
    
    /// If `true` the `WorkoutCompletionActionHandler` did already perform an action, so no additional action should be taken
    private var didPerformAction: Bool = false
    var onFinalAction: (() -> Void)?
    
    /**
     Initialises the `WorkoutCompletionActionHandler` with the needed snapshot of an `TempWorkout`
     - parameter snapshot: a `TempWorkout` object to be saved, discarded or continued
     */
    public init(snapshot: TempWorkout, builder: WorkoutBuilder) {
        
        self.snapshotResolver = SnapshotResolver(snapshot: snapshot)
        self.builderReference = BuilderReference(builder: builder)
        
    }

    public init(snapshotProvider: @escaping () -> TempWorkout?, builder: WorkoutBuilder) {

        self.snapshotResolver = SnapshotResolver(snapshotProvider: snapshotProvider)
        self.builderReference = BuilderReference(builder: builder)

    }

    private static func showBanner(messageKey: String) {

        Task { @MainActor in
            let banner = TextBanner(text: LS[messageKey])
            banner.duration = 5
            banner.show()
        }

    }
    
    /**
     Saves the workout if no other action was already performed
     */
    public func saveWorkout(completion: @escaping (Bool) -> Void = { _ in }) {
        
        guard !self.didPerformAction else {
            return
        }
        
        self.didPerformAction = true
        onFinalAction?()

        let snapshotResolver = self.snapshotResolver
        snapshotQueue.async {

            guard let snapshot = snapshotResolver.resolveSnapshot() else {
                Self.showBanner(messageKey: "NewWorkoutCompletion.Save.Error")
                Task { @MainActor in
                    self.didPerformAction = false
                    completion(false)
                }
                return
            }

            DataManager.saveWorkout(object: snapshot) { (success, error, workout) in

                Task { @MainActor in
                    if !success {
                        self.didPerformAction = false
                    }

                    let banner = TextBanner(text: LS["NewWorkoutCompletion.Save." + (success ? "Success" : "Error")])
                    banner.duration = 5
                    banner.show()

                    completion(success)

                    guard success else { return }
                    UIApplication.shared.topMostViewController?.dismiss(animated: true)
                }

            }
            
        }
        
    }
    
    /**
     Continues the workout if no other action was already performed and the builder is still active
     */
    @MainActor
    public func continueWorkout() {
        
        guard !self.didPerformAction else {
            return
        }
        
        self.didPerformAction = true

        let snapshotResolver = self.snapshotResolver
        let builderReference = self.builderReference
        snapshotQueue.async {

            guard let snapshot = snapshotResolver.resolveSnapshot() else {
                Self.showBanner(messageKey: "NewWorkoutCompletion.Continue.Error")
                return
            }

            Task { @MainActor in
                var messageKey = ""

                if builderReference.continueWorkout(from: snapshot) {

                    messageKey = "NewWorkoutCompletion.Continue.Success"

                } else {

                    messageKey = "NewWorkoutCompletion.Continue.Error"

                }

                let banner = TextBanner(text: LS[messageKey])
                banner.duration = 5
                banner.show()
            }

        }
        
    }
    
    /**
     Discards the workout if no other action was already performed
     */
    public func discardWorkout() {
        
        guard !self.didPerformAction else {
            return
        }
        
        self.didPerformAction = true
        onFinalAction?()
        let builderReference = self.builderReference
        Task { @MainActor in
            builderReference.discardWorkout()
        }
        
    }
    
}
