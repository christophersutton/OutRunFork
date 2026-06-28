//
//  WorkoutLiveActivityController.swift
//  MoveFeet
//

import ActivityKit
import Combine
import Foundation

final class WorkoutLiveActivityController {
    private var activity: Activity<WorkoutActivityAttributes>?
    private var cancellables = Set<AnyCancellable>()

    private var status: WorkoutBuilder.Status = .waiting
    private var workoutType: Workout.WorkoutType = Workout.WorkoutType(rawValue: UserPreferences.standardWorkoutType.value)
    private var startDate: Date?
    private var pauses: [TempWorkoutPause] = []
    private var activePauseStart: Date?
    private var distanceText = StatsHelper.string(for: 0, unit: UserPreferences.distanceMeasurementType.safeValue)
    private var paceOrSpeedText = StatsHelper.string(for: 0, unit: UserPreferences.speedMeasurementType.safeValue)
    private var caloriesText = StatsHelper.string(for: 0, unit: UserPreferences.energyMeasurementType.safeValue)
    private let usesPace = UserPreferences.speedMeasurementType.safeValue.isPaceUnit
    private var lastContentState: WorkoutActivityAttributes.ContentState?

    init(builder: WorkoutBuilder, liveStats: LiveStats) {
        bind(builder: builder, liveStats: liveStats)
    }

    private func bind(builder: WorkoutBuilder, liveStats: LiveStats) {
        let output = builder.tranform(WorkoutBuilder.Input())

        output.workoutType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workoutType in
                self?.workoutType = workoutType
            }
            .store(in: &cancellables)

        output.startDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] startDate in
                self?.startDate = startDate
            }
            .store(in: &cancellables)

        output.pauses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pauses in
                self?.pauses = pauses
            }
            .store(in: &cancellables)

        liveStats.distance
            .combineLatest(liveStats.speed, liveStats.burnedEnergy)
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] distance, speed, calories in
                guard let self else { return }
                self.distanceText = distance
                self.paceOrSpeedText = speed
                self.caloriesText = calories
                self.updateActivityIfNeeded()
            }
            .store(in: &cancellables)

        output.status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.apply(status: status)
            }
            .store(in: &cancellables)
    }

    func end() {
        guard let activity else { return }
        let content = ActivityContent(state: lastContentState ?? contentState(status: status), staleDate: nil)
        self.activity = nil
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private func apply(status newStatus: WorkoutBuilder.Status) {
        let oldStatus = status
        status = newStatus

        if newStatus.isPausedStatus, !oldStatus.isPausedStatus {
            activePauseStart = Date()
        } else if newStatus == .recording {
            activePauseStart = nil
        }

        switch newStatus {
        case .recording:
            if activity == nil {
                startActivityIfPossible()
            } else {
                updateActivityIfNeeded(status: newStatus)
            }
        case .paused, .autoPaused:
            updateActivityIfNeeded(status: newStatus)
        case .ready:
            if oldStatus.isActiveStatus {
                activePauseStart = Date()
                updateActivityIfNeeded(status: newStatus)
            }
        case .waiting:
            break
        }
    }

    private func startActivityIfPossible() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }
        guard startDate != nil else { return }

        let attributes = WorkoutActivityAttributes(
            workoutTypeRawValue: workoutType.rawValue,
            usesPace: usesPace
        )
        let state = contentState(status: .recording)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            lastContentState = state
        } catch {
            print("[WorkoutLiveActivityController] failed to start activity: \(error)")
        }
    }

    private func updateActivityIfNeeded(status overrideStatus: WorkoutBuilder.Status? = nil) {
        guard let activity else { return }
        let state = contentState(status: overrideStatus ?? status)
        lastContentState = state
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    private func contentState(status: WorkoutBuilder.Status) -> WorkoutActivityAttributes.ContentState {
        let isPaused = status.isPausedStatus || status == .ready
        let pauseTime = isPaused ? (activePauseStart ?? Date()) : nil

        return WorkoutActivityAttributes.ContentState(
            timerStart: timerStart,
            pauseTime: pauseTime,
            isPaused: isPaused,
            distanceText: distanceText,
            paceOrSpeedText: paceOrSpeedText,
            caloriesText: caloriesText,
            statusTitle: status.title,
            statusKind: status.liveActivityKind
        )
    }

    private var timerStart: Date {
        let start = startDate ?? Date()
        let completedPauseDuration = pauses.map { $0.duration }.reduce(0, +)
        return start.addingTimeInterval(completedPauseDuration)
    }
}

private extension WorkoutBuilder.Status {
    var liveActivityKind: String {
        switch self {
        case .waiting: return "waiting"
        case .ready: return "ready"
        case .recording: return "recording"
        case .paused: return "paused"
        case .autoPaused: return "autoPaused"
        }
    }
}
