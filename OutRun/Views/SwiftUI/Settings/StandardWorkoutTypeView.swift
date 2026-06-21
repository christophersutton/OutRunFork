//
//  StandardWorkoutTypeView.swift
//
//  OutRun
//
//  Single-select picker for the workout type pre-selected when starting a new recording. Writes the chosen
//  type's `rawValue` straight to `UserPreferences.standardWorkoutType`.
//

import SwiftUI

struct StandardWorkoutTypeView: View {

    /// The selectable workout types in display order.
    private let types = Workout.WorkoutType.supportedTypes

    @State private var selection: Int

    init() {
        _selection = State(initialValue: UserPreferences.standardWorkoutType.value)
    }

    var body: some View {
        Form {
            Section {
                ForEach(types, id: \.rawValue) { type in
                    Button {
                        selection = type.rawValue
                        UserPreferences.standardWorkoutType.value = type.rawValue
                    } label: {
                        HStack {
                            Text(type.description)
                                .foregroundStyle(Color.orPrimary)
                            Spacer()
                            if selection == type.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.orAccent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } header: {
                Text(LS["Workout.Type"])
            } footer: {
                Text(LS["Settings.StandardWorkoutType.Message"])
            }
        }
        .navigationTitle(LS["Settings.StandardWorkoutType"])
        .navigationBarTitleDisplayMode(.inline)
    }
}
