//
//  WorkoutStore.swift
//
//  OutRun
//
//  The @Observable, main-actor store that the SwiftUI layer reads from. It observes the CoreStore
//  `ListMonitor` and republishes an array of value-type `WorkoutSnapshot`s — so SwiftUI views never
//  touch thread-confined CoreStore objects directly. Snapshots are rebuilt on the main queue (where the
//  monitor's objects are bound), keeping all CoreStore access on the correct queue.
//

import Foundation
import Observation
import CoreStore

@MainActor
@Observable
final class WorkoutStore {

    /// Shared timeline store kept alive across tab switches so reselecting Timeline does not synchronously
    /// rebuild every workout snapshot on the main actor.
    static let shared = WorkoutStore()

    /// The current list of workouts as immutable value snapshots, newest first (mirrors the monitor's sort).
    private(set) var workouts: [WorkoutSnapshot] = []

    /// `true` once the backing monitor has loaded at least once.
    private(set) var isLoaded: Bool = false

    @ObservationIgnored private let monitor: ListMonitor<Workout>
    @ObservationIgnored private var observer: WorkoutMonitorObserver?

    init(monitor: ListMonitor<Workout> = DataManager.workoutMonitor) {
        self.monitor = monitor
        let observer = WorkoutMonitorObserver { [weak self] in
            // ListObserver callbacks already arrive on the main queue.
            MainActor.assumeIsolated { self?.rebuild() }
        }
        self.observer = observer
        monitor.addObserver(observer)
        rebuild()
    }

    /// Rebuilds the snapshot array from the monitor's current objects. Main-queue only.
    private func rebuild() {
        let objects = monitor.objectsInAllSections()
        var snapshots = [WorkoutSnapshot]()
        snapshots.reserveCapacity(objects.count)
        for object in objects {
            snapshots.append(WorkoutSnapshot(object))
        }
        workouts = snapshots
        isLoaded = true
    }
}

/// Bridges CoreStore's `ListObserver` callbacks into a single rebuild closure.
/// (All `ListObserver` methods have default implementations, so only change/refetch are overridden.)
private final class WorkoutMonitorObserver: ListObserver {

    typealias ListEntityType = Workout

    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func listMonitorDidChange(_ monitor: ListMonitor<Workout>) { onChange() }
    func listMonitorDidRefetch(_ monitor: ListMonitor<Workout>) { onChange() }
}
