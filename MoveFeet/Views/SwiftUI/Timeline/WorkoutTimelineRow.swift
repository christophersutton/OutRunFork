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
                .fill(Color.orLine)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            if showRing {
                // The Move ring: the same stroke-to-radius ratio as the family's "o".
                Circle()
                    .fill(Color.orBackground)
                    .overlay(Circle().strokeBorder(Color.orAccent, lineWidth: 6))
                    .frame(width: 22, height: 22)
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
                .moveLabelStyle()
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
                Text(snapshot.workoutType.description)
                    .moveLabelStyle()
                WorkoutStatText.bigStat(Self.distanceString(snapshot), style: .largeTitle)
                    .foregroundStyle(Color.orPrimary)
                WorkoutStatText.bigStat(Self.durationString(snapshot), style: .title3)
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if snapshot.isRace {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.orAccent, lineWidth: 2)
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
        let roundedSeconds = (max(snapshot.activeDuration, 0) / 60).rounded() * 60
        return CustomMeasurementFormatting.string(
            forMeasurement: NSMeasurement(doubleValue: roundedSeconds, unit: UnitDuration.seconds),
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
    /// Renders a "number unit" string as Inter Tight tabular digits with the unit set smaller and muted beside
    /// them (the Move stat style). Numeric tokens get the stat face; the rest is the unit.
    ///
    /// Splits on any Unicode whitespace (so locales that separate the number and unit — or group digits — with a
    /// no-break/narrow space, e.g. fr_FR's U+202F, still split correctly) and treats a token as numeric if it
    /// contains any digit (so grouped numbers like "1,234" render upright). This is a deliberate improvement over
    /// the legacy split-on-ASCII-space + `NumberFormatter` parse, which lost the styling in those locales.
    static func bigStat(_ string: String, style: Font.TextStyle) -> Text {
        let size = statSize(for: style)
        let base = Font.moveStat(size, relativeTo: style)
        let unit = Font.custom(MoveTheme.FontName.bold, size: (size * 0.5).rounded(), relativeTo: style)
        let tokens = string.split(whereSeparator: \.isWhitespace).map(String.init)

        var text = Text("")
        for (index, token) in tokens.enumerated() {
            let isNumber = token.contains(where: \.isNumber)
            let piece = isNumber
                ? Text(token).font(base)
                : Text(token).font(unit).foregroundStyle(Color.orSecondary)
            if index == 0 {
                text = piece
            } else {
                text = text + Text(" ").font(base) + piece
            }
        }
        return text
    }

    /// Point size for a stat set at a text style (Display, Stat and smaller stat steps).
    static func statSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 24
        case .title3: return 20
        default: return 17
        }
    }

    /// The hero number: Inter Tight Black at Display size, unit beside it in muted Inter Tight Bold.
    static func hero(_ string: String) -> Text {
        let tokens = string.split(whereSeparator: \.isWhitespace).map(String.init)
        var text = Text("")
        for (index, token) in tokens.enumerated() {
            let piece = token.contains(where: \.isNumber)
                ? Text(token).font(.moveDisplay)
                : Text(token).font(.custom(MoveTheme.FontName.bold, size: 22, relativeTo: .title2)).foregroundStyle(Color.orSecondary)
            text = index == 0 ? piece : text + Text(" ").font(.moveDisplay) + piece
        }
        return text
    }
}
