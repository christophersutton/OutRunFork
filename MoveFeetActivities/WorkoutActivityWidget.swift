//
//  WorkoutActivityWidget.swift
//  MoveFeetActivities
//

import ActivityKit
import SwiftUI
import WidgetKit

// Move Live Activity: ink ground, numbers in the accent, labels in muted.
private enum ActivityPalette {
    static let ink = Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
    static let paper = Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255)
    static let muted = Color(red: 142 / 255, green: 142 / 255, blue: 150 / 255)

    static func accent(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

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
                .activityBackgroundTint(ActivityPalette.ink)
                .activitySystemActionForegroundColor(ActivityPalette.paper)
                .widgetURL(URL(string: "movefeet://workout/active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutActivityMetric(title: "Time", accent: ActivityPalette.accent(context.attributes.accentHex)) {
                        WorkoutActivityTimerView(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutActivityMetric(title: "Distance", isStale: context.isStale) {
                        Text(context.state.distanceText)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    WorkoutActivityGlyph(isStale: context.isStale, accent: ActivityPalette.accent(context.attributes.accentHex))
                }
            } compactLeading: {
                WorkoutActivityCompactTimer(state: context.state, accent: ActivityPalette.accent(context.attributes.accentHex))
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
            .keylineTint(context.isStale ? .gray : ActivityPalette.accent(context.attributes.accentHex))
        }
    }
}

private struct WorkoutActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        let accent = ActivityPalette.accent(context.attributes.accentHex)
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            WorkoutActivityGlyph(isStale: context.isStale, accent: accent)
            WorkoutActivityMetric(title: "Time", accent: accent) {
                WorkoutActivityTimerView(state: context.state)
            }
            WorkoutActivityMetric(title: "Distance", isStale: context.isStale) {
                Text(context.state.distanceText)
            }
        }
        .foregroundStyle(ActivityPalette.paper)
        .padding()
    }
}

private struct WorkoutActivityGlyph: View {
    var isStale = false
    var accent: Color = .orange

    var body: some View {
        Image(systemName: "figure.run")
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(isStale ? ActivityPalette.muted : accent)
            .accessibilityHidden(true)
    }
}

private struct WorkoutActivityCompactTimer: View {
    let state: WorkoutActivityAttributes.ContentState
    var accent: Color = .orange

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                Image(systemName: "figure.run")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
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
    /// Tints the value; `nil` keeps it in paper.
    var accent: Color? = nil
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(ActivityPalette.muted)
            value
                .font(.system(.title2, weight: .heavy).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isStale ? ActivityPalette.muted : (accent ?? ActivityPalette.paper))
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
