//
//  StatsView.swift
//
//  OutRun
//
//  The "Stats" dashboard tab — a workout-history summary that goes beyond the timeline list. It is driven by
//  the same `WorkoutStore` value snapshots the timeline uses (never a live CoreStore object), and derives a
//  pure `StatsSummary` for the selected period. Sections: period-scoped totals, an adaptive trend bar chart
//  (distance / active-time), a workout-type mix, and tappable all-time records that open the existing
//  `WorkoutDetailView`.
//
//  Charting uses Apple's Swift Charts (already used by `WorkoutDetailCharts`). Aggregation is cached by the
//  workout-store generation and selected period so unrelated view updates do not rescan workout history.
//

import SwiftUI
import Charts

struct StatsView: View {

    @State private var store = WorkoutStore.shared

    @State private var period: StatsPeriod = .month
    @State private var metric: StatsMetric = .distance
    @State private var selectedWorkout: WorkoutSnapshot?
    @State private var statsSummary: StatsSummary?
    @State private var statsSummaryKey: StatsSummaryCacheKey?

    // Formatted strings read `UserPreferences` (not observable). Re-render when the tab reappears with a
    // changed distance unit, mirroring the timeline's refresh approach.
    @State private var lastDistanceUnit = UserPreferences.distanceMeasurementType.safeValue
    @State private var unitRefreshToken = 0

    var body: some View {
        NavigationStack {
            content
                .background(Color.orBackground)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    let current = UserPreferences.distanceMeasurementType.safeValue
                    if current != lastDistanceUnit {
                        lastDistanceUnit = current
                        unitRefreshToken += 1
                    }
                }
                .task(id: currentStatsSummaryKey) {
                    rebuildStatsSummary(for: currentStatsSummaryKey)
                }
                .sheet(item: $selectedWorkout) { snapshot in
                    NavigationStack { WorkoutDetailView(workoutID: snapshot.id) }
                }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !store.isLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let key = currentStatsSummaryKey

            if let summary = statsSummary, statsSummaryKey == key, !summary.hasAnyWorkouts {
                ContentUnavailableView(
                    "No Stats Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Record a workout to start tracking your distance, time and trends.")
                )
            } else if let summary = statsSummary, statsSummaryKey == key {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        periodPicker
                        totalsSection(summary)
                        trendSection(summary)
                        typeMixSection(summary)
                        recordsSection(summary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        Text("stats")
            .font(Font.system(.largeTitle, weight: .heavy).lowercaseSmallCaps())
            .foregroundStyle(Color.orAccent)
            .padding(.top, 8)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { period in
                Text(period.pickerTitle).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Totals

    private func totalsSection(_ summary: StatsSummary) -> some View {
        StatSectionView(title: summary.period.windowCaption) {
            StatTileGrid(tiles: [
                StatTileData(title: "Workouts", value: "\(summary.workoutCount)"),
                StatTileData(title: "Distance", value: WorkoutStatFormat.distance(summary.totalDistanceMeters)),
                StatTileData(title: "Active Time", value: WorkoutStatFormat.duration(summary.totalDuration)),
                StatTileData(title: "Calories", value: summary.totalEnergy.map(WorkoutStatFormat.energy) ?? "--")
            ])
        }
    }

    // MARK: Trend

    private func trendSection(_ summary: StatsSummary) -> some View {
        StatSectionView(title: "Trend") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Metric", selection: $metric) {
                    ForEach(StatsMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                StatsTrendChart(
                    buckets: summary.buckets,
                    metric: metric,
                    distanceUnit: lastDistanceUnit,
                    emptyMessage: summary.windowHasWorkouts ? nil : "No workouts \(summary.period.inlineCaption)"
                )
            }
        }
    }

    // MARK: Type mix

    @ViewBuilder
    private func typeMixSection(_ summary: StatsSummary) -> some View {
        StatSectionView(title: "Type Mix") {
            if summary.typeBreakdown.isEmpty {
                Text("No workouts \(summary.period.inlineCaption)")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color.orSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                let maxDistance = summary.typeBreakdown.map(\.distanceMeters).max() ?? 0
                VStack(spacing: 12) {
                    ForEach(summary.typeBreakdown) { item in
                        TypeMixRow(item: item, maxDistance: maxDistance)
                    }
                }
            }
        }
    }

    // MARK: Records

    @ViewBuilder
    private func recordsSection(_ summary: StatsSummary) -> some View {
        if !summary.records.isEmpty {
            StatSectionView(title: "All-Time Records") {
                let rows = stride(from: 0, to: summary.records.count, by: 2).map {
                    Array(summary.records[$0 ..< min($0 + 2, summary.records.count)])
                }
                VStack(spacing: 12) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            ForEach(rows[index]) { record in
                                RecordTile(record: record) { openWorkout(record.workoutID) }
                            }
                            if rows[index].count == 1 { Spacer(minLength: 0) }
                        }
                    }
                }
            }
        }
    }

    private func openWorkout(_ id: UUID) {
        selectedWorkout = store.workouts.first { $0.id == id }
    }

    private var currentStatsSummaryKey: StatsSummaryCacheKey {
        StatsSummaryCacheKey(
            workoutGeneration: store.generation,
            period: period,
            unitRefreshToken: unitRefreshToken
        )
    }

    @MainActor
    private func rebuildStatsSummary(for key: StatsSummaryCacheKey) {
        guard store.isLoaded else {
            statsSummary = nil
            statsSummaryKey = key
            return
        }

        let startedAt = PerformanceDiagnostics.mark()
        let snapshots = store.workouts
        statsSummary = StatsSummary.make(from: snapshots, period: key.period, referenceDate: Date())
        statsSummaryKey = key
        PerformanceDiagnostics.log(
            "StatsSummary.make",
            since: startedAt,
            details: "workouts=\(snapshots.count) generation=\(key.workoutGeneration) period=\(key.period)"
        )
    }
}

private struct StatsSummaryCacheKey: Hashable {
    let workoutGeneration: Int
    let period: StatsPeriod
    let unitRefreshToken: Int
}

// MARK: - Trend chart

/// A lightweight bar chart of a single metric across the period's buckets. Distance is converted to the
/// user's unit here (the bucket holds metres); time is shown in hours. Shows a centered message when the
/// window is empty so the section never collapses to a blank rectangle.
private struct StatsTrendChart: View {

    let buckets: [StatsBucket]
    let metric: StatsMetric
    let distanceUnit: UnitLength
    let emptyMessage: String?

    private func value(for bucket: StatsBucket) -> Double {
        switch metric {
        case .distance:
            return Measurement(value: bucket.distanceMeters, unit: UnitLength.meters)
                .converted(to: distanceUnit).value
        case .time:
            return bucket.duration / 3600       // hours
        }
    }

    private var unitSymbol: String {
        metric == .distance ? distanceUnit.symbol : "h"
    }

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Period", bucket.label),
                y: .value(metric.title, value(for: bucket))
            )
            .foregroundStyle(Color.orAccent)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartYAxisLabel(unitSymbol)
        .frame(height: 200)
        .overlay {
            if let emptyMessage {
                Text(emptyMessage)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color.orSecondary)
            }
        }
        .padding(14)
        .background(Color.orForeground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

// MARK: - Type mix row

/// One workout type's share: icon + name, count/distance, and a proportional accent bar (relative to the
/// most-travelled type in the window).
private struct TypeMixRow: View {

    let item: StatsTypeBreakdown
    let maxDistance: Double

    private var fraction: Double {
        guard maxDistance > 0 else { return 0 }
        return min(1, item.distanceMeters / maxDistance)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.type.sfSymbolName)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.orAccent)
                    .frame(width: 24)

                Text(item.type.description)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.orPrimary)

                Spacer(minLength: 8)

                Text("\(item.count) • \(WorkoutStatFormat.distance(item.distanceMeters))")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Color.orSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.orSecondary.opacity(0.18))
                    Capsule()
                        .fill(Color.orAccent)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.orForeground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

// MARK: - Record tile

/// A tappable all-time record card: icon + title, big value, and the date it was set. Opens the workout.
private struct RecordTile: View {

    let record: StatsRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: record.kind.sfSymbol)
                        .font(.system(.caption, weight: .bold))
                    Text(record.kind.title)
                        .font(.system(.caption, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Color.orSecondary)

                Text(record.valueText)
                    .font(.system(.title3, weight: .heavy))
                    .foregroundStyle(Color.orPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(record.dateText)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(Color.orSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orForeground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
