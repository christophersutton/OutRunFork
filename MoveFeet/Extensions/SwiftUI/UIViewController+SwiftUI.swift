//
//  UIViewController+SwiftUI.swift
//
//  OutRun
//
//  The bridge that lets the existing UIKit shell host SwiftUI screens during the migration. Every leaf
//  SwiftUI screen is presented/pushed from UIKit through these helpers; the SwiftUI side dismisses itself
//  via @Environment(\.dismiss), which drives the hosting controller.
//

import UIKit
import SwiftUI

extension UIViewController {

    /// Presents a SwiftUI view modally, wrapped in a `UIHostingController`.
    @discardableResult
    func presentSwiftUI<Content: View>(
        _ view: Content,
        animated: Bool = true,
        modalPresentationStyle: UIModalPresentationStyle = .automatic,
        modalTransitionStyle: UIModalTransitionStyle = .coverVertical
    ) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = modalPresentationStyle
        host.modalTransitionStyle = modalTransitionStyle
        if modalPresentationStyle == .overFullScreen || modalPresentationStyle == .overCurrentContext {
            host.view.backgroundColor = .clear
        }
        present(host, animated: animated)
        return host
    }

    /// Pushes a SwiftUI view onto the current navigation stack, wrapped in a `UIHostingController`.
    @discardableResult
    func pushSwiftUI<Content: View>(_ view: Content, animated: Bool = true) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: view)
        (self as? UINavigationController ?? navigationController)?.pushViewController(host, animated: animated)
        return host
    }
}
