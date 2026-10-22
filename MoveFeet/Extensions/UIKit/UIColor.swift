//
//  UIColor.swift
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

import UIKit

extension UIColor {
    
    /// The person's chosen Move accent (orange by default). Resolved on every draw, so views pick up a new
    /// choice the next time they render.
    static var accentColor: UIColor { UIColor { _ in MoveTheme.accent.fill } }
    /// Pressed/secondary variant of the accent. In the Move identity there is no second hue, so it is the
    /// same signal color.
    static var accentColorSwapped: UIColor { accentColor }
    /// Accent-colored text: darker shade on light backgrounds.
    static var accentLabelColor: UIColor { UIColor { traits in MoveTheme.accent.label.resolvedColor(with: traits) } }
    static let primaryColor = UIColor(named: "primaryColor") ?? .black
    static let secondaryColor = UIColor(named: "secondaryColor") ?? UIColor(white: 118/255, alpha: 1)
    static let backgroundColor = UIColor(named: "backgroundColor") ??  UIColor.white
    static let foregroundColor = UIColor(named: "foregroundColor") ?? UIColor(white: 248/255, alpha: 1)
    static let lineColor = UIColor(named: "lineColor") ?? UIColor(white: 0.5, alpha: 0.25)
    static let tableViewSeparator = lineColor
    
}
