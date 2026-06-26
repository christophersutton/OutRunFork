//
//  GPSAccuracyView.swift
//
//  OutRun
//
//  Single-select picker for the desired GPS accuracy. Each option maps to the raw `Double?` stored in
//  `UserPreferences.gpsAccuracy`: `nil` for the system standard, a meter threshold for the named tiers,
//  and `-1` to turn GPS off entirely.
//

import SwiftUI

struct GPSAccuracyView: View {

    /// A single selectable accuracy tier and its backing value.
    private struct Option: Identifiable {
        let title: String
        let value: Double?
        var id: String { title }
    }

    private let options: [Option] = [
        Option(title: LS["Settings.GPSAccuracy.Standard"], value: nil),
        Option(title: LS["Settings.GPSAccuracy.High"], value: 20),
        Option(title: LS["Settings.GPSAccuracy.Acceptable"], value: 30),
        Option(title: LS["Settings.GPSAccuracy.LastResort"], value: 50),
        Option(title: LS["Settings.GPSAccuracy.Off"], value: -1)
    ]

    @State private var selection: Double?

    init() {
        _selection = State(initialValue: UserPreferences.gpsAccuracy.value)
    }

    var body: some View {
        Form {
            Section {
                ForEach(options) { option in
                    Button {
                        selection = option.value
                        UserPreferences.gpsAccuracy.value = option.value
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(Color.orPrimary)
                            Spacer()
                            if selection == option.value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.orAccent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            } header: {
                Text(LS["Settings.GPSAccuracy.Title"])
            } footer: {
                Text(LS["Settings.GPSAccuracy.Text"])
            }
        }
        .navigationTitle(LS["Settings.GPSAccuracy"])
        .navigationBarTitleDisplayMode(.inline)
    }
}
