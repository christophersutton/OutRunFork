//
//  WorkoutTimelineSortSheet.swift
//
//  OutRun
//
//  The SwiftUI replacement for the UIKit `WorkoutListSortViewController` popover. Sort + filter state is held
//  in-memory by the timeline view (NOT persisted to UserPreferences — matching the legacy behavior) and bound
//  here; the timeline applies it to its snapshot array. (`.duration` sort is intentionally omitted — the
//  legacy disabled it because active duration is a transient value.)
//

import SwiftUI

enum TimelineSortField: String, CaseIterable, Identifiable {
    case date, distance
    var id: String { rawValue }

    var label: String {
        switch self {
        case .date:     return LS["WorkoutList.Sort.Date"]
        case .distance: return LS["WorkoutStats.Distance"]
        }
    }
}

struct WorkoutTimelineSortSheet: View {

    @Binding var sortField: TimelineSortField
    @Binding var sortDescending: Bool
    @Binding var typeFilter: Workout.WorkoutType?
    @Binding var raceOnly: Bool

    @Environment(\.dismiss) private var dismiss

    /// The workout types offered by this fork (note: no `.unknown`).
    private static let filterableTypes = Workout.WorkoutType.supportedTypes

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(TimelineSortField.allCases) { field in
                        selectionRow(field.label, isSelected: sortField == field) { sortField = field }
                    }
                } header: {
                    Text(LS["WorkoutList.SortBy"])
                }

                Section {
                    Toggle(LS["WorkoutList.Order.Descending"], isOn: $sortDescending)
                        .tint(Color.orAccent)
                } header: {
                    Text(LS["WorkoutList.Order"])
                }

                Section {
                    Picker(LS["Workout.Type"], selection: $typeFilter) {
                        Text(LS["All"]).tag(Workout.WorkoutType?.none)
                        ForEach(Self.filterableTypes, id: \.self) { type in
                            Text(type.description).tag(Workout.WorkoutType?.some(type))
                        }
                    }
                    Toggle(LS["Workout.Race"], isOn: $raceOnly)
                        .tint(Color.orAccent)
                } header: {
                    Text(LS["WorkoutList.Filter"])
                }
            }
            .navigationTitle(LS["WorkoutList.SortBy"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LS["Done"]) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func selectionRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(Color.orPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.orAccent)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
