//
//  OutRunApp.swift
//
//  OutRun
//
//  The app entry point (Phase 6 shell flip). Replaces the former `@UIApplicationMain AppDelegate` +
//  UIKit `TabBarController` shell with a SwiftUI `App`. The `AppDelegate` is retained via
//  `@UIApplicationDelegateAdaptor` for `lastVersion` + the launch permission re-check; everything else
//  (root selection, migration UI, the custom tab shell, the changelog) lives in `RootView`.
//
//  The legacy `applicationDidEnterBackground` / `applicationWillEnterForeground` work — suspending and
//  resuming the map-image render queues and broadcasting the app state to `WorkoutBuilder` (battery-save
//  during recording) — moves here onto `scenePhase`, because adopting `WindowGroup` opts into the UIScene
//  lifecycle and the app-delegate background/foreground callbacks no longer fire.
//

import SwiftUI

@main
struct MoveFeetApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// Tracks whether map rendering has already been logically suspended for the current background
    /// transition. Unlike UIKit's `applicationWillEnterForeground`, `scenePhase` becomes `.active` on the
    /// initial launch too, so this flag avoids redundant scene-phase calls while the manager remains
    /// idempotent on its own.
    @State private var renderSuspended = false

    /// Move accent and appearance choices from Settings; changing either re-tints the app live.
    @AppStorage(MoveTheme.accentKey) private var accentRaw = MoveAccent.default.rawValue
    @AppStorage(MoveTheme.appearanceKey) private var appearanceRaw = MoveAppearance.system.rawValue

    init() {
        MoveTheme.registerFonts()
        MoveTheme.applyNavigationBarStyle()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color(uiColor: (MoveAccent(rawValue: accentRaw) ?? .default).label))
                .task(id: accentRaw) {
                    do { try await MoveTheme.applyAppIcon(for: MoveAccent(rawValue: accentRaw) ?? .default) }
                    catch { print("[MoveTheme] Could not reconcile app icon:", error.localizedDescription) }
                }
                .preferredColorScheme((MoveAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if !renderSuspended {
                    WorkoutMapImageManager.suspendRenderProcess()
                    renderSuspended = true
                }
                ApplicationStateObservation.stateChanged(to: .background)
            case .active:
                if renderSuspended {
                    WorkoutMapImageManager.resumeRenderProcess()
                    renderSuspended = false
                }
                ApplicationStateObservation.stateChanged(to: .foreground)
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
