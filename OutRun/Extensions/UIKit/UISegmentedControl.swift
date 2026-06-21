//
//  UISegmentedControl.swift
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

extension UISegmentedControl {

    private static var dynamicTypeObserverKey: UInt8 = 0

    func styleLikeIOS12() {
        if #available(iOS 13, *) {
            let tintColorImage = UIImage(color: tintColor)
            // Must set the background image for normal to something (even clear) else the rest won't work
            setBackgroundImage(UIImage(color: backgroundColor ?? .clear), for: .normal, barMetrics: .default)
            setBackgroundImage(tintColorImage, for: .selected, barMetrics: .default)
            setBackgroundImage(UIImage(color: tintColor.withAlphaComponent(0.2)), for: .highlighted, barMetrics: .default)
            setBackgroundImage(tintColorImage, for: [.highlighted, .selected], barMetrics: .default)
            refreshIOS12DynamicTypeTitleAttributes()
            observeDynamicTypeChangesForIOS12Style()
            setDividerImage(tintColorImage, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
            layer.borderWidth = 1
            layer.borderColor = tintColor.cgColor
        }
    }

    func refreshIOS12DynamicTypeTitleAttributes() {
        let titleFont = UIFont.preferredFont(forTextStyle: .caption1)
        setTitleTextAttributes([.foregroundColor: tintColor as Any, NSAttributedString.Key.font: titleFont], for: .normal)
        setTitleTextAttributes([.foregroundColor: UIColor.white, NSAttributedString.Key.font: titleFont], for: .selected)
    }

    /// `setTitleTextAttributes(_:for:)` snapshots the font once, so — unlike a label with
    /// `adjustsFontForContentSizeCategory` — the iOS-12-style title does NOT re-scale when the user changes
    /// Dynamic Type while the app is running. Re-apply the attributes on every content-size-category change so
    /// the title keeps tracking the preferred font. The observer's lifetime is tied to this control via an
    /// associated `DynamicTypeTitleObserver` (extensions can't add stored properties or `deinit`), which removes
    /// the notification registration when the control is deallocated.
    private func observeDynamicTypeChangesForIOS12Style() {
        guard objc_getAssociatedObject(self, &Self.dynamicTypeObserverKey) == nil else { return }
        let observer = DynamicTypeTitleObserver { [weak self] in
            self?.refreshIOS12DynamicTypeTitleAttributes()
        }
        objc_setAssociatedObject(self, &Self.dynamicTypeObserverKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

}

/// Owns a `UIContentSizeCategory.didChangeNotification` registration and tears it down on `deinit`, so the
/// registration lives exactly as long as the object it is associated with.
private final class DynamicTypeTitleObserver {
    private var token: NSObjectProtocol?

    init(onChange: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in onChange() }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
