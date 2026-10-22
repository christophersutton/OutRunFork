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

    private var yScaleDomain: ClosedRange<Double> {
        let values = finitePoints.map(\.y)
        guard let minY = values.min(), let maxY = values.max() else {
            return 0 ... 1
        }

        guard minY != maxY else {
            let padding = minY == 0 ? 1 : max(abs(minY) * 0.05, 0.01)
            return paddedDomain(minY: minY, maxY: maxY, padding: padding)
        }

        return paddedDomain(minY: minY, maxY: maxY, padding: (maxY - minY) * 0.08)
    }

    private func paddedDomain(minY: Double, maxY: Double, padding: Double) -> ClosedRange<Double> {
        let lower: Double
        if minY > 0 {
            lower = max(minY - padding, minY * 0.5)
        } else if minY == 0 {
            lower = 0
        } else {
            lower = minY - padding
        }

        let upper: Double
        if maxY < 0 {
            upper = min(maxY + padding, maxY * 0.5)
        } else {
            upper = maxY + padding
        }

        return lower ... upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unitSymbol.isEmpty ? title : "\(title) (\(unitSymbol))")
                .moveLabelStyle()

            Chart {
                ForEach(Array(finitePoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.x),
                        y: .value(title, point.y)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYScale(domain: yScaleDomain)
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Color.orLine)
                    AxisValueLabel().font(.caption2.monospacedDigit()).foregroundStyle(Color.orSecondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.orLine)
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(WorkoutStatFormat.axisClock(seconds))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.orSecondary)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moveCard()
    }
}
