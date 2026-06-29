//
//  WorkoutDetailView.swift
//
//  OutRun
//
//  The SwiftUI workout detail screen — replaces the UIKit `WorkoutViewController`. It holds only a value
//  `WorkoutDetailSnapshot` (built off the CoreStore queue by `DataManager.workoutDetailSnapshot(for:)`),
//  never a live `Workout`. Live `Workout` objects are re-resolved on the main queue, on demand, only for
//  the action handlers (share / edit / delete / Apple Health / full-screen map) which need to hand a real
//  object to the existing UIKit managers.
//
//  Note: unlike the legacy screen — whose stat tiles were never bound to data and whose charts were never
//  fed — this screen renders real values. Charts are added on top of this in the Swift Charts step.
//

import SwiftUI
import UIKit

@MainActor
struct WorkoutDetailView: View {

    let workoutID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: WorkoutDetailSnapshot?
    @State private var loadFailed = false
    @State private var reloadToken = 0

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showHealthDeletePrompt = false

    var body: some View {
        content
            .background(Color.orBackground)
            .navigationTitle(snapshot?.workoutType.description ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(LS["Close"]))
                }
                if snapshot != nil {
                    ToolbarItem(placement: .navigationBarTrailing) { actionsMenu }
                }
            }
            .confirmationDialog(
                LS["WorkoutDeletion.Title"],
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(LS["Delete"], role: .destructive) { afterDeleteConfirmed() }
                Button(LS["Cancel"], role: .cancel) {}
            } message: {
                Text(LS["WorkoutDeletion.Message"])
            }
            .confirmationDialog(
                LS["WorkoutDeletion.AppleHealth.Title"],
                isPresented: $showHealthDeletePrompt,
                titleVisibility: .visible
            ) {
                Button(LS["Delete"], role: .destructive) { performDelete(removeFromHealth: true) }
                Button(LS["Keep"]) { performDelete(removeFromHealth: false) }
                Button(LS["Cancel"], role: .cancel) {}
            } message: {
                Text(LS["WorkoutDeletion.AppleHealth.Message"])
            }
            .task(id: reloadToken) { await load() }
            .sheet(isPresented: $showEditSheet) {
                // Editing the *existing* workout; on save, dismiss the sheet and refresh this screen's
                // snapshot in place (the form delegates all teardown to this hook).
                EditWorkoutForm(mode: .edit(workoutID)) { _ in
                    showEditSheet = false
                    reloadToken += 1
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header(snapshot)
                    sections(snapshot)
                }
                .padding(20)
            }
            .contentMargins(.bottom, 12, for: .scrollContent)
        } else if loadFailed {
            ContentUnavailableView(
                LS["WorkoutViewController.LoadingError"],
                systemImage: "exclamationmark.triangle"
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ snapshot: WorkoutDetailSnapshot) -> some View {
        HStack(spacing: 16) {
            Image(systemName: snapshot.workoutType.sfSymbolName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.orAccent)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.workoutType.description)
                    .font(.system(.title2, weight: .heavy))
                    .foregroundStyle(Color.orPrimary)
                Text(headerSubtitle(snapshot))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.orSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func headerSubtitle(_ snapshot: WorkoutDetailSnapshot) -> String {
        var parts = [WorkoutStatFormat.day(snapshot.startDate)]
        if snapshot.isRace { parts.append(LS["Workout.Race"]) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func sections(_ snapshot: WorkoutDetailSnapshot) -> some View {
        distanceSection(snapshot)
        timeSection(snapshot)
        speedSection(snapshot)
        if snapshot.hasEnergy { energySection(snapshot) }
        if snapshot.hasHeartRateData { heartRateSection(snapshot) }
        if snapshot.hasRouteData { routeSection(snapshot) }
        if snapshot.comment != nil || snapshot.isUserModified { commentSection(snapshot) }
    }

    // MARK: Sections

    private func distanceSection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        var tiles = [StatTileData(title: LS["Workout.Distance"], value: WorkoutStatFormat.distance(snapshot.distance))]
        if let steps = snapshot.steps {
            tiles.append(StatTileData(title: LS["Workout.Steps"], value: WorkoutStatFormat.count(steps)))
        }
        if snapshot.hasRouteData {
            tiles.append(StatTileData(title: LS["WorkoutStats.AscendingAltitude"], value: WorkoutStatFormat.altitude(snapshot.ascend)))
            tiles.append(StatTileData(title: LS["WorkoutStats.DescendingAltitude"], value: WorkoutStatFormat.altitude(snapshot.descend)))
        }
        return StatSectionView(title: LS["Workout.Distance"]) {
            StatTileGrid(tiles: tiles)
            altitudeChart(snapshot)
        }
    }

    private func timeSection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        var tiles = [StatTileData(title: LS["Workout.ActiveDuration"], value: WorkoutStatFormat.duration(snapshot.activeDuration))]
        if snapshot.hasPauses {
            tiles.append(StatTileData(title: LS["Workout.PauseDuration"], value: WorkoutStatFormat.duration(snapshot.pauseDuration)))
        }
        tiles.append(StatTileData(title: LS["WorkoutStats.StartTime"], value: WorkoutStatFormat.time(snapshot.startDate)))
        tiles.append(StatTileData(title: LS["WorkoutStats.EndTime"], value: WorkoutStatFormat.time(snapshot.endDate)))
        return StatSectionView(title: LS["WorkoutStats.Time"]) {
            StatTileGrid(tiles: tiles)
        }
    }

    private func speedSection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        var tiles: [StatTileData] = []
        if let avg = snapshot.averageSpeed {
            tiles.append(StatTileData(title: LS["WorkoutStats.AverageSpeed"], value: WorkoutStatFormat.speed(avg)))
        }
        if let top = snapshot.topSpeed {
            tiles.append(StatTileData(title: LS["WorkoutStats.TopSpeed"], value: WorkoutStatFormat.speed(top)))
        }
        return StatSectionView(title: LS["WorkoutStats.Speed"]) {
            StatTileGrid(tiles: tiles)
            speedChart(snapshot)
        }
    }

    private func energySection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        StatSectionView(title: LS["WorkoutStats.BurnedEnergy"]) {
            StatTileGrid(tiles: [
                StatTileData(title: LS["WorkoutStats.TotalEnergy"], value: WorkoutStatFormat.energy(snapshot.burnedEnergy ?? 0))
            ])
        }
    }

    private func heartRateSection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        var tiles: [StatTileData] = []
        if let avg = snapshot.averageHeartRate {
            tiles.append(StatTileData(title: LS["WorkoutStats.AverageHeartRate"], value: WorkoutStatFormat.heartRate(avg)))
        }
        return StatSectionView(title: LS["WorkoutStats.HeartRate"]) {
            StatTileGrid(tiles: tiles)
            heartRateChart(snapshot)
        }
    }

    // MARK: Charts

    @ViewBuilder
    private func altitudeChart(_ snapshot: WorkoutDetailSnapshot) -> some View {
        if snapshot.hasAltitudeData {
            let unit = UserPreferences.altitudeMeasurementType.safeValue
            WorkoutLineChartView(
                title: LS["WorkoutStats.AltitudeOverTime"],
                points: convertSeries(snapshot.altitudeSeries, from: UnitLength.meters, to: unit),
                unitSymbol: CustomMeasurementFormatting.string(forUnit: unit, short: true)
            )
        }
    }

    @ViewBuilder
    private func speedChart(_ snapshot: WorkoutDetailSnapshot) -> some View {
        if snapshot.hasSpeedData {
            let unit = UserPreferences.speedMeasurementType.safeValue
            WorkoutLineChartView(
                title: LS["WorkoutStats.SpeedOverTime"],
                points: convertSeries(snapshot.speedSeries, from: UnitSpeed.metersPerSecond, to: unit),
                unitSymbol: CustomMeasurementFormatting.string(forUnit: unit, short: true)
            )
        }
    }

    @ViewBuilder
    private func heartRateChart(_ snapshot: WorkoutDetailSnapshot) -> some View {
        if snapshot.hasHeartRateData {
            WorkoutLineChartView(
                title: LS["WorkoutStats.HeartRateOverTime"],
                points: snapshot.heartRateSeries,   // bpm — no conversion
                unitSymbol: "bpm"
            )
        }
    }

    /// Converts a raw (metric) series into the user's preferred display unit for the chart axis,
    /// dropping any non-finite results (e.g. a 0 m/s sample under an inverse pace unit).
    private func convertSeries(_ points: [WorkoutChartPoint], from source: Dimension, to display: Dimension) -> [WorkoutChartPoint] {
        points.compactMap { point in
            let y = Measurement(value: point.y, unit: source).converted(to: display).value
            return y.isFinite ? WorkoutChartPoint(x: point.x, y: y) : nil
        }
    }

    private func routeSection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        StatSectionView(title: LS["WorkoutStats.Route"]) {
            RouteMapView(coordinates: snapshot.routeCoordinates, isInteractive: false)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(12)
                }
                .contentShape(Rectangle())
                .onTapGesture { openFullScreenMap() }
        }
    }

    private func commentSection(_ snapshot: WorkoutDetailSnapshot) -> some View {
        StatSectionView(title: LS["Workout.Comment"]) {
            VStack(alignment: .leading, spacing: 8) {
                if let comment = snapshot.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.body)
                        .foregroundStyle(Color.orPrimary)
                }
                if snapshot.isUserModified {
                    Text(LS["Workout.IsUserModified.Text"])
                        .font(.caption)
                        .foregroundStyle(Color.orSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orForeground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    // MARK: - Actions menu

    private var actionsMenu: some View {
        Menu {
            Button { share() } label: { Label(LS["Share"], systemImage: "square.and.arrow.up") }
            Button { showEditSheet = true } label: { Label(LS["Edit"], systemImage: "pencil") }
            if let snapshot {
                let inHealth = snapshot.healthKitUUID != nil
                Button { toggleAppleHealth() } label: {
                    Label(inHealth ? LS["AppleHealth.Remove"] : LS["AppleHealth.Add"], systemImage: "heart")
                }
            }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(LS["Delete"], systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Loading

    private func load() async {
        let result = await DataManager.workoutDetailSnapshot(for: workoutID)
        if let result {
            snapshot = result
            loadFailed = false
        } else {
            loadFailed = true
        }
    }

    // MARK: - Live-object resolution & presentation

    /// Re-resolves the live, main-context `Workout` for an action. Safe on the main thread.
    private func liveWorkout() -> Workout? {
        let workout: Workout? = DataManager.queryObject(from: workoutID)
        return workout
    }

    /// The frontmost view controller, used as a presenter for the UIKit share sheet / editor / map.
    private func topMostViewController() -> UIViewController? {
        var top = UIApplication.shared.activeKeyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private func share() {
        guard let workout = liveWorkout(), let presenter = topMostViewController() else { return }
        ExportManager.displayShareAlert(for: .someWorkouts([workout]), on: presenter)
    }

    private func openFullScreenMap() {
        guard let workout = liveWorkout(), let presenter = topMostViewController() else { return }
        let mapController = WorkoutMapViewController()
        mapController.workout = workout
        presenter.present(mapController, animated: true)
    }

    private func toggleAppleHealth() {
        guard let workout = liveWorkout() else { return }
        let reload: () -> Void = { reloadToken += 1 }
        if workout.healthKitUUID == nil {
            HealthStoreManager.saveHealthWorkout(for: workout) { _, _ in
                DispatchQueue.main.async { reload() }
            }
        } else {
            HealthStoreManager.deleteHealthWorkout(for: workout) { _ in
                DispatchQueue.main.async { reload() }
            }
        }
    }

    // MARK: - Delete

    private func afterDeleteConfirmed() {
        if snapshot?.healthKitUUID != nil {
            showHealthDeletePrompt = true
        } else {
            performDelete(removeFromHealth: false)
        }
    }

    private func performDelete(removeFromHealth: Bool) {
        guard let workout = liveWorkout() else { return }

        func deleteFromStore() {
            DataManager.deleteObject(object: workout) { success, _ in
                DispatchQueue.main.async {
                    if success { dismiss() }
                }
            }
        }

        if removeFromHealth, workout.healthKitUUID != nil {
            HealthStoreManager.deleteHealthWorkout(for: workout) { _ in
                DispatchQueue.main.async { deleteFromStore() }
            }
        } else {
            deleteFromStore()
        }
    }
}
