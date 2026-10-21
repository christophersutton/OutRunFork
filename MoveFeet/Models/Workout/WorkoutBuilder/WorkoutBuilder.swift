//
//  WorkoutBuilder.swift
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
import Combine
import CombineExt

/// Recording inputs, components and actions are synchronous on the main thread. Sensors
/// hop to main before publishing. Keep this path free of asynchronous Combine delivery:
/// Stop must see every route/distance/step update already delivered to the builder.
public class WorkoutBuilder: ApplicationStateObserver {
    
    // MARK: Public
    
    /// The current status of this `WorkoutBuilder` instance.
    public var status: Status { statusRelay.value }
    
    // MARK: - Internal
    
    /// Indicating the type and last time when a workout was paused by the user or the app.
    private var lastPause: (type: WorkoutPause.WorkoutPauseType, startingAt: Date)?
    /// Holds a reference to the types of workout builder components still preparing to record.
    private var preparingComponents: [WorkoutBuilderComponent.Type] = []
    
    // MARK: - Initialisation
    
    /**
     Initialises a `WorkoutBuilder` instance.
     - parameter workoutType: an optional of the type of workout that is supposed to be recorded; if `nil` the `WorkoutBuilder` sets it appropriately from `UserPreferences.standardWorkoutType`
     - parameter delegate: the delegate that is supposed to receive updates
     */
    typealias CheckpointStore = RecordingCheckpointStore<TempWorkout>
    private let checkpointStore: CheckpointStore
    private let now: () -> Date
    private var sessionID = UUID()
    private var finalized = false
    private var checkpointTimer: AnyCancellable?
    var checkpointError: ((Error) -> Void)?
    var hasRecovery: Bool { checkpointStore.exists && startDateRelay.value == nil }
    var selectedWorkoutType: Workout.WorkoutType { workoutTypeRelay.value }

    static var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recording/current-session.json")
    }

    public convenience init(workoutType: Workout.WorkoutType? = nil) {
        self.init(workoutType: workoutType, checkpointStore: CheckpointStore(url: Self.recoveryURL))
    }

    init(workoutType: Workout.WorkoutType? = nil, checkpointStore: CheckpointStore, now: @escaping () -> Date = Date.init) {
        self.checkpointStore = checkpointStore
        self.now = now
        
        let workoutType = workoutType ?? Workout.WorkoutType(rawValue: UserPreferences.standardWorkoutType.value)
        self.workoutTypeRelay = CurrentValueRelay(workoutType)
        
        self.prepareBindings()
        self.startObservingApplicationState()
        checkpointTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.checkpoint() }
    }

    deinit {
        self.stopObservingApplicationState()
    }
    
    // MARK: - Bindings
    
    private func prepareBindings() {
        
        // reacting to status changes
        statusRelay.sink(receiveValue: { [weak self] newStatus in
            guard let self, !self.restoring else { return }
            let timestamp = self.now()
            
            switch newStatus {
            case .recording: // starting / resuming workout
                if self.startDateRelay.value == nil {
                    self.finalized = false
                    self.sessionID = UUID()
                    self.startDateRelay.accept(timestamp)
                    
                } else if let lastPause = self.lastPause {
                    self.lastPause = nil
                    let pause = TempWorkoutPause(uuid: nil, startDate: lastPause.startingAt, endDate: timestamp, pauseType: lastPause.type)
                    let pauses = self.pausesRelay.value + [pause]
                    self.pausesRelay.accept(pauses)
                }
                self.openPauseStartRelay.accept(nil)
            
            case .paused, .autoPaused: // (auto) pausing workout
                let pauseType = newStatus == .paused ? WorkoutPause.WorkoutPauseType.manual : .automatic
                self.lastPause = (type: pauseType, startingAt: self.lastPause?.startingAt ?? timestamp)
                self.openPauseStartRelay.accept(self.lastPause?.startingAt)
                
            case .reviewing: // stopping workout for save/discard/continue review
                guard self.startDateRelay.value != nil else { return }
                
                if let lastPause = self.lastPause {
                    let pause = TempWorkoutPause(uuid: nil, startDate: lastPause.startingAt, endDate: timestamp, pauseType: lastPause.type)
                    let pauses = self.pausesRelay.value + [pause]
                    self.pausesRelay.accept(pauses)
                    self.lastPause = nil
                }
                
                self.endDateRelay.accept(timestamp)
                self.openPauseStartRelay.accept(nil)
                
                self.checkpoint(phase: .reviewing)
                if let snapshotProvider = self.createSnapshotProvider() {
                    let actionHandler = WorkoutCompletionActionHandler(snapshotProvider: snapshotProvider, builder: self)
                    self.completionActionHandlerRelay.accept(actionHandler)
                }

            default: // ignore everything else
                break
            }
            self.checkpoint()
        }).store(in: &cancellables)
        
    }
    
    // MARK: - Dataflow
    
    /// An Array of cancellables for subscription links to components and custom permanent subscriptions.
    private var cancellables: [AnyCancellable] = []
    
    /// The relay to publish the current status of the `WorkoutBuilder`.
    private let statusRelay = CurrentValueRelay<WorkoutBuilder.Status>(.waiting)
    /// The relay to publish the type of workout the `WorkoutBuilder` is supposed to record.
    private let workoutTypeRelay: CurrentValueRelay<Workout.WorkoutType>
    /// The relay to publish the date the recorded workout was started.
    private let startDateRelay = CurrentValueRelay<Date?>(nil)
    /// Freezes live duration while a pause is still open.
    private let openPauseStartRelay = CurrentValueRelay<Date?>(nil)
    /// The final end date, set only when entering review.
    private let endDateRelay = CurrentValueRelay<Date?>(nil)
    /// The relay to publish the distance shared by components.
    private let distanceRelay = CurrentValueRelay<Double>(0)
    /// The relay to publish the steps counted by components.
    private let stepsRelay = CurrentValueRelay<Int?>(nil)
    /// The relay to publish the pauses initiated by the user or by the app automaticallyprivate
    private let pausesRelay = CurrentValueRelay<[TempWorkoutPause]>([])
    /// The relay to publish the current location regardless of whether it was recorded or not.
    private let currentLocationRelay = CurrentValueRelay<TempWorkoutRouteDataSample?>(nil)
    /// The relay to publish the recorded locations received from components.
    private let locationsRelay = CurrentValueRelay<[TempWorkoutRouteDataSample]>([])
    /// The relay to publish the altitudes received from components.
    private let altitudesRelay = CurrentValueRelay<[AltitudeManagement.AltitudeSample]>([])
    /// The relay to publish the heart rate samples received from components.
    private let heartRatesRelay = CurrentValueRelay<[TempWorkoutHeartRateDataSample]>([])
    /// The relay to publish a components report of isufficient permissions to record the workout.
    private let insufficientPermissionRelay = PassthroughRelay<String>()
    /// The relay to publish a UI suspension command.
    private let uiSuspensionRelay = CurrentValueRelay<Bool>(false)
    /// The relay to publish a suspension command.
    private let suspensionRelay = CurrentValueRelay<Bool>(false)
    /// The relay to publish a reset command.
    private let resetRelay = PassthroughRelay<ORWorkoutInterface?>()
    /// The relay to publish a completed workout action handler.
    private let completionActionHandlerRelay = PassthroughRelay<WorkoutCompletionActionHandler>()
    
    /// A type containing all input data needed to establish a data flow.
    public struct Input {
        let readiness: AnyPublisher<WorkoutBuilderComponentStatus, Never>?
        let insufficientPermission: AnyPublisher<String, Never>?
        let workoutType: AnyPublisher<Workout.WorkoutType, Never>?
        let statusSuggestion: AnyPublisher<WorkoutBuilder.Status, Never>?
        let distance: AnyPublisher<Double, Never>?
        let steps: AnyPublisher<Int?, Never>?
        let currentLocation: AnyPublisher<TempWorkoutRouteDataSample?, Never>?
        let locations: AnyPublisher<[TempWorkoutRouteDataSample], Never>?
        let altitudes: AnyPublisher<[AltitudeManagement.AltitudeSample], Never>?
        let heartRates: AnyPublisher<[TempWorkoutHeartRateDataSample], Never>?

        public init(
            readiness: AnyPublisher<WorkoutBuilderComponentStatus, Never>? = nil,
            insufficientPermission: AnyPublisher<String, Never>? = nil,
            workoutType: AnyPublisher<Workout.WorkoutType, Never>? = nil,
            statusSuggestion: AnyPublisher<WorkoutBuilder.Status, Never>? = nil,
            distance: AnyPublisher<Double, Never>? = nil,
            steps: AnyPublisher<Int?, Never>? = nil,
            currentLocation: AnyPublisher<TempWorkoutRouteDataSample?, Never>? = nil,
            locations: AnyPublisher<[TempWorkoutRouteDataSample], Never>? = nil,
            altitudes: AnyPublisher<[AltitudeManagement.AltitudeSample], Never>? = nil,
            heartRates: AnyPublisher<[TempWorkoutHeartRateDataSample], Never>? = nil
        ) {
            self.readiness = readiness
            self.insufficientPermission = insufficientPermission
            self.workoutType = workoutType
            self.statusSuggestion = statusSuggestion
            self.distance = distance
            self.steps = steps
            self.currentLocation = currentLocation
            self.locations = locations
            self.altitudes = altitudes
            self.heartRates = heartRates
        }
    }
    
    /// A type containing all output data needed to establish a data flow.
    public struct Output {
        let status: AnyPublisher<WorkoutBuilder.Status, Never>
        let workoutType: AnyPublisher<Workout.WorkoutType, Never>
        let startDate: AnyPublisher<Date?, Never>
        let endDate: AnyPublisher<Date?, Never>
        let durationEndDate: AnyPublisher<Date?, Never>
        let distance: AnyPublisher<Double, Never>
        let steps: AnyPublisher<Int?, Never>
        let pauses: AnyPublisher<[TempWorkoutPause], Never>
        let currentLocation: AnyPublisher<TempWorkoutRouteDataSample?, Never>
        let locations: AnyPublisher<[TempWorkoutRouteDataSample], Never>
        let altitudes: AnyPublisher<[AltitudeManagement.AltitudeSample], Never>
        let heartRates: AnyPublisher<[TempWorkoutHeartRateDataSample], Never>
        let insufficientPermission: AnyPublisher<String, Never>
        let isUISuspended: AnyPublisher<Bool, Never>
        let isSuspended: AnyPublisher<Bool, Never>
        let onReset: AnyPublisher<ORWorkoutInterface?, Never>
        let completionActionHandler: AnyPublisher<WorkoutCompletionActionHandler, Never>
    }
    
    /**
     Tranforms the provided inputs to an output establishing a data flow between this WorkoutBuilder and the caller of this function.
     - parameter input: the input provided to the workout builder
     - returns: the output to provide the caller with the necessary data
     */
    public func tranform(_ input: WorkoutBuilder.Input) -> Output {
        
        input.workoutType?.sink { [weak self] type in
            guard let self, self.startDateRelay.value == nil, !self.hasRecovery else { return }
            self.workoutTypeRelay.accept(type)
        }.store(in: &cancellables)
        input.readiness?.sink(receiveValue: readinessBinder).store(in: &cancellables)
        input.statusSuggestion?.sink(receiveValue: statusSuggestionBinder).store(in: &cancellables)
        input.insufficientPermission?.sink(receiveValue: insufficientPermissionRelay.accept).store(in: &cancellables)
        input.distance?.sink { [weak self] value in
            guard let self, !self.status.isReviewingStatus else { return }
            self.distanceRelay.accept(value)
        }.store(in: &cancellables)
        input.steps?.sink { [weak self] value in
            guard let self, !self.status.isReviewingStatus else { return }
            self.stepsRelay.accept(value)
            self.checkpoint()
        }.store(in: &cancellables)
        input.currentLocation?.sink { [weak self] value in
            guard let self else { return }
            self.currentLocationRelay.accept(value)
            self.checkpoint()
        }.store(in: &cancellables)
        input.locations?.sink { [weak self] value in
            guard let self, !self.status.isReviewingStatus else { return }
            self.locationsRelay.accept(value)
        }.store(in: &cancellables)
        input.altitudes?.sink(receiveValue: altitudesRelay.accept).store(in: &cancellables)
        input.heartRates?.sink { [weak self] value in
            guard let self, !self.status.isReviewingStatus else { return }
            self.heartRatesRelay.accept(value)
            self.checkpoint()
        }.store(in: &cancellables)
        
        return Output(
            status: statusRelay.eraseToAnyPublisher(),
            workoutType: workoutTypeRelay.eraseToAnyPublisher(),
            startDate: startDateRelay.eraseToAnyPublisher(),
            endDate: endDateRelay.eraseToAnyPublisher(),
            durationEndDate: endDateRelay.combineLatest(openPauseStartRelay).map { $0 ?? $1 }.eraseToAnyPublisher(),
            distance: distanceRelay.eraseToAnyPublisher(),
            steps: stepsRelay.eraseToAnyPublisher(),
            pauses: pausesRelay.eraseToAnyPublisher(),
            currentLocation: currentLocationRelay.eraseToAnyPublisher(),
            locations: locationsRelay.eraseToAnyPublisher(),
            altitudes: altitudesRelay.eraseToAnyPublisher(),
            heartRates: heartRatesRelay.eraseToAnyPublisher(),
            insufficientPermission: insufficientPermissionRelay.eraseToAnyPublisher(),
            isUISuspended: uiSuspensionRelay.eraseToAnyPublisher(),
            isSuspended: suspensionRelay.eraseToAnyPublisher(),
            onReset: resetRelay.eraseToAnyPublisher(),
            completionActionHandler: completionActionHandlerRelay.eraseToAnyPublisher()
        )
    }
    
    /// A closure to update the readiness status of components.
    private var readinessBinder: (WorkoutBuilderComponentStatus) -> Void {
        return { [weak self] status in
            guard let self else { return }
            switch status {
            case .preparing(let preparingType):
                guard !self.preparingComponents.contains(where: { $0 == preparingType }) else { return }
                self.preparingComponents.append(preparingType)
            case .ready(let preparingType):
                self.preparingComponents.removeAll(where: { $0 == preparingType })
            }
            let newStatus = self.readinessStatus
            self.validateTransition(to: newStatus) { isValid in
                guard isValid else { return }
                self.statusRelay.accept(newStatus)
            }
        }
    }
    
    /// A closure to enable components to suggest a new status.
    private var statusSuggestionBinder: (WorkoutBuilder.Status) -> Void {
        return { [weak self] status in
            guard let self else { return }
            self.validateTransition(to: status) { (isValid) in
                guard isValid else { return }
                self.statusRelay.accept(status)
            }
        }
    }
    
    /// Shared by the Pause/Play control and behavioral tests.
    func togglePause() {
        statusSuggestionBinder(status.isPausedStatus ? .recording : .paused)
    }

    // MARK: - Create Snapshot

    private struct SnapshotValues {
        let sessionID: UUID
        let heartRates: [TempWorkoutHeartRateDataSample]
        let workoutType: Workout.WorkoutType
        let distance: Double
        let steps: Int?
        let startDate: Date
        let endDate: Date
        let routeData: [TempWorkoutRouteDataSample]
        let pauses: [TempWorkoutPause]

        func makeSnapshot() -> TempWorkout {
            let snapshot = NewWorkout(
                workoutType: workoutType,
                distance: distance,
                steps: steps,
                startDate: startDate,
                endDate: endDate,
                isRace: false,
                comment: nil,
                isUserModified: false,
                finishedRecording: true,
                heartRates: heartRates,
                routeData: routeData,
                pauses: pauses,
                workoutEvents: []
            )
            snapshot.uuid = sessionID
            return snapshot
        }
    }
    
    /**
     Captures the values needed to create a final snapshot later.
     - returns: a provider that constructs the recorded workout; will be `nil` when start or end cannot be determined
     */
    func createSnapshotProvider() -> (() -> TempWorkout?)? {
        
        guard let start = startDateRelay.value, let end = endDateRelay.value else { return nil }

        let values = SnapshotValues(
            sessionID: sessionID,
            heartRates: heartRatesRelay.value,
            workoutType: workoutTypeRelay.value,
            distance: distanceRelay.value,
            steps: stepsRelay.value,
            startDate: start,
            endDate: end,
            routeData: locationsRelay.value,
            pauses: pausesRelay.value
        )

        return {
            values.makeSnapshot()
        }
    }

    private var readinessStatus: Status {
        preparingComponents.isEmpty ? .ready : .waiting
    }
    
    // MARK: - Preparation
    
    /// Resets the `WorkoutBuilder` and it's components and prepares them for another recording.
    private func reset() {
        
        startDateRelay.accept(nil)
        distanceRelay.accept(0)
        stepsRelay.accept(nil)
        locationsRelay.accept([])
        heartRatesRelay.accept([])
        endDateRelay.accept(nil)
        lastPause = nil
        openPauseStartRelay.accept(nil)
        pausesRelay.accept([])
        resetRelay.accept(nil)
        statusRelay.accept(readinessStatus)
    }

    @discardableResult
    public func discardWorkout() -> Bool {
        do {
            try checkpointStore.discard()
            reset()
            return true
        } catch {
            checkpointError?(error)
            return false
        }
    }

    /// Called only after the local record is known to exist, never after a Health failure.
    func didSaveLocally() {
        finalized = true
        do { try checkpointStore.clear(sessionID: sessionID) }
        catch { checkpointError?(error) }
    }

    func saveFailed() { checkpoint(phase: .failedSave) }

    /// Recovery always opens in review at the durable end time. Continue adds the entire
    /// interruption as a pause; neither launch nor a failed save starts an elapsed-time clock.
    @discardableResult
    func recoverWorkout(isLocallySaved: (UUID) -> Bool) throws -> Bool {
        guard let checkpoint = try checkpointStore.load() else { return false }
        // A crash after commit must not offer Continue on a record already saved locally.
        if isLocallySaved(checkpoint.sessionID) {
            try checkpointStore.clear(sessionID: checkpoint.sessionID)
            return false
        }
        sessionID = checkpoint.sessionID
        let snapshot = checkpoint.snapshot
        guard snapshot.uuid == sessionID else { throw CocoaError(.coderReadCorrupt) }
        workoutTypeRelay.accept(snapshot.workoutType)
        startDateRelay.accept(snapshot.startDate)
        endDateRelay.accept(snapshot.endDate)
        pausesRelay.accept(snapshot.pauses.map { .init(from: $0) })
        distanceRelay.accept(snapshot.distance)
        stepsRelay.accept(snapshot.steps)
        locationsRelay.accept(snapshot.routeData.map { .init(from: $0) })
        heartRatesRelay.accept(snapshot.heartRates.map { .init(from: $0) })
        lastPause = nil
        // Do not re-run the reviewing transition, which would replace the durable end date.
        restoring = true
        statusRelay.accept(.reviewing)
        restoring = false
        completionActionHandlerRelay.accept(WorkoutCompletionActionHandler(snapshot: snapshot, builder: self))
        return true
    }

    private var restoring = false

    func checkpoint(phase: CheckpointStore.Phase? = nil) {
        guard !finalized, !restoring, (!status.isReviewingStatus || phase != nil), let start = startDateRelay.value else { return }
        let timestamp = endDateRelay.value ?? now()
        var pauses = pausesRelay.value
        if let pause = lastPause {
            pauses.append(TempWorkoutPause(uuid: nil, startDate: pause.startingAt, endDate: timestamp, pauseType: pause.type))
        }
        let snapshot = SnapshotValues(sessionID: sessionID, heartRates: heartRatesRelay.value,
            workoutType: workoutTypeRelay.value, distance: distanceRelay.value, steps: stepsRelay.value,
            startDate: start, endDate: timestamp, routeData: locationsRelay.value, pauses: pauses).makeSnapshot()
        let phase = phase ?? (status.isReviewingStatus ? .reviewing : status.isPausedStatus ? .paused : .recording)
        do { try checkpointStore.save(.init(sessionID: sessionID, phase: phase, capturedAt: timestamp, snapshot: snapshot)) }
        catch { checkpointError?(error) }
    }
    
    /**
     Continues a workout by setting up the `WorkoutBuilder` and it's components like they are recording.
     - parameter snapshot: the snapshot made of the continued workout
     */
    public func continueWorkout(from snapshot: TempWorkout) {
        
        workoutTypeRelay.accept(snapshot.workoutType)
        distanceRelay.accept(snapshot.distance)
        stepsRelay.accept(snapshot.steps)
        locationsRelay.accept(snapshot.routeData.map { .init(from: $0) })
        heartRatesRelay.accept(snapshot.heartRates.map { .init(from: $0) })
        startDateRelay.accept(snapshot.startDate)
        endDateRelay.accept(nil)
        pausesRelay.accept(snapshot.pauses.map { TempWorkoutPause(uuid: $0.uuid, startDate: $0.startDate, endDate: $0.endDate, pauseType: $0.pauseType) })
        lastPause = (type: .manual, startingAt: snapshot.endDate)
        resetRelay.accept(snapshot)
        self.validateTransition(to: .recording) { isValid in
            guard isValid else { return }
            self.statusRelay.accept(.recording)
        }
    }
    
    // MARK: - Validation
    
    /**
     Validates the transition to a new status
     - parameter newStatus: the new status the `WorkoutBuilder` is supposed to take on
     - parameter closure: the closure being performed with a boolean indicating if the transition is valid as an argument; the closure will not be called if the status is equal to the current one
     */
    private func validateTransition(to newStatus: WorkoutBuilder.Status, closure: (Bool) -> Void) {
        let oldStatus = self.statusRelay.value
        guard oldStatus != newStatus else { return }
        
        var isValid = false
        
        switch newStatus {
        case .recording: isValid = !hasRecovery && [.ready, .paused, .autoPaused, .reviewing].contains(oldStatus)
        case .paused: isValid = [.recording, .autoPaused].contains(oldStatus)
        case .waiting: isValid = oldStatus == .ready
        case .ready: isValid = oldStatus == .waiting
        case .autoPaused: isValid = oldStatus == .recording
        case .reviewing: isValid = oldStatus.isActiveStatus
        }
        
        closure(isValid)
    }
    
    // MARK: - ApplicationStateObserver
    
    /// Implementation of the `ApplicationStateObserver` protocol sending a suspension command to all subscribers when not recording to save battery life.
    func didUpdateApplicationState(to state: ApplicationState) {
        checkpoint()
        self.uiSuspensionRelay.accept(state == .background)
        guard !self.statusRelay.value.isActiveStatus else { return }
        self.suspensionRelay.accept(state == .background)
    }
    
}
