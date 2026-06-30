//
//  StatsSummary.swift
//
//  OutRun
//
//  A pure, value-type aggregation of the workout history for the Stats dashboard. It is computed entirely
//  from the `[WorkoutSnapshot]` value array published by `WorkoutStore` — no CoreStore access — so it is
//  cheap to rebuild on the main actor and easy to reason about. All distances stay in metres and durations
//  in seconds here; unit conversion/formatting happens at the view layer (or via `WorkoutStatFormat`), so
//  the model itself is unit-agnostic.
//
//  The summary scopes "totals", the trend buckets and the type mix to a selected `StatsPeriod` window
//  (this week / month / year / all time), while "records" are always all-time bests.
//

import Foundation

// MARK: - Period & metric

/// The time window the dashboard's totals, trend and type-mix are scoped to.
enum StatsPeriod: CaseIterable, Identifiable, Hashable {
    case week, month, year, all

    var id: Self { self }

    /// Short label for the segmented period picker.
    var pickerTitle: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all:  return "All"
        }
    }

    /// Sentence-style caption describing the window (used as the totals section header).
    var windowCaption: String {
        switch self {
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "This Year"
        case .all:  return "All Time"
        }
    }

    /// Lower-cased form for inline empty-state copy ("No workouts this week").
    var inlineCaption: String {
        switch self {
        case .week: return "this week"
        case .month: return "this month"
        case .year: return "this year"
        case .all:  return "yet"
        }
    }
}

/// The metric plotted by the trend chart.
enum StatsMetric: CaseIterable, Identifiable, Hashable {
    case distance, time

    var id: Self { self }

    var title: String {
        switch self {
        case .distance: return "Distance"
        case .time:     return "Active Time"
        }
    }
}

// MARK: - Component types

/// One column of the trend bar chart. Values are raw (metres / seconds); the view converts to user units.
struct StatsBucket: Identifiable, Hashable {
    let id: String
    let label: String           // x-axis label, e.g. "M", "Wk 2", "Jun", "2026"
    let distanceMeters: Double
    let duration: TimeInterval
    let count: Int
}

/// A per-workout-type row in the "type mix" breakdown (scoped to the period window).
struct StatsTypeBreakdown: Identifiable, Hashable {
    let type: Workout.WorkoutType
    let count: Int
    let distanceMeters: Double
    let duration: TimeInterval

    var id: Workout.WorkoutType { type }
}

/// A single all-time record, referencing the workout that holds it.
struct StatsRecord: Identifiable, Hashable {
    let kind: Kind
    let workoutID: UUID
    let valueText: String
    let dateText: String

    var id: Kind { kind }

    enum Kind: Hashable {
        case longestDistance, longestDuration, biggestClimb, bestPace

        var title: String {
            switch self {
            case .longestDistance: return "Longest Distance"
            case .longestDuration: return "Longest Time"
            case .biggestClimb:    return "Biggest Climb"
            case .bestPace:        return "Fastest Average"
            }
        }

        var sfSymbol: String {
            switch self {
            case .longestDistance: return "ruler"
            case .longestDuration: return "clock"
            case .biggestClimb:    return "mountain.2"
            case .bestPace:        return "bolt"
            }
        }
    }
}

// MARK: - Summary

/// The fully-derived dashboard model for one `(snapshots, period)` pairing.
struct StatsSummary {

    let period: StatsPeriod

    // Totals (period-windowed, raw units)
    let workoutCount: Int
    let totalDistanceMeters: Double
    let totalDuration: TimeInterval
    let totalEnergy: Double?            // kcal; nil when no workout in the window recorded energy

    // Trend (period-windowed)
    let buckets: [StatsBucket]

    // Type mix (period-windowed), sorted by distance descending
    let typeBreakdown: [StatsTypeBreakdown]

    // Records (all-time)
    let records: [StatsRecord]

    /// `true` when the history has at least one workout overall (drives the screen-level empty state).
    let hasAnyWorkouts: Bool

    /// `true` when the selected window contains at least one workout.
    var windowHasWorkouts: Bool { workoutCount > 0 }

    // MARK: Build

    /// Builds the summary from the full (newest-first) snapshot array. `referenceDate` is injected so the
    /// computation is deterministic/testable; pass `Date()` from the view.
    static func make(
        from snapshots: [WorkoutSnapshot],
        period: StatsPeriod,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> StatsSummary {

        let window = windowInterval(for: period, reference: referenceDate, calendar: calendar)
        let windowed = window.map { interval in
            snapshots.filter { interval.contains($0.startDate) }
        } ?? snapshots

        // Totals
        let totalDistance = windowed.reduce(0) { $0 + $1.distance }
        let totalDuration = windowed.reduce(0) { $0 + $1.activeDuration }
        let energyValues = windowed.compactMap(\.burnedEnergy)
        let totalEnergy = energyValues.isEmpty ? nil : energyValues.reduce(0, +)

        return StatsSummary(
            period: period,
            workoutCount: windowed.count,
            totalDistanceMeters: totalDistance,
            totalDuration: totalDuration,
            totalEnergy: totalEnergy,
            buckets: buildBuckets(period: period, windowed: windowed, window: window, reference: referenceDate, calendar: calendar),
            typeBreakdown: buildTypeBreakdown(from: windowed),
            records: buildRecords(from: snapshots),
            hasAnyWorkouts: !snapshots.isEmpty
        )
    }

    // MARK: Window

    /// The calendar interval scoping a period, or `nil` for `.all` (no window).
    static func windowInterval(for period: StatsPeriod, reference: Date, calendar: Calendar) -> DateInterval? {
        switch period {
        case .week:  return calendar.dateInterval(of: .weekOfYear, for: reference)
        case .month: return calendar.dateInterval(of: .month, for: reference)
        case .year:  return calendar.dateInterval(of: .year, for: reference)
        case .all:   return nil
        }
    }

    // MARK: Buckets

    private static func buildBuckets(
        period: StatsPeriod,
        windowed: [WorkoutSnapshot],
        window: DateInterval?,
        reference: Date,
        calendar: Calendar
    ) -> [StatsBucket] {
        switch period {
        case .week:
            return weeklyDayBuckets(windowed: windowed, window: window, reference: reference, calendar: calendar)
        case .month:
            return monthWeekBuckets(windowed: windowed, window: window, reference: reference, calendar: calendar)
        case .year:
            return yearMonthBuckets(windowed: windowed, calendar: calendar)
        case .all:
            return allYearBuckets(windowed: windowed, calendar: calendar)
        }
    }

    /// 7 daily buckets across the reference week (Mon…Sun per the user's calendar).
    private static func weeklyDayBuckets(windowed: [WorkoutSnapshot], window: DateInterval?, reference: Date, calendar: Calendar) -> [StatsBucket] {
        let start = window?.start ?? calendar.startOfDay(for: reference)
        let symbols = calendar.veryShortWeekdaySymbols   // index 0 == Sunday
        return (0..<7).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let weekday = calendar.component(.weekday, from: dayStart)   // 1...7
            let dayWorkouts = windowed.filter { calendar.isDate($0.startDate, inSameDayAs: dayStart) }
            return bucket(id: "day-\(offset)", label: symbols[(weekday - 1) % symbols.count], from: dayWorkouts)
        }
    }

    /// Weekly buckets spanning the reference month (~4–6 columns).
    private static func monthWeekBuckets(windowed: [WorkoutSnapshot], window: DateInterval?, reference: Date, calendar: Calendar) -> [StatsBucket] {
        let weeksRange = calendar.range(of: .weekOfMonth, in: .month, for: window?.start ?? reference) ?? 1..<6
        let lower = weeksRange.lowerBound
        return weeksRange.map { weekOfMonth in
            let weekWorkouts = windowed.filter { calendar.component(.weekOfMonth, from: $0.startDate) == weekOfMonth }
            return bucket(id: "week-\(weekOfMonth)", label: "Wk \(weekOfMonth - lower + 1)", from: weekWorkouts)
        }
    }

    /// 12 monthly buckets across the reference year.
    private static func yearMonthBuckets(windowed: [WorkoutSnapshot], calendar: Calendar) -> [StatsBucket] {
        let symbols = calendar.veryShortMonthSymbols     // index 0 == January
        return (1...12).map { month in
            let monthWorkouts = windowed.filter { calendar.component(.month, from: $0.startDate) == month }
            return bucket(id: "month-\(month)", label: symbols[(month - 1) % symbols.count], from: monthWorkouts)
        }
    }

    /// One bucket per calendar year present in the history (used by `.all`).
    private static func allYearBuckets(windowed: [WorkoutSnapshot], calendar: Calendar) -> [StatsBucket] {
        let years = windowed.map { calendar.component(.year, from: $0.startDate) }
        guard let minYear = years.min(), let maxYear = years.max() else { return [] }
        return (minYear...maxYear).map { year in
            let yearWorkouts = windowed.filter { calendar.component(.year, from: $0.startDate) == year }
            // Compact two-digit label keeps a multi-year axis readable.
            return bucket(id: "year-\(year)", label: "'\(String(format: "%02d", year % 100))", from: yearWorkouts)
        }
    }

    private static func bucket(id: String, label: String, from workouts: [WorkoutSnapshot]) -> StatsBucket {
        StatsBucket(
            id: id,
            label: label,
            distanceMeters: workouts.reduce(0) { $0 + $1.distance },
            duration: workouts.reduce(0) { $0 + $1.activeDuration },
            count: workouts.count
        )
    }

    // MARK: Type mix

    private static func buildTypeBreakdown(from windowed: [WorkoutSnapshot]) -> [StatsTypeBreakdown] {
        let grouped = Dictionary(grouping: windowed, by: \.workoutType)
        return grouped.map { type, workouts in
            StatsTypeBreakdown(
                type: type,
                count: workouts.count,
                distanceMeters: workouts.reduce(0) { $0 + $1.distance },
                duration: workouts.reduce(0) { $0 + $1.activeDuration }
            )
        }
        .sorted { ($0.distanceMeters, $0.count) > ($1.distanceMeters, $1.count) }
    }

    // MARK: Records (all-time)

    private static func buildRecords(from snapshots: [WorkoutSnapshot]) -> [StatsRecord] {
        var records: [StatsRecord] = []

        if let best = snapshots.filter({ $0.distance > 0 }).max(by: { $0.distance < $1.distance }) {
            records.append(StatsRecord(
                kind: .longestDistance,
                workoutID: best.id,
                valueText: WorkoutStatFormat.distance(best.distance),
                dateText: WorkoutStatFormat.day(best.startDate)
            ))
        }

        if let best = snapshots.filter({ $0.activeDuration > 0 }).max(by: { $0.activeDuration < $1.activeDuration }) {
            records.append(StatsRecord(
                kind: .longestDuration,
                workoutID: best.id,
                valueText: WorkoutStatFormat.duration(best.activeDuration),
                dateText: WorkoutStatFormat.day(best.startDate)
            ))
        }

        if let best = snapshots.filter({ $0.ascend > 0 }).max(by: { $0.ascend < $1.ascend }) {
            records.append(StatsRecord(
                kind: .biggestClimb,
                workoutID: best.id,
                valueText: WorkoutStatFormat.altitude(best.ascend),
                dateText: WorkoutStatFormat.day(best.startDate)
            ))
        }

        // Fastest average speed/pace — ignore very short efforts (<1 km) where the average is noisy.
        let paceCandidates = snapshots.filter { $0.distance >= 1000 && $0.activeDuration > 0 }
        if let best = paceCandidates.max(by: { ($0.distance / $0.activeDuration) < ($1.distance / $1.activeDuration) }) {
            let metresPerSecond = best.distance / best.activeDuration
            records.append(StatsRecord(
                kind: .bestPace,
                workoutID: best.id,
                valueText: WorkoutStatFormat.speed(metresPerSecond),
                dateText: WorkoutStatFormat.day(best.startDate)
            ))
        }

        return records
    }
}
