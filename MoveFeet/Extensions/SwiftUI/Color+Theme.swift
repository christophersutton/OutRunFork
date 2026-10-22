//
//  Color+Theme.swift
//
//  OutRun
//
//  SwiftUI mirror of the app's UIColor theme (see Extensions/UIKit/UIColor.swift). Bridging through the
//  existing UIColor accessors reuses the named asset colours + their fallbacks, and the `or` prefix avoids
//  clashing with SwiftUI built-ins or generated asset symbols.
//

import SwiftUI

extension Color {
    static var orAccent: Color { Color(uiColor: .accentColor) }
    static var orAccentSwapped: Color { Color(uiColor: .accentColorSwapped) }
    static var orPrimary: Color { Color(uiColor: .primaryColor) }
    static var orSecondary: Color { Color(uiColor: .secondaryColor) }
    static var orBackground: Color { Color(uiColor: .backgroundColor) }
    static var orForeground: Color { Color(uiColor: .foregroundColor) }
    static var orAccentLabel: Color { Color(uiColor: .accentLabelColor) }
    static var orLine: Color { Color(uiColor: .lineColor) }
    /// Text on an accent fill: always ink.
    static var orOnAccent: Color { Color(uiColor: MoveTheme.ink) }
}

// MARK: - Move type

extension Font {
    /// Large navigation and screen titles (Inter Tight 34 / 800).
    static var moveTitle: Font { .custom(MoveTheme.FontName.extraBold, size: 34, relativeTo: .largeTitle) }
    /// Card and section titles (Inter Tight 22 / 800).
    static var moveHeadline: Font { .custom(MoveTheme.FontName.extraBold, size: 22, relativeTo: .title2) }
    /// Hero numbers (Inter Tight 56 / 900).
    static var moveDisplay: Font { .custom(MoveTheme.FontName.black, size: 56, relativeTo: .largeTitle).monospacedDigit() }
    /// Weights, pace, distance and durations (Inter Tight 800, tabular figures).
    static func moveStat(_ size: CGFloat = 28, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(MoveTheme.FontName.extraBold, size: size, relativeTo: style).monospacedDigit()
    }
    /// Field labels and section eyebrows; use with `.moveLabelStyle()`.
    static var moveLabel: Font { .system(.footnote, weight: .semibold) }
}

extension View {
    /// A Move card: tile ground, radius 20, no border or shadow.
    func moveCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.orForeground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Uppercase, +10% tracking, muted: the Move label style.
    func moveLabelStyle() -> some View {
        font(.moveLabel)
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(Color.orSecondary)
    }
}

// MARK: - Buttons

/// Accent fill, ink text, 52pt tall, radius 14: the one primary action on a screen.
struct MovePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Color.orOnAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.orAccent.opacity(isEnabled ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Tile fill, paper text: secondary actions.
struct MoveSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Color.orPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.orForeground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == MovePrimaryButtonStyle {
    static var movePrimary: MovePrimaryButtonStyle { MovePrimaryButtonStyle() }
}

extension ButtonStyle where Self == MoveSecondaryButtonStyle {
    static var moveSecondary: MoveSecondaryButtonStyle { MoveSecondaryButtonStyle() }
}

// MARK: - Mark

/// The Move Run glyph: the move ring, smaller and moving, with three speed lines. Drawn on the
/// 168-unit grid the family's marks share.
struct MoveRunMark: View {
    var color: Color = .orAccent

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 168
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (size.width - 168 * unit) / 2 + x * unit, y: (size.height - 168 * unit) / 2 + y * unit)
            }
            let center = point(104, 84)
            let ring = Path(ellipseIn: CGRect(x: center.x - 32 * unit, y: center.y - 32 * unit, width: 64 * unit, height: 64 * unit))
            context.stroke(ring, with: .color(color), lineWidth: 24 * unit)
            var lines = Path()
            for (start, y) in [(CGFloat(32), CGFloat(62)), (24, 84), (32, 106)] {
                lines.move(to: point(start, y))
                lines.addLine(to: point(52, y))
            }
            context.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: 12 * unit, lineCap: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
