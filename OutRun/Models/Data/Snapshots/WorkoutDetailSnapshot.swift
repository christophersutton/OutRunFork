//
//  WorkoutDetailSnapshot.swift
//
//  OutRun
//
//  An immutable, value-type snapshot of everything the workout *detail* screen renders: the scalar stats,
//  the route as plain `[CLLocationCoordinate2D]`, and the chart series as plain `[WorkoutChartPoint]`
//  value arrays (NOT CoreStore samples).
//
//  Like `WorkoutSnapshot`, this exists to honour CoreStore's threading model: `Workout` and its route /
//  heart-rate samples are thread-confined, and reading them off their designated queue traps at runtime.
//  This snapshot is built ONCE, inside a `dataStack.perform` transaction (see
//  `DataManager.workoutDetailSnapshot(for:)`), reading the RAW `_x.value` accessors directly on the
//  transaction queue — never the public scalar accessors, which marshal every read back to main via
//  `threadSafeSyncReturn` (a per-read main-queue hop, and a deadlock risk from inside a transaction).
//  Thereafter it is a plain value the SwiftUI layer can hold safely.
//
//  All numeric values are kept in raw SI / metric units (metres, m/s, kcal, bpm, seconds); the view layer
//  converts and formats for display using the app's existing formatting helpers.
//

import Foundation
import CoreLocation

/// A single point in a workout chart series. `x` is seconds since the workout's start; `y` is the metric
/// value in SI / metric units (metres for altitude, m/s for speed, bpm for heart rate).
struct WorkoutChartPoint: Hashable {
    let x: Double
    let y: Double
}

struct WorkoutDetailSnapshot: Identifiable {

    // MARK: Identity & scalar fields (raw, as stored)

    let id: UUID
    let workoutType: Workout.WorkoutType
    let distance: Double                 // metres
    let startDate: Date
    let endDate: Date
    let activeDuration: TimeInterval     // seconds
    let pauseDuration: TimeInterval      // seconds
    let steps: Int?
    let burnedEnergy: Double?            // kcal
    let ascend: Double                   // metres
    let descend: Double                  // metres
    let isRace: Bool
    let comment: String?
    let isUserModified: Bool
    let healthKitUUID: UUID?
    let dayIdentifier: String
    let hasPauses: Bool

    // MARK: Derived scalar stats (computed once, raw units)

    let averageSpeed: Double?            // m/s — distance / activeDuration
    let topSpeed: Double?                // m/s — fastest valid route sample
    let averageHeartRate: Int?           // bpm

    // MARK: Route & chart series (plain values, no CoreStore objects)

    let routeCoordinates: [CLLocationCoordinate2D]
    let altitudeSeries: [WorkoutChartPoint]     // y = metres
    let speedSeries: [WorkoutChartPoint]        // y = m/s
    let heartRateSeries: [WorkoutChartPoint]    // y = bpm

    // MARK: Convenience capability flags (derive section visibility)

    var hasRouteData: Bool { !routeCoordinates.isEmpty }
    var hasAltitudeData: Bool { !altitudeSeries.isEmpty }
    var hasSpeedData: Bool { !speedSeries.isEmpty }
    var hasHeartRateData: Bool { !heartRateSeries.isEmpty }
    var hasSteps: Bool { steps != nil }
    var hasEnergy: Bool { burnedEnergy != nil }

    /// Builds a detail snapshot from a CoreStore `Workout`.
    ///
    /// MUST be called on the workout's designated queue — for this codebase that means inside a
    /// `dataStack.perform` transaction with a transaction-bound `Workout` (see
    /// `DataManager.workoutDetailSnapshot(for:)`). It deliberately uses the RAW `_x.value` accessors so it
    /// stays on the current (transaction) queue and never marshals to main.
    init(_ workout: Workout) {

        self.id = workout._uuid.value ?? UUID()
        self.workoutType = workout._workoutType.value
        self.distance = workout._distance.value
        let start = workout._startDate.value
        self.startDate = start
        self.endDate = workout._endDate.value
        let active = workout._activeDuration.value
        self.activeDuration = active
        self.pauseDuration = workout._pauseDuration.value
        self.steps = workout._steps.value
        self.burnedEnergy = workout._burnedEnergy.value
        self.ascend = workout._ascend.value
        self.descend = workout._descend.value
        self.isRace = workout._isRace.value
        self.comment = workout._comment.value
        self.isUserModified = workout._isUserModified.value
        self.healthKitUUID = workout._healthKitUUID.value
        self.dayIdentifier = workout._dayIdentifier.value

        // Relationship reads — queue-confined; valid here because we are on the transaction queue.
        let routeSamples = workout._routeData.value
        let heartRateSamples = workout._heartRates.value
        self.hasPauses = !workout._pauses.value.isEmpty

        // Route coordinates. Route sample lat/lon default to the -1 "unset" sentinel; skip those.
        self.routeCoordinates = routeSamples.compactMap { sample -> CLLocationCoordinate2D? in
            let lat = sample._latitude.value
            let lon = sample._longitude.value
            guard lat != -1, lon != -1 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Chart series. x = seconds since start (start.distance(to: timestamp) == timestamp - start, so it
        // increases over the workout). The legacy WorkoutStats used the inverse (timestamp.distance(to:
        // start)), which produced negative/decreasing x — a latent bug masked by the old charts never
        // being fed data. Altitude/speed carry -1 sentinels for unset samples; skip them.
        self.altitudeSeries = routeSamples.compactMap { sample -> WorkoutChartPoint? in
            let altitude = sample._altitude.value
            guard altitude != -1 else { return nil }
            return WorkoutChartPoint(x: start.distance(to: sample._timestamp.value), y: altitude)
        }
        self.speedSeries = routeSamples.compactMap { sample -> WorkoutChartPoint? in
            let speed = sample._speed.value
            guard speed >= 0 else { return nil }
            return WorkoutChartPoint(x: start.distance(to: sample._timestamp.value), y: speed)
        }
        self.heartRateSeries = heartRateSamples.map { sample -> WorkoutChartPoint in
            WorkoutChartPoint(x: start.distance(to: sample._timestamp.value), y: Double(sample._heartRate.value))
        }

        // Derived scalars.
        self.averageSpeed = active > 0 ? (workout._distance.value / active) : nil
        let validSpeeds = routeSamples.map { $0._speed.value }.filter { $0 >= 0 }
        self.topSpeed = validSpeeds.max()
        let heartRates = heartRateSamples.map { $0._heartRate.value }
        self.averageHeartRate = heartRates.isEmpty ? nil : (heartRates.reduce(0, +) / heartRates.count)
    }
}
