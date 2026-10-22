import SwiftUI
import UIKit
import XCTest
@testable import MoveFeet

final class HomeChromeAppearanceTests: XCTestCase {

    func testNativeTabAssetsLoadAsTemplatesWithoutLegacyUIImageHelpers() throws {
        // The iOS 26 Tab initializers load asset names directly, bypassing UIImage.tabbar*.
        for name in ["timeline 23px", "settings 23px"] {
            let image = try XCTUnwrap(UIImage(named: name), "Missing native tab asset: \(name)")
            XCTAssertEqual(image.renderingMode, .alwaysTemplate, "\(name) must follow native tab tint")
        }
    }

    func testSharedNavigationColorsRemainDynamicAcrossAppearanceChanges() {
        // Reuse these same instances through light -> dark -> light. Static UIColor storage
        // must retain the asset's dynamic behavior rather than a launch-time resolution.
        let foreground = UIColor.primaryColor
        let background = UIColor.backgroundColor
        var luminances: [Double] = []
        for style in [UIUserInterfaceStyle.light, .dark, .light] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let text = luminance(foreground.resolvedColor(with: traits))
            let surface = luminance(background.resolvedColor(with: traits))
            XCTAssertGreaterThanOrEqual(contrast(text, surface), 4.5, "Unreadable navigation text in \(style)")
            if style == .dark {
                XCTAssertGreaterThan(text, surface)
            } else {
                XCTAssertLessThan(text, surface)
            }
            luminances.append(text)
        }
        XCTAssertEqual(luminances[0], luminances[2], accuracy: 0.001)
        XCTAssertNotEqual(luminances[0], luminances[1])
    }

    func testSwiftUINavigationColorBridgeFollowsEnvironmentAppearance() {
        let foreground = Color.orPrimary
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark

        // Exercise the actual SwiftUI bridge used by the home sort button, independently
        // of the process's initial UIKit appearance.
        let lightValue = foreground.resolve(in: light)
        let darkValue = foreground.resolve(in: dark)
        for component in [lightValue.red, lightValue.green, lightValue.blue] {
            XCTAssertEqual(component, 0, accuracy: 0.001)
        }
        for component in [darkValue.red, darkValue.green, darkValue.blue] {
            XCTAssertEqual(component, 1, accuracy: 0.001)
        }
        XCTAssertEqual(foreground.resolve(in: light), lightValue)
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
        let linear = [red, green, blue].map { component -> Double in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    func testMoveAccentLabelsAndFilledButtonsRemainReadableAcrossAppearances() {
        for accent in MoveAccent.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                let label = luminance(accent.label.resolvedColor(with: traits))
                for surface in [UIColor.backgroundColor, .foregroundColor] {
                    XCTAssertGreaterThanOrEqual(
                        contrast(label, luminance(surface.resolvedColor(with: traits))), 4.5,
                        "Unreadable \(accent) label in \(style)"
                    )
                }
                XCTAssertGreaterThanOrEqual(contrast(luminance(MoveTheme.ink), luminance(accent.fill)), 4.5)
                XCTAssertGreaterThanOrEqual(
                    contrast(luminance(UIColor.moveError.resolvedColor(with: traits)),
                             luminance(UIColor.foregroundColor.resolvedColor(with: traits))), 4.5
                )
            }
        }
    }

    func testLiveActivityAccentCanChangeWithoutChangingItsInitialAttributes() throws {
        let attributes = WorkoutActivityAttributes(accentHex: 0xFF8A00)
        var state = WorkoutActivityAttributes.ContentState(
            timerStart: Date(timeIntervalSince1970: 100), pauseTime: nil,
            isPaused: false, distanceText: "1 km", accentHex: 0x2DD4BF
        )
        let initial = state
        state.accentHex = 0xA78BFA
        XCTAssertNotEqual(initial, state)
        XCTAssertEqual(attributes.accentHex, 0xFF8A00)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: data), state)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "accentHex")
        let legacyState = try JSONDecoder().decode(
            WorkoutActivityAttributes.ContentState.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(legacyState.accentHex)
        XCTAssertEqual(legacyState.accentHex ?? attributes.accentHex, 0xFF8A00)
    }

    private func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
