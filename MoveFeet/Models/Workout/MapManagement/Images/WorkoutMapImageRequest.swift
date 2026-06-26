//
//  WorkoutMapImageRequest.swift
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

class WorkoutMapImageRequest: Equatable {
    
    let workoutUUID: UUID?
    let size: WorkoutMapImageSize
    let pointSize: CGSize
    let scale: CGFloat
    let usesDarkAppearance: Bool
    let highPriority: Bool
    var completion: (Bool, UIImage?) -> Void
    
    func cacheIdentifier(forDarkAppearance usesDarkAppearance: Bool? = nil) -> String? {
        guard let uuid = workoutUUID else {
            return nil
        }
        let id = uuid.uuidString
        let size = self.size.identifier
        let pointSize = Self.identifierComponent(for: self.pointSize)
        let scale = Self.identifierComponent(for: self.scale)
        let appearance = (usesDarkAppearance ?? self.usesDarkAppearance) ? "dark" : "light"
        return id + "_" + size + "_" + pointSize + "_@" + scale + "x_" + appearance
    }
    
    init(
        workoutUUID: UUID?,
        size: WorkoutMapImageSize,
        pointSize: CGSize,
        scale: CGFloat,
        usesDarkAppearance: Bool = Config.isDarkModeEnabled,
        highPriority: Bool = false,
        completion: @escaping (Bool, UIImage?) -> Void
    ) {
        self.workoutUUID = workoutUUID
        self.size = size
        self.pointSize = pointSize
        self.scale = scale
        self.usesDarkAppearance = usesDarkAppearance
        self.highPriority = highPriority
        self.completion = completion
    }
    
    static func == (lhs: WorkoutMapImageRequest, rhs: WorkoutMapImageRequest) -> Bool {
        return lhs.workoutUUID == rhs.workoutUUID &&
            lhs.size == rhs.size &&
            lhs.pointSize == rhs.pointSize &&
            lhs.scale == rhs.scale &&
            lhs.usesDarkAppearance == rhs.usesDarkAppearance
    }

    private static func identifierComponent(for size: CGSize) -> String {
        return identifierComponent(for: size.width) + "x" + identifierComponent(for: size.height)
    }

    private static func identifierComponent(for value: CGFloat) -> String {
        let rounded = value.rounded()
        if value == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.3f", Double(value))
    }
}
