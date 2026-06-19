//
//  UnitSelectionView.swift
//
//  OutRun
//
//  Generic single-select picker for a `MeasurementUserPreference`. Renders an optional "Standard" row
//  (only when the locale exposes a standard unit) plus one row per possible value, writing the choice
//  straight back through the preference (`nil` == use the system standard).
//

import SwiftUI

struct UnitSelectionView<UnitType: Unit>: View {

    let title: String
    let preference: MeasurementUserPreference<UnitType>

    /// Mirrors `preference.value` so SwiftUI can react to the selection.
    @State private var selection: UnitType?

    init(title: String, preference: MeasurementUserPreference<UnitType>) {
        self.title = title
        self.preference = preference
        _selection = State(initialValue: preference.value)
    }

    var body: some View {
        Form {
            Section {
                if let standardUnit = preference.standardLocalValue {
                    row(
                        label: LS["Standard"] + " (\(standardUnit.symbol))",
                        isSelected: selection == nil
                    ) {
                        selection = nil
                        preference.value = nil
                    }
                }

                ForEach(preference.possibleValues, id: \.self) { unit in
                    row(
                        label: MeasurementFormatter().string(from: unit),
                        isSelected: selection == unit
                    ) {
                        selection = unit
                        preference.value = unit
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(Color.orPrimary)
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
