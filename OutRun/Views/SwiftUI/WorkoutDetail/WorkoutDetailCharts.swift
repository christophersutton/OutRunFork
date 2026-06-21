//
//  WorkoutDetailCharts.swift
//
//  OutRun
//
//  Swift Charts replacement for the old DGCharts `LabelledDiagramView`. This is the ONLY file that imports
//  the (Apple) Charts framework. It is a dumb plotter: it receives points already in display units plus a
//  unit symbol; unit conversion is done by the caller (WorkoutDetailView) from the snapshot's raw series.
//

import SwiftUI
import Charts

/// A titled line chart of a workout metric over time. `points` are in display units; `x` is seconds since
/// the workout start. Matches the legacy diagram's look: trailing Y axis, time X axis, no legend, fixed
/// height, on a rounded card.
struct WorkoutLineChartView: View {

    let title: String
    let points: [WorkoutChartPoint]
    let unitSymbol: String
    var color: Color = .orAccent

    private var finitePoints: [WorkoutChartPoint] {
        points.filter { $0.x.isFinite && $0.y.isFinite }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unitSymbol.isEmpty ? title : "\(title) (\(unitSymbol))")
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Color.orSecondary)

            Chart {
                ForEach(Array(finitePoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.x),
                        y: .value(title, point.y)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(WorkoutStatFormat.axisClock(seconds))
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orForeground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
