//
//  WorkoutTimelineView.swift
//
//  OutRun
//
//  SwiftUI "Your Workouts" timeline — replaces the UIKit `WorkoutListViewController`. It is driven by the
//  Phase-1 `WorkoutStore` (`@MainActor @Observable`, observing `DataManager.workoutMonitor` and republishing
//  immutable `[WorkoutSnapshot]`), so the view only ever holds value snapshots, never a live CoreStore object.
//
//  A `ScrollView` + `LazyVStack` (rather than `List`) is used so the timeline decoration — a continuous accent
//  line with a ring per card — and the card styling match the legacy look. Sort/filter is applied in memory on
//  the snapshot array (the store stays a pure read model). Day headers are inserted on day-change and only
//  while date-sorted (de-duplicated, unlike the legacy which drew a header above every card). Tapping a row
//  presents the existing `WorkoutDetailView` as a sheet (matching the legacy modal presentation).
//

import SwiftUI

struct WorkoutTimelineView: View {

    @State private var store = WorkoutStore()

    // In-memory sort/filter (not persisted — matches the legacy controller).
    @State private var sortField: TimelineSortField = .date
    @State private var sortDescending = true
    @State private var typeFilter: Workout.WorkoutType?
    @State private var raceOnly = false

    @State private var showSortSheet = false
    @State private var selectedWorkout: WorkoutSnapshot?

    // Distance/duration strings are formatted against `UserPreferences` (not observable). Re-render the rows
    // when the tab reappears with a changed distance unit, mirroring the legacy `willGetSelected` refresh.
    @State private var lastDistanceUnit = UserPreferences.distanceMeasurementType.safeValue
    @State private var unitRefreshToken = 0

    var body: some View {
        NavigationStack {
            content
                .background(Color.orBackground)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Bumping this @State re-renders the rows (recomputing unit strings) without tearing down
                    // their loaded thumbnails.
                    let current = UserPreferences.distanceMeasurementType.safeValue
                    if current != lastDistanceUnit {
                        lastDistanceUnit = current
                        unitRefreshToken += 1
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSortSheet = true } label: {
                            Text(sortField.label + (sortDescending ? " ↓" : " ↑"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                .sheet(isPresented: $showSortSheet) {
                    WorkoutTimelineSortSheet(
                        sortField: $sortField,
                        sortDescending: $sortDescending,
                        typeFilter: $typeFilter,
                        raceOnly: $raceOnly
                    )
                }
                .sheet(item: $selectedWorkout) { snapshot in
                    NavigationStack { WorkoutDetailView(workoutID: snapshot.id) }
                }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if store.isLoaded && displayedSnapshots.isEmpty {
            ContentUnavailableView(LS["NoData.Message"], systemImage: "figure.run")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(LS["WorkoutListViewController.Headline"])
                        .font(Font.system(size: 32, weight: .heavy).lowercaseSmallCaps())
                        .foregroundStyle(Color.orAccent)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    LazyVStack(spacing: 0) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .header(_, let text):
                                TimelineDayHeader(text: text)
                            case .workout(let snapshot):
                                WorkoutTimelineRow(snapshot: snapshot) { selectedWorkout = snapshot }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: Derived data

    /// The filtered + sorted snapshots. The store hands back all snapshots (newest-first); sort/filter is a
    /// pure in-memory transform of that value array.
    private var displayedSnapshots: [WorkoutSnapshot] {
        var list = store.workouts
        if let typeFilter {
            list = list.filter { $0.workoutType == typeFilter }
        }
        if raceOnly {
            list = list.filter(\.isRace)
        }
        switch sortField {
        case .date:
            list.sort { sortDescending ? $0.startDate > $1.startDate : $0.startDate < $1.startDate }
        case .distance:
            list.sort { sortDescending ? $0.distance > $1.distance : $0.distance < $1.distance }
        }
        return list
    }

    /// Interleaves day headers with workout rows. Headers are only emitted while date-sorted (where same-day
    /// workouts are contiguous, giving each day a single header); distance-sorted rows have no day grouping.
    private var timelineItems: [TimelineItem] {
        let showHeaders = (sortField == .date)
        var result: [TimelineItem] = []
        var lastDayIdentifier: String?
        for snapshot in displayedSnapshots {
            if showHeaders, snapshot.dayIdentifier != lastDayIdentifier {
                let text = CustomDateFormatting.dayString(forIdentifier: snapshot.dayIdentifier) ?? ""
                result.append(.header(id: snapshot.dayIdentifier, text: text))
                lastDayIdentifier = snapshot.dayIdentifier
            }
            result.append(.workout(snapshot))
        }
        return result
    }
}

/// A timeline list entry: either a day header or a workout card.
enum TimelineItem: Identifiable {
    case header(id: String, text: String)
    case workout(WorkoutSnapshot)

    var id: String {
        switch self {
        case .header(let id, _): return "header-\(id)"
        case .workout(let snapshot): return "workout-\(snapshot.id.uuidString)"
        }
    }
}
