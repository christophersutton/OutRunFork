//
//  WorkoutDetailSupport.swift
//
//  OutRun
//
//  Formatting helpers and reusable building blocks for the SwiftUI workout detail screen. All formatting
//  reuses the app's existing helpers (StatsHelper / CustomMeasurementFormatting / CustomDateFormatting) so
//  the new SwiftUI screen renders values identically to the rest of the app. These are synchronous,
//  main-safe Foundation calls; the snapshot stores raw SI/metric values and conversion happens here.
//

import SwiftUI

// MARK: - Formatting

/// Display formatting for a `WorkoutDetailSnapshot`'s raw (SI/metric) values. Each method returns the
/// localized, user-unit string the tiles show.
enum WorkoutStatFormat {

    /// Distance (metres in → user distance unit, e.g. "5.2 km").
    static func distance(_ metres: Double) -> String {
        StatsHelper.string(for: metres, unit: UnitLength.meters)
    }

    /// Altitude (metres in → user altitude unit; must pass `.altitude` so it doesn't use the distance unit).
    static func altitude(_ metres: Double) -> String {
        StatsHelper.string(for: metres, unit: UnitLength.meters, type: .altitude)
    }

    /// Speed (m/s in → user speed/pace unit).
    static func speed(_ metresPerSecond: Double) -> String {
        StatsHelper.string(for: metresPerSecond, unit: UnitSpeed.metersPerSecond)
    }

    /// Energy (kcal in → user energy unit).
    static func energy(_ kilocalories: Double) -> String {
        StatsHelper.string(for: kilocalories, unit: UnitEnergy.kilocalories)
    }

    /// Duration as HH:MM:SS (seconds in → clock string).
    static func duration(_ seconds: TimeInterval) -> String {
        StatsHelper.string(for: seconds, unit: UnitDuration.seconds, type: .clock)
    }

    /// A plain integer count (steps), no unit symbol.
    static func count(_ value: Int) -> String {
        StatsHelper.string(for: Double(value), unit: UnitCount.count, rounding: .wholeNumbers)
    }

    /// Heart rate as "N bpm".
    static func heartRate(_ bpm: Int) -> String {
        "\(count(bpm)) bpm"
    }

    /// Time-of-day string (e.g. "3:45 PM").
    static func time(_ date: Date) -> String {
        CustomDateFormatting.timeString(forDate: date)
    }

    /// Relative day string (e.g. "Today", "Monday", "Jun 19, 2026").
    static func day(_ date: Date) -> String {
        CustomDateFormatting.dayString(forDate: date)
    }

    /// Compact clock label for a chart's time axis (seconds since start → "m:ss" or "h:mm:ss").
    static func axisClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Workout type icon

extension Workout.WorkoutType {

    /// SF Symbol representing the workout type. (No icon mapping exists in the legacy code, so this is new.)
    var sfSymbolName: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .skating: return "figure.skating"
        case .hiking:  return "figure.hiking"
        case .unknown: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Tiles & sections

/// A single small stat tile: a bold caption above a large value, on a rounded card.
struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.orSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color.orPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orForeground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

/// Lightweight value type describing one tile in a grid.
struct StatTileData: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

/// Lays stat tiles two-per-row; a lone trailing tile stretches to full width.
struct StatTileGrid: View {
    let tiles: [StatTileData]

    private var rows: [[StatTileData]] {
        stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0 ..< min($0 + 2, tiles.count)]) }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    ForEach(rows[index]) { tile in
                        StatTile(title: tile.title, value: tile.value)
                    }
                }
            }
        }
    }
}

/// A titled section: a heavy header above arbitrary content.
struct StatSectionView<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.orPrimary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
