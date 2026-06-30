//
//  DebugView.swift
//
//  OutRun
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import SwiftUI
import UIKit

@MainActor
struct DebugView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var databaseRows: [DebugInfoRow]? = nil
    @State private var cacheDiskSize: Int? = nil
    @State private var cacheSize: String = "…"
    @State private var clearCacheMessage = ""
    @State private var isShowingClearCacheAlert = false
    @State private var performanceLogSummary = ""
    @State private var performanceLogMessage = ""
    @State private var isShowingPerformanceLogAlert = false
    
    private var isClearCacheDisabled: Bool {
        [0, -1, nil].contains(cacheDiskSize)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Database") {
                    ForEach(databaseRows ?? Self.placeholderDatabaseRows) { row in
                        DebugValueRow(title: row.title, value: row.value)
                    }
                }
                
                Section("Cache") {
                    DebugValueRow(title: "Cache Storage Size", value: cacheSize)
                    
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .disabled(isClearCacheDisabled)
                }

                Section("Performance") {
                    DebugValueRow(title: "Recent Events", value: performanceLogSummary)

                    Button("Mark Slow Moment") {
                        markSlowMoment()
                    }

                    Button("Export Performance Log") {
                        exportPerformanceLog()
                    }

                    Button("Clear Performance Log", role: .destructive) {
                        clearPerformanceLog()
                    }
                }
                
                Section("Config") {
                    DebugValueRow(title: "isDebug", value: String(Config.isDebug))
                    DebugValueRow(title: "isRunOnSimulator", value: String(Config.isRunOnSimulator))
                    DebugValueRow(title: "hasMobileProvision", value: String(Config.hasMobileProvision))
                    DebugValueRow(title: "hasSanboxReceipt", value: String(Config.hasSanboxReceipt))
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(LS["Close"]))
                    .tint(Color.orAccent)
                }
            }
            .tint(Color.orAccent)
        }
        .task {
            await loadValues()
        }
        .onAppear {
            updatePerformanceLogSummary()
        }
        .alert(
            "Clear Cache",
            isPresented: $isShowingClearCacheAlert,
            actions: {
                Button("OK") { }
            },
            message: {
                Text(clearCacheMessage)
            }
        )
        .alert(
            "Performance Log",
            isPresented: $isShowingPerformanceLogAlert,
            actions: {
                Button("OK") { }
            },
            message: {
                Text(performanceLogMessage)
            }
        )
    }
    
    private func loadValues() async {
        let summary = await DataManager.debugSummary()
        let databaseRows = [
            DebugInfoRow(
                title: "Database Storage Size",
                value: CustomByteFormatting.string(for: summary.databaseStorageSize ?? -1)
            ),
            DebugInfoRow(
                title: "Workouts",
                value: String(summary.workoutCount)
            ),
            DebugInfoRow(
                title: "RouteDataSamples",
                value: String(summary.routeDataSampleCount)
            ),
            DebugInfoRow(
                title: "WorkoutEvents",
                value: String(summary.workoutEventCount)
            ),
            DebugInfoRow(
                title: "HeartRateDataSamples",
                value: String(summary.heartRateDataSampleCount)
            ),
            DebugInfoRow(
                title: "Events",
                value: String(summary.eventCount)
            )
        ]
        
        self.databaseRows = databaseRows
        updateCacheSize(summary.cacheDiskSize)
    }
    
    private func clearCache() {
        CustomImageCache.mapImageCache.clear { success in
            updateCacheSize(CustomImageCache.mapImageCache.diskSize)
            clearCacheMessage = success ? "Successfully cleared cache." : "Failed to clear cache."
            isShowingClearCacheAlert = true
        }
    }
    
    private func updateCacheSize(_ diskSize: Int?) {
        cacheDiskSize = diskSize
        cacheSize = CustomByteFormatting.string(for: diskSize ?? -1)
    }

    private func updatePerformanceLogSummary() {
        let events = PerformanceDiagnostics.snapshot()
        if let latest = events.last {
            performanceLogSummary = "\(events.count) - \(latest.label)"
        } else {
            performanceLogSummary = "0"
        }
    }

    private func markSlowMoment() {
        PerformanceDiagnostics.event("Manual slow moment", details: "Marked from DebugView")
        updatePerformanceLogSummary()
    }

    private func exportPerformanceLog() {
        do {
            let url = try PerformanceDiagnostics.exportLogFile()
            guard let presenter = UIApplication.shared.topMostViewController else {
                try? FileManager.default.removeItem(at: url)
                performanceLogMessage = "Could not open the share sheet."
                isShowingPerformanceLogAlert = true
                return
            }

            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: url)
            }
            presenter.present(activityVC, animated: true)
        } catch {
            performanceLogMessage = error.localizedDescription
            isShowingPerformanceLogAlert = true
        }
    }

    private func clearPerformanceLog() {
        PerformanceDiagnostics.clear()
        updatePerformanceLogSummary()
    }
    
    private static let placeholderDatabaseRows = [
        DebugInfoRow(title: "Database Storage Size", value: "…"),
        DebugInfoRow(title: "Workouts", value: "…"),
        DebugInfoRow(title: "RouteDataSamples", value: "…"),
        DebugInfoRow(title: "WorkoutEvents", value: "…"),
        DebugInfoRow(title: "HeartRateDataSamples", value: "…"),
        DebugInfoRow(title: "Events", value: "…")
    ]
    
}

private struct DebugValueRow: View {
    
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.orPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.orSecondary)
        }
    }
    
}

private struct DebugInfoRow: Identifiable, Sendable {
    
    let title: String
    let value: String
    
    var id: String {
        title
    }
    
}
