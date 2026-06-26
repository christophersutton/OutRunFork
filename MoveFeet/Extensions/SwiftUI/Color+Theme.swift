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
}
