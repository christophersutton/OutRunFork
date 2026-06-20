//
//  UIApplication+Scene.swift
//
//  OutRun
//
//  Scene-aware replacements for the deprecated `UIApplication.shared.keyWindow`. Under the SwiftUI `App`
//  lifecycle the app is multi-scene-capable, so window lookups must go through the connected window scenes
//  rather than the legacy app-level key window. These helpers resolve the foreground-active scene's key
//  window and the front-most presented view controller, which is how UIKit screens (live recording, the
//  full-screen route map, share sheets, permission alerts) are bridged from the SwiftUI shell.
//

import UIKit

extension UIApplication {

    /// The key window of the foreground-active window scene (a scene-aware replacement for the deprecated
    /// `keyWindow`). Falls back to any connected scene's key/first window if none is foreground-active yet.
    var activeKeyWindow: UIWindow? {
        let windowScenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first
        return scene?.keyWindow
            ?? scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
    }

    /// The front-most presented view controller, used as a presenter when bridging UIKit modals from SwiftUI.
    var topMostViewController: UIViewController? {
        var top = activeKeyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
