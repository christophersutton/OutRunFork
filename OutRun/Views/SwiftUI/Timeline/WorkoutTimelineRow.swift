//
//  WorkoutTimelineRow.swift
//
//  OutRun
//
//  The SwiftUI timeline row + its supporting pieces (the left timeline gutter with the accent line/ring, the
//  workout card, the async route thumbnail, and the "big number / small-caps unit" stat formatting). Rows are
//  driven entirely by an immutable `WorkoutSnapshot` — never a live CoreStore `Workout`.
//

import SwiftUI

// MARK: - Timeline gutter (continuous accent line + per-card ring)

/// The fixed-width left column that draws the vertical timeline line and, for workout rows, the ring that
/// "punches" the line. Stacking gutters with no inter-row spacing makes the line continuous.
struct TimelineGutter: View {
    var showRing: Bool = false

    static let width: CGFloat = 40

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.orAccent.opacity(0.25))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            if showRing {
                Circle()
                    .fill(Color.orBackground)
                    .overlay(Circle().strokeBorder(Color.orAccent, lineWidth: 4))
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: Self.width)
    }
}

// MARK: - Day header row

struct TimelineDayHeader: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            TimelineGutter()
            Text(text)
                .font(.system(.body, weight: .bold))
                .foregroundStyle(Color.orSecondary)
            Spacer(minLength: 0)
        }
        .frame(height: 40)
    }
}

// MARK: - Workout row (gutter + card)

struct WorkoutTimelineRow: View {
    let snapshot: WorkoutSnapshot
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale

    @State private var routeImage: UIImage?
    @State private var routeThumbnailSize: CGSize = .zero
    @State private var requestedRouteThumbnailSize: CGSize?

    var body: some View {
        HStack(spacing: 0) {
            TimelineGutter(showRing: true)
            card
                .padding(.trailing, 10)
                .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var card: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.workoutType.description.uppercased())
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Color.orSecondary)
                WorkoutStatText.bigStat(Self.distanceString(snapshot), size: 36)
                    .foregroundStyle(Color.orPrimary)
                WorkoutStatText.bigStat(Self.durationString(snapshot), size: 24)
                    .foregroundStyle(Color.orSecondary)
            }
            .padding(.leading, 20)
            .padding(.vertical, 14)

            Spacer(minLength: 12)

            if let routeImage {
                Image(uiImage: routeImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: routeThumbnailSize.width, height: routeThumbnailSize.height)
                    .clipped()
            }
        }
        .frame(minHeight: routeImage == nil ? 0 : 120)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orForeground)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            if snapshot.isRace {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color.orAccent.opacity(0.5), lineWidth: 4)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            let thumbnailWidth = max(newSize.width / 2, 0)
            routeThumbnailSize = CGSize(width: thumbnailWidth, height: 120)
            loadRouteImageIfNeeded()
        }
        .onAppear(perform: loadRouteImageIfNeeded)
    }

    /// Distance in the user's unit with a single decimal place (e.g. "5.2 km").
    static func distanceString(_ snapshot: WorkoutSnapshot) -> String {
        CustomMeasurementFormatting.string(
            forMeasurement: NSMeasurement(doubleValue: snapshot.distance, unit: UnitLength.meters),
            type: .distance,
            rounding: .oneDigit
        )
    }

    /// Active duration in natural scale (e.g. "2 min", "1 hr 5 min").
    static func durationString(_ snapshot: WorkoutSnapshot) -> String {
        CustomMeasurementFormatting.string(
            forMeasurement: NSMeasurement(doubleValue: snapshot.activeDuration, unit: UnitDuration.seconds),
            type: .time,
            rounding: .wholeNumbers
        )
    }

    private func loadRouteImageIfNeeded() {
        guard snapshot.hasRouteData else { return }

        let requestedSize = routeThumbnailSize
        guard requestedSize.width > 0, requestedSize.height > 0 else { return }
        guard requestedRouteThumbnailSize != requestedSize else { return }
        requestedRouteThumbnailSize = requestedSize

        let request = WorkoutMapImageRequest(
            workoutUUID: snapshot.id,
            size: .list,
            pointSize: requestedSize,
            scale: displayScale
        ) { success, image in
            guard success else { return }
            guard let image else { return }
            DispatchQueue.main.async {
                guard self.routeThumbnailSize == requestedSize else { return }
                self.routeImage = image
            }
        }
        WorkoutMapImageManager.execute(request)
    }
}

// MARK: - Big-number stat text

enum WorkoutStatText {
    /// Renders a "number unit" string as large normal digits + lowercase-small-caps unit at the same size
    /// (matching the legacy `attributedStringWithBigNumbers`). Numeric tokens stay upright; the rest is small-caps.
    ///
    /// Splits on any Unicode whitespace (so locales that separate the number and unit — or group digits — with a
    /// no-break/narrow space, e.g. fr_FR's U+202F, still split correctly) and treats a token as numeric if it
    /// contains any digit (so grouped numbers like "1,234" render upright). This is a deliberate improvement over
    /// the legacy split-on-ASCII-space + `NumberFormatter` parse, which lost the styling in those locales.
    static func bigStat(_ string: String, size: CGFloat) -> Text {
        let base = Font.system(size: size, weight: .bold)
        let smallCaps = base.lowercaseSmallCaps()
        let tokens = string.split(whereSeparator: \.isWhitespace).map(String.init)

        var text = Text("")
        for (index, token) in tokens.enumerated() {
            let isNumber = token.contains(where: \.isNumber)
            let piece = Text(token).font(isNumber ? base : smallCaps)
            if index == 0 {
                text = piece
            } else {
                text = text + Text(" ").font(base) + piece
            }
        }
        return text
    }
}
