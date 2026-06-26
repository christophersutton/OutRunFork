//
//  AppDelegate.swift
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

//
//  As of the SwiftUI-`App` shell flip (Phase 6), the entry point is `OutRunApp` (a SwiftUI `App`). This
//  AppDelegate is retained only via `@UIApplicationDelegateAdaptor` so a couple of app-level concerns keep a
//  home: the `lastVersion` preference (drives the post-update changelog) and the launch-time permission
//  re-check. Window creation, root-view-controller selection, and the background/foreground render-suspend
//  hooks moved into `OutRunApp`/`RootView`/`RootRouter` and the SwiftUI `scenePhase`.
//

import UIKit
import Foundation
import CoreLocation

class AppDelegate: UIResponder, UIApplicationDelegate {

    static let lastVersion = UserPreference.Optional<String>(key: "lastVersion", initialValue: "1.0")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    /// Runs the launch-time permission re-check (location → motion → health), presenting any required alerts
    /// on the supplied presenter. Side-effect-free apart from the presented alerts; always calls `completion`
    /// on the main queue once the chain finishes. Ported verbatim from the pre-Phase-6 window-rooting flow,
    /// now invoked by `RootRouter` with the SwiftUI hosting controller as the presenter.
    static func checkPermissionStatus(controller: UIViewController, completion: (() -> Void)? = nil) {

        let safeCompletion: () -> Void = {
            DispatchQueue.main.async {
                completion?()
            }
        }

        if UserPreferences.isSetUp.value {

            func checkHealthPermission() {
                if UserPreferences.synchronizeWorkoutsWithAppleHealth.value || UserPreferences.synchronizeWeightWithAppleHealth.value {
                    PermissionManager.standard.checkHealthPermission { (success) in
                        if !success {
                            DispatchQueue.main.async {
                                controller.displayError(withMessage: LS["Setup.Permission.AppleHealth.Error"], dismissAction: { _ in
                                    safeCompletion()
                                })
                            }
                        } else {
                            safeCompletion()
                        }
                    }
                } else {
                    safeCompletion()
                }
            }

            func checkMotionPermission() {
                PermissionManager.standard.checkMotionPermission { (success) in
                    if !success {
                        DispatchQueue.main.async {
                            controller.displayOpenSettingsAlert(
                                withTitle: LS["Error"],
                                message: LS["Setup.Permission.Motion.Error"],
                                dismissAction: {
                                    checkHealthPermission()
                                }
                            )
                        }
                    } else {
                        checkHealthPermission()
                    }
                }
            }

            PermissionManager.standard.checkLocationPermission { (status) in
                switch status {
                case .granted:
                    checkMotionPermission()
                    break
                case .restricted:
                    DispatchQueue.main.async {
                        controller.displayOpenSettingsAlert(
                            withTitle: LS["Setup.Permission.Location.Restricted.Title"],
                            message: LS["Setup.Permission.Location.Restricted.Message"],
                            dismissAction: {
                                checkMotionPermission()
                            }
                        )
                    }
                default:
                    DispatchQueue.main.async {
                        controller.displayOpenSettingsAlert(
                            withTitle: LS["Error"],
                            message: LS["Setup.Permission.Location.Error"],
                            dismissAction: {
                                checkMotionPermission()
                            }
                        )
                    }
                }
            }

        } else {
            safeCompletion()
        }
    }
}
