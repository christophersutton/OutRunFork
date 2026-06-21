//
//  MainTabView.swift
//
//  OutRun
//
//  The custom SwiftUI tab shell replacing the UIKit `TabBarController`. SwiftUI's `TabView` exposes no tab
//  bar to inject the in-bar floating "+" button into, so the shell is hand-built: the selected tab's content
//  with a custom bottom bar (Timeline / Settings) hosted as a bottom safe-area inset, and a centered, raised
//  "+" button as a non-clipped bottom overlay. The "+" tap starts a live recording; long-press offers the
//  workout-type / manual-entry alert. A hidden 10-tap on the bar (while on Settings) opens the developer
//  `DebugView`.
//
//  Live recording (`NewWorkoutViewController`), the full-screen route map, and the manual-create flow are
//  presented imperatively on the front-most view controller — preserving their existing self-dismiss
//  contracts — exactly as the UIKit shell did, rather than being forced into SwiftUI covers.
//

import SwiftUI
import UIKit

struct MainTabView: View {

    enum Tab {
        case timeline
        case settings
    }

    @State private var selection: Tab = .timeline
    @State private var showDebug = false

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(
                    selection: $selection,
                    onDebugGesture: { if selection == .settings { showDebug = true } }
                )
            }
            // The floating "+" lives in a bottom overlay (NOT inside the safe-area inset): a raised button
            // inside the inset would have its protruding top half clipped from touch delivery, since SwiftUI
            // routes touches outside a view's frame to whatever is behind it. As a full-frame overlay it is
            // tappable across its whole area.
            .overlay(alignment: .bottom) {
                AddButton(
                    onAdd: { presentRecording(initialType: nil) },
                    onLongPress: { presentWorkoutTypeAlert() }
                )
                .padding(.bottom, 13)
            }
            .sheet(isPresented: $showDebug) {
                DebugView()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .timeline: WorkoutTimelineView()
        case .settings: SettingsView()
        }
    }

    // MARK: - Imperative UIKit presentations (front-most VC presenter)

    private func presentRecording(initialType: Workout.WorkoutType?) {
        guard let presenter = UIApplication.shared.topMostViewController else { return }
        let controller = NewWorkoutViewController()
        if let initialType { controller.initialWorkoutType = initialType }
        presenter.present(controller, animated: true)
    }

    private func presentWorkoutTypeAlert() {
        guard let presenter = UIApplication.shared.topMostViewController else { return }
        let alert = WorkoutTypeAlert(
            action: { type in
                // Defer past the alert's own dismissal transition: presenting from inside a UIAlertController
                // action handler (while it is still the presented VC) would no-op with "already presenting".
                DispatchQueue.main.async {
                    guard let presenter = UIApplication.shared.topMostViewController else { return }
                    let controller = NewWorkoutViewController()
                    controller.initialWorkoutType = type
                    presenter.present(controller, animated: true)
                }
            },
            manualAction: {
                // Manually add a workout via the SwiftUI create form. On save, dismiss the form and — in the
                // dismiss completion — show the new workout's detail (presenting during the dismiss would
                // silently fail). Mirrors the former TabBarController behaviour; deferred for the same reason
                // as the typed-action path above.
                DispatchQueue.main.async {
                    guard let presenter = UIApplication.shared.topMostViewController else { return }
                    presenter.presentSwiftUI(
                        EditWorkoutForm(mode: .create) { workoutID in
                            presenter.dismiss(animated: true) {
                                guard let top = UIApplication.shared.topMostViewController else { return }
                                let host = UIHostingController(rootView: NavigationStack { WorkoutDetailView(workoutID: workoutID) })
                                top.present(host, animated: true)
                            }
                        }
                    )
                }
            }
        )
        alert.present(on: presenter)
    }
}

// MARK: - Custom bottom bar (two side tabs + hidden debug gesture)

private struct CustomTabBar: View {

    @Binding var selection: MainTabView.Tab
    let onDebugGesture: () -> Void

    var body: some View {
        ZStack {
            // Bar background — also hosts the hidden 10-tap developer gesture (taps on empty bar regions).
            Color.orBackground
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.orForeground.opacity(0.4))
                        .frame(height: 0.5)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 10, perform: onDebugGesture)

            HStack(spacing: 0) {
                tabButton(.timeline,
                          title: LS["TabBar.Timeline"],
                          image: .tabbarTimeline,
                          selectedImage: .tabbarTimelineFilled)
                Spacer(minLength: 0)
                tabButton(.settings,
                          title: LS["TabBar.Settings"],
                          image: .tabbarSettings,
                          selectedImage: .tabbarSettingsFilled)
            }
            .padding(.horizontal, 36)
            .frame(height: 49)
        }
        .background(Color.orBackground)
    }

    private func tabButton(_ tab: MainTabView.Tab, title: String, image: UIImage, selectedImage: UIImage) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(uiImage: isSelected ? selectedImage : image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 23, height: 23)
                Text(title)
                    .font(.system(.caption2, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.orAccent : Color.orSecondary)
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating "+" button

private struct AddButton: View {

    let onAdd: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orAccent)
                .frame(width: 58, height: 58)
                .overlay(
                    Circle().stroke(Color.orBackground.opacity(0.2), lineWidth: 4)
                )
            Image(uiImage: .tabbarPlus)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
        // Long-press takes priority over tap: a held press (≥0.4s) opens the workout-type menu and suppresses
        // the tap; a quick tap starts a default recording. Attaching both as plain `.onTapGesture` +
        // `.onLongPressGesture` let the tap win even on a long hold.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in onLongPress() }
        )
        .onTapGesture(perform: onAdd)
        .accessibilityLabel(Text(LS["NewWorkoutAlert.Title"]))
    }
}
