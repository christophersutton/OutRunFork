//
//  MoveTheme.swift
//
//  Move Run
//
//  The Move identity: one near-black ink ground, neutral grays and a single accent. Orange is Run's own
//  signal; the picker offers the palette all Move apps share, and the home screen icon follows it through
//  the AppIcon-<accent> alternate icons in the asset catalog. Inter Tight carries titles and every big
//  number; it ships as data assets and is registered at launch.
//

import CoreText
import SwiftUI
import UIKit

enum MoveAccent: String, CaseIterable, Identifiable {
    case orange, green, moonlight, teal, blue, purple, pink, red

    /// Run's own signal color.
    static let `default`: MoveAccent = .orange

    var id: String { rawValue }

    /// Name shown in the picker. Color names are kept in English like the rest of the Move palette.
    var displayName: String {
        switch self {
        case .orange: return "Orange"
        case .green: return "Green"
        case .moonlight: return "Moonlight"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        }
    }

    /// Fill color: buttons, routes, selected states. Text on it is always ink.
    var fillHex: UInt32 {
        switch self {
        case .orange: return 0xFF8A00
        case .green: return 0x22C55E
        case .moonlight: return 0xE3C78E
        case .teal: return 0x2DD4BF
        case .blue: return 0x60A5FA
        case .purple: return 0xA78BFA
        case .pink: return 0xF472B6
        case .red: return 0xF87171
        }
    }

    /// Darker shade for accent-colored text on a light background.
    var textOnLightHex: UInt32 {
        switch self {
        case .orange: return 0xC2410C
        case .green: return 0x15803D
        case .moonlight: return 0x8A6A2E
        case .teal: return 0x0F766E
        case .blue: return 0x1D4ED8
        case .purple: return 0x6D28D9
        case .pink: return 0xBE185D
        case .red: return 0xB91C1C
        }
    }

    var fill: UIColor { UIColor(moveHex: fillHex) }

    /// Accent-colored text: the fill in dark mode, the darker shade in light mode.
    var label: UIColor {
        let dark = fill
        let light = UIColor(moveHex: textOnLightHex)
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// `nil` selects the primary (orange) app icon.
    var alternateIconName: String? {
        self == .default ? nil : "AppIcon-\(rawValue)"
    }
}

enum MoveAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum MoveTheme {

    static let accentKey = "move.accentColor"
    static let appearanceKey = "move.appearance"

    /// Ink: the color text sits in on every accent fill.
    static let ink = UIColor(moveHex: 0x0B0B0C)

    static var accent: MoveAccent {
        MoveAccent(rawValue: UserDefaults.standard.string(forKey: accentKey) ?? "") ?? .default
    }

    static var appearance: MoveAppearance {
        MoveAppearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .system
    }

    /// Switches the home screen icon to match `accent`. iOS confirms the change with its own alert.
    @MainActor
    static func applyAppIcon(for accent: MoveAccent) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons,
              application.alternateIconName != accent.alternateIconName else { return }
        application.setAlternateIconName(accent.alternateIconName) { error in
            if let error {
                print("[MoveTheme] Could not change the app icon:", error.localizedDescription)
            }
        }
    }

    // MARK: Fonts

    enum FontName {
        static let bold = "InterTight-Bold"
        static let extraBold = "InterTight-ExtraBold"
        static let black = "InterTight-Black"
    }

    /// Registers the bundled Inter Tight data assets with Core Text. Safe to call more than once.
    static func registerFonts() {
        for name in [FontName.bold, FontName.extraBold, FontName.black] {
            guard UIFont(name: name, size: 12) == nil,
                  let asset = NSDataAsset(name: name),
                  let provider = CGDataProvider(data: asset.data as CFData),
                  let font = CGFont(provider) else { continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterGraphicsFont(font, &error) {
                print("[MoveTheme] Could not register \(name):", error?.takeRetainedValue().localizedDescription ?? "unknown error")
            }
        }
    }
}

extension UIColor {
    /// Destructive actions and errors. Stays red whatever the accent is.
    static let moveError = UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(moveHex: 0xF87171) : UIColor(moveHex: 0xDC2626)
    }

    convenience init(moveHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension UIFont {

    /// Inter Tight with tabular figures, scaled with Dynamic Type relative to `textStyle`.
    /// Falls back to the heavy system font if the bundled font is unavailable.
    static func moveFont(_ name: String = MoveTheme.FontName.extraBold, size: CGFloat, relativeTo textStyle: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        let tabular = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]
        ])
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: UIFont(descriptor: tabular, size: size))
    }

    /// Stat readouts: pace, distance, durations.
    static func moveStat(size: CGFloat = 28) -> UIFont {
        moveFont(size: size, relativeTo: .title1)
    }

    /// Field labels above stats; pair with uppercase text and +10% tracking (see `UILabel.applyMoveLabelStyle`).
    static var moveLabel: UIFont {
        .preferredFont(forTextStyle: .footnote, weight: .semibold)
    }
}

extension UILabel {
    /// Uppercase, +10% tracking, muted: the Move label style.
    func applyMoveLabelStyle() {
        font = .moveLabel
        textColor = .secondaryColor
        adjustsFontForContentSizeCategory = true
        guard let text else { return }
        attributedText = NSAttributedString(string: text.uppercased(), attributes: [.kern: font.pointSize * 0.1])
    }
}
