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
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "movefeet://workout/active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutActivityMetric(title: "Time") {
                        WorkoutActivityTimerView(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutActivityMetric(title: "Distance", isStale: context.isStale) {
                        Text(context.state.distanceText)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    WorkoutActivityGlyph(isStale: context.isStale)
                }
            } compactLeading: {
                WorkoutActivityCompactTimer(state: context.state)
            } compactTrailing: {
                Text(context.state.distanceText)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(context.isStale ? .secondary : .primary)
            } minimal: {
                WorkoutActivityTimerView(state: context.state)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .widgetURL(URL(string: "movefeet://workout/active"))
            .keylineTint(context.isStale ? .gray : .clear)
        }
    }
}

private struct WorkoutActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            WorkoutActivityGlyph(isStale: context.isStale)
            WorkoutActivityMetric(title: "Time") {
                WorkoutActivityTimerView(state: context.state)
            }
            WorkoutActivityMetric(title: "Distance", isStale: context.isStale) {
                Text(context.state.distanceText)
            }
        }
        .foregroundStyle(.primary)
        .padding()
    }
}

private struct WorkoutActivityGlyph: View {
    var isStale = false

    var body: some View {
        Image(systemName: "figure.run")
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(isStale ? Color.secondary : Color.primary)
            .accessibilityHidden(true)
    }
}

private struct WorkoutActivityCompactTimer: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                Image(systemName: "figure.run")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                WorkoutActivityTimerView(state: state)
            }
            WorkoutActivityTimerView(state: state)
        }
        .font(.caption.monospacedDigit())
    }
}

private struct WorkoutActivityMetric<Value: View>: View {
    let title: String
    var isStale = false
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            value
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isStale ? .secondary : .primary)
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
