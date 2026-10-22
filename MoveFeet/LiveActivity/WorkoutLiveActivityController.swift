//
//  WorkoutLiveActivityController.swift
//  MoveFeet
//

import ActivityKit
import Combine
import Foundation

final class WorkoutLiveActivityController {
    private static let staleInterval: TimeInterval = 90

    private var activity: Activity<WorkoutActivityAttributes>?
    private var cancellables = Set<AnyCancellable>()

    private var status: WorkoutBuilder.Status = .waiting
    private var startDate: Date?
    private var pauses: [TempWorkoutPause] = []
    private var activePauseStart: Date?
    private var distanceText = CustomMeasurementFormatting.string(
        forMeasurement: NSMeasurement(doubleValue: 0, unit: UnitLength.standardUnit),
        type: .distance,
        rounding: .oneDigit
    )
    private var lastContentState: WorkoutActivityAttributes.ContentState?

    init(builder: WorkoutBuilder, liveStats: LiveStats) {
        bind(builder: builder, liveStats: liveStats)
    }

    private func bind(builder: WorkoutBuilder, liveStats: LiveStats) {
        let output = builder.tranform(WorkoutBuilder.Input())

        output.startDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] startDate in
                guard let self else { return }
                self.startDate = startDate
                if startDate != nil, self.status == .recording, self.activity == nil {
                    self.startActivityIfPossible(reason: "startDate")
                }
            }
            .store(in: &cancellables)

        output.pauses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pauses in
                self?.pauses = pauses
            }
            .store(in: &cancellables)

        output.distance
            .map(Self.distanceString)
            .removeDuplicates()
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] distance in
                guard let self else { return }
                self.distanceText = distance
                self.updateActivityIfNeeded()
            }
            .store(in: &cancellables)

        liveStats.duration
            .throttle(for: .seconds(30), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self, self.status == .recording else { return }
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
        let content = activityContent(state: lastContentState ?? contentState(status: status), status: status)
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
                startActivityIfPossible(reason: "status")
            } else {
                updateActivityIfNeeded(status: newStatus)
            }
        case .paused, .autoPaused:
            updateActivityIfNeeded(status: newStatus)
        case .reviewing:
            if oldStatus.isActiveStatus {
                activePauseStart = Date()
                updateActivityIfNeeded(status: newStatus)
            }
        case .ready, .waiting:
            break
        }
    }

    private func startActivityIfPossible(reason: String) {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("[WorkoutLiveActivityController] not starting activity (\(reason)): Live Activities are disabled")
            return
        }
        guard activity == nil else {
            print("[WorkoutLiveActivityController] not starting activity (\(reason)): activity already exists")
            return
        }
        guard startDate != nil else {
            print("[WorkoutLiveActivityController] not starting activity (\(reason)): missing start date")
            return
        }

        let attributes = WorkoutActivityAttributes(accentHex: MoveTheme.accent.fillHex)
        let state = contentState(status: .recording)
        let content = activityContent(state: state, status: .recording)

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            lastContentState = state
            print("[WorkoutLiveActivityController] started activity (\(reason))")
        } catch {
            print("[WorkoutLiveActivityController] failed to start activity (\(reason)): \(error)")
        }
    }

    private func updateActivityIfNeeded(status overrideStatus: WorkoutBuilder.Status? = nil) {
        guard let activity else { return }
        let resolvedStatus = overrideStatus ?? status
        let state = contentState(status: resolvedStatus)
        lastContentState = state
        let content = activityContent(state: state, status: resolvedStatus)
        Task {
            await activity.update(content)
        }
    }

    private func contentState(status: WorkoutBuilder.Status) -> WorkoutActivityAttributes.ContentState {
        let isPaused = status.isPausedStatus || status.isReviewingStatus
        let pauseTime = isPaused ? (activePauseStart ?? Date()) : nil

        return WorkoutActivityAttributes.ContentState(
            timerStart: timerStart,
            pauseTime: pauseTime,
            isPaused: isPaused,
            distanceText: distanceText
        )
    }

    private func activityContent(
        state: WorkoutActivityAttributes.ContentState,
        status: WorkoutBuilder.Status
    ) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        let staleDate = status == .recording ? Date().addingTimeInterval(Self.staleInterval) : nil
        return ActivityContent(state: state, staleDate: staleDate)
    }

    private var timerStart: Date {
        let start = startDate ?? Date()
        let completedPauseDuration = pauses.map { $0.duration }.reduce(0, +)
        return start.addingTimeInterval(completedPauseDuration)
    }

    private static func distanceString(for distance: Double) -> String {
        CustomMeasurementFormatting.string(
            forMeasurement: NSMeasurement(doubleValue: distance, unit: UnitLength.standardUnit),
            type: .distance,
            rounding: .oneDigit
        )
    }
}
