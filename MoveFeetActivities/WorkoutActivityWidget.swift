//
//  WorkoutActivityWidget.swift
//  MoveFeetActivities
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MoveFeetActivitiesBundle: WidgetBundle {
    var body: some Widget {
        WorkoutActivityWidget()
    }
}

struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.accentColor)
                .widgetURL(URL(string: "movefeet://workout/active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.workoutTypeName, systemImage: context.attributes.workoutTypeSymbol)
                        .font(.headline)
                        .foregroundStyle(context.state.statusColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutActivityTimerView(state: context.state)
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                }
                DynamicIslandExpandedRegion(.center) {
                    WorkoutActivityStatusPill(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityStatsRow(
                        state: context.state,
                        usesPace: context.attributes.usesPace
                    )
                }
            } compactLeading: {
                Image(systemName: context.attributes.workoutTypeSymbol)
                    .foregroundStyle(context.state.statusColor)
            } compactTrailing: {
                WorkoutActivityTimerView(state: context.state)
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: context.attributes.workoutTypeSymbol)
                    .foregroundStyle(context.state.statusColor)
            }
            .widgetURL(URL(string: "movefeet://workout/active"))
            .keylineTint(context.state.statusColor)
        }
    }
}

private struct WorkoutActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(context.attributes.workoutTypeName, systemImage: context.attributes.workoutTypeSymbol)
                    .font(.headline)
                Spacer()
                WorkoutActivityStatusPill(state: context.state)
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                WorkoutActivityStat(title: "Duration") {
                    WorkoutActivityTimerView(state: context.state)
                }
                WorkoutActivityStat(title: "Distance", value: context.state.distanceText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                WorkoutActivityStat(title: context.attributes.usesPace ? "Pace" : "Speed", value: context.state.paceOrSpeedText)
                WorkoutActivityStat(title: "Calories", value: context.state.caloriesText)
            }
        }
        .foregroundStyle(.primary)
        .padding()
    }
}

private struct WorkoutActivityStatsRow: View {
    let state: WorkoutActivityAttributes.ContentState
    let usesPace: Bool

    var body: some View {
        HStack(spacing: 8) {
            WorkoutActivityStat(title: "Distance", value: state.distanceText)
            WorkoutActivityStat(title: usesPace ? "Pace" : "Speed", value: state.paceOrSpeedText)
            WorkoutActivityStat(title: "Calories", value: state.caloriesText)
        }
    }
}

private struct WorkoutActivityStat<Value: View>: View {
    let title: String
    @ViewBuilder var value: Value

    init(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    init(title: String, value: String) where Value == Text {
        self.title = title
        self.value = Text(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            value
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkoutActivityTimerView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.timerStart...Date.distantFuture,
            pauseTime: state.pauseTime,
            countsDown: false
        )
        .monospacedDigit()
    }
}

private struct WorkoutActivityStatusPill: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Text(state.statusTitle.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(state.statusColor, in: Capsule())
    }
}

private extension WorkoutActivityAttributes {
    var workoutTypeName: String {
        switch workoutTypeRawValue {
        case 0: return "Running"
        case 1: return "Walking"
        case 4: return "Hiking"
        default: return "Workout"
        }
    }

    var workoutTypeSymbol: String {
        switch workoutTypeRawValue {
        case 0: return "figure.run"
        case 1: return "figure.walk"
        case 4: return "figure.hiking"
        default: return "figure.run"
        }
    }
}

private extension WorkoutActivityAttributes.ContentState {
    var statusColor: Color {
        if isPaused { return .gray }
        if statusKind == "recording" { return .red }
        return .green
    }
}
