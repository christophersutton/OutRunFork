//
//  EditWorkoutForm.swift
//
//  OutRun
//
//  SwiftUI replacement for the UIKit `EditWorkoutController`. A single `Form` that handles both creating a
//  manual workout and editing an existing one (`EditWorkoutState.Mode`). Presented as a sheet from the
//  workout detail screen (edit mode) and from the tab bar's "add workout" long-press (create mode).
//
//  On a successful save the form dismisses itself and calls `onSaved(workoutID)`; callers use that to either
//  refresh the existing detail screen in place (edit) or push the new workout's detail (create).
//

import SwiftUI

struct EditWorkoutForm: View {

    @Environment(\.dismiss) private var dismiss

    @State private var state: EditWorkoutState
    @State private var showDurationWheels = false
    @FocusState private var keyboardFocused: Bool

    /// Called on the main queue after a successful save, with the saved workout's id.
    private let onSaved: (UUID) -> Void

    init(mode: EditWorkoutState.Mode, onSaved: @escaping (UUID) -> Void) {
        _state = State(initialValue: EditWorkoutState(mode: mode))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                infoSection
                commentSection
            }
            .navigationTitle(state.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LS["Cancel"]) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LS["Save"]) { save() }
                        .disabled(!state.isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { keyboardFocused = false }
                }
            }
            .alert(
                LS["Error"],
                isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var infoSection: some View {
        Section {
            Picker(LS["Workout.Type"], selection: $state.workoutType) {
                ForEach(state.availableTypes, id: \.self) { type in
                    Text(type.description).tag(type)
                }
            }

            LabeledFieldRow(title: LS["Workout.Distance"], unit: state.distanceUnitSymbol) {
                TextField("0", text: $state.distanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($keyboardFocused)
            }

            LabeledFieldRow(title: state.stepsFieldTitle, unit: nil) {
                TextField(LS["NotSet"], text: $state.stepsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($keyboardFocused)
            }

            DatePicker(LS["Workout.StartDate"], selection: $state.startDate)

            durationRow

            Toggle(LS["Workout.Race"], isOn: $state.isRace)
                .tint(Color.orAccent)
        } header: {
            Text("Info")
        }
    }

    private var commentSection: some View {
        Section {
            TextField(LS["Workout.Comment"], text: $state.comment, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text(LS["Workout.Comment"])
        }
    }

    // MARK: Duration

    @ViewBuilder
    private var durationRow: some View {
        Button {
            withAnimation { showDurationWheels.toggle() }
            keyboardFocused = false
        } label: {
            HStack {
                Text(LS["Workout.Duration"]).foregroundStyle(Color.orPrimary)
                Spacer()
                Text(formattedDuration).foregroundStyle(showDurationWheels ? Color.orAccent : Color.orSecondary)
            }
            .contentShape(Rectangle())
        }

        if showDurationWheels {
            HStack(spacing: 0) {
                durationWheel(selection: $state.durationHours, range: 0..<96)
                durationWheel(selection: $state.durationMinutes, range: 0..<60)
                durationWheel(selection: $state.durationSeconds, range: 0..<60)
            }
            .frame(height: 150)
        }
    }

    private func durationWheel(selection: Binding<Int>, range: Range<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(range, id: \.self) { value in
                Text(String(format: "%02d", value)).tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var formattedDuration: String {
        String(format: "%02d:%02d:%02d", state.durationHours, state.durationMinutes, state.durationSeconds)
    }

    // MARK: Save

    private func save() {
        keyboardFocused = false
        state.save { workoutID in
            dismiss()
            onSaved(workoutID)
        }
    }
}

/// A form row with a leading title and a trailing input, plus an optional unit label after the input.
private struct LabeledFieldRow<Content: View>: View {
    let title: String
    let unit: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.orPrimary)
            Spacer(minLength: 12)
            content
                .frame(maxWidth: 140)
            if let unit {
                Text(unit).foregroundStyle(Color.orSecondary)
            }
        }
    }
}
