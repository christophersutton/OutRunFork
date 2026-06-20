//
//  SettingsView.swift
//
//  OutRun
//
//  Idiomatic SwiftUI rewrite of the settings screen. A single `Form` drives every preference through the
//  shared `SettingsState`, with sub-screens reached via `NavigationLink`. Backups, backup import and the
//  Apple Health import list still rely on UIKit controllers, so those rows are left as clearly-commented
//  placeholders for later wiring.
//

import SwiftUI

struct SettingsView: View {

    @State private var state = SettingsState()

    // Sheet presentation for the policy views.
    @State private var showTermsOfService = false
    @State private var showPrivacyPolicy = false

    // Sync-all result alert.
    @State private var showSyncResult = false
    @State private var syncResultMessage = ""

    // Delete-all flow.
    @State private var showDeleteConfirmation = false
    @State private var showDeleteError = false

    var body: some View {
        NavigationStack {
            Form {
                userSettingsSection
                unitPreferencesSection
                recordingPreferencesSection
                appleHealthSection
                dataPreferencesSection
                supportSection
                appInfoSection
            }
            .navigationTitle(LS["Settings"])
        }
        .sheet(isPresented: $showTermsOfService) {
            PolicyView(type: .termsOfService)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PolicyView(type: .privacyPolicy)
        }
        .alert(LS["Settings.SyncAll"], isPresented: $showSyncResult) {
            Button(LS["Okay"], role: .cancel) {}
        } message: {
            Text(syncResultMessage)
        }
        .alert(LS["Settings.DeleteAll.Confirmation.Title"], isPresented: $showDeleteConfirmation) {
            Button(LS["Delete"], role: .destructive) { deleteAllData() }
            Button(LS["Cancel"], role: .cancel) {}
        } message: {
            Text(LS["Settings.DeleteAll.Confirmation.Message"])
        }
        .alert(LS["Settings.DeleteAll.Error.Title"], isPresented: $showDeleteError) {
            Button(LS["Okay"], role: .cancel) {}
        } message: {
            Text(LS["Settings.DeleteAll.Error.Message"])
        }
    }

    // MARK: S1 - User Settings

    private var userSettingsSection: some View {
        Section {
            TextField(LS["Settings.UserSettings"], text: $state.name)

            HStack {
                TextField("0", text: weightBinding)
                    .keyboardType(.decimalPad)
                Text(state.weightMeasurementType.safeValue.symbol)
                    .foregroundStyle(Color.orSecondary)
            }
        } header: {
            Text(LS["Settings.UserSettings"])
        } footer: {
            Text(LS["Settings.UserSettings.Description"])
        }
    }

    /// Binding that displays the weight in the preferred unit while storing it in kilograms, and pushes
    /// new values to Apple Health when weight syncing is enabled.
    private var weightBinding: Binding<String> {
        Binding(
            get: {
                guard let kg = state.weight else { return "" }
                let displayed = state.weightMeasurementType.convert(fromValue: kg, toPrefered: true)
                return String(displayed)
            },
            set: { newValue in
                let sanitized = newValue.replacingOccurrences(of: ",", with: ".")
                guard let displayed = Double(sanitized) else {
                    state.weight = nil
                    return
                }
                let kg = state.weightMeasurementType.convert(fromValue: displayed, toPrefered: false)
                state.weight = kg

                if state.syncWeight {
                    let measurement = NSMeasurement(doubleValue: kg, unit: UnitMass.kilograms)
                    HealthStoreManager.saveWeight(for: measurement) { _ in }
                }
            }
        )
    }

    // MARK: S2 - Unit Preferences

    private var unitPreferencesSection: some View {
        Section {
            NavigationLink {
                UnitSelectionView(title: LS["Settings.DistanceUnit"], preference: UserPreferences.distanceMeasurementType)
            } label: {
                detailRow(LS["Settings.DistanceUnit"], MeasurementFormatter().string(from: UserPreferences.distanceMeasurementType.safeValue))
            }

            NavigationLink {
                UnitSelectionView(title: LS["Settings.AltitudeUnit"], preference: UserPreferences.altitudeMeasurementType)
            } label: {
                detailRow(LS["Settings.AltitudeUnit"], MeasurementFormatter().string(from: UserPreferences.altitudeMeasurementType.safeValue))
            }

            NavigationLink {
                UnitSelectionView(title: LS["Settings.SpeedUnit"], preference: UserPreferences.speedMeasurementType)
            } label: {
                detailRow(LS["Settings.SpeedUnit"], MeasurementFormatter().string(from: UserPreferences.speedMeasurementType.safeValue))
            }

            NavigationLink {
                UnitSelectionView(title: LS["Settings.EnergyUnit"], preference: UserPreferences.energyMeasurementType)
            } label: {
                detailRow(LS["Settings.EnergyUnit"], MeasurementFormatter().string(from: UserPreferences.energyMeasurementType.safeValue))
            }

            NavigationLink {
                UnitSelectionView(title: LS["Settings.WeightUnit"], preference: UserPreferences.weightMeasurementType)
            } label: {
                detailRow(LS["Settings.WeightUnit"], MeasurementFormatter().string(from: UserPreferences.weightMeasurementType.safeValue))
            }
        } header: {
            Text(LS["Settings.UnitPreferences"])
        }
    }

    // MARK: S3 - Recording Preferences

    private var recordingPreferencesSection: some View {
        Section {
            NavigationLink {
                StandardWorkoutTypeView()
            } label: {
                detailRow(LS["Settings.StandardWorkoutType"], state.standardWorkoutTypeValue.description)
            }

            Toggle(LS["Settings.MapVisibility"], isOn: $state.shouldShowMap)

            NavigationLink {
                GPSAccuracyView()
            } label: {
                detailRow(LS["Settings.GPSAccuracy"], gpsAccuracyDetail)
            }

            Toggle(LS["Settings.DisplayRollingSpeed"], isOn: $state.displayRollingSpeed)
        } header: {
            Text(LS["Settings.RecordingPreferences"])
        } footer: {
            Text(LS["Settings.RecordingPreferences.Message"])
        }
    }

    private var gpsAccuracyDetail: String {
        switch state.gpsAccuracy {
        case .none:
            return LS["Settings.GPSAccuracy.Standard"]
        case .some(let value) where value == -1:
            return LS["Settings.GPSAccuracy.Off"]
        case .some(let value):
            return "\(Int(value)) m"
        }
    }

    // MARK: S4 - Apple Health Preferences

    private var appleHealthSection: some View {
        Section {
            Toggle(LS["Settings.SynchronizeWorkoutsWithAppleHealth"], isOn: Binding(
                get: { state.syncWorkouts },
                set: { newValue in
                    guard newValue else { state.syncWorkouts = false; return }
                    PermissionManager.standard.checkHealthPermission { success in
                        DispatchQueue.main.async {
                            state.syncWorkouts = success
                            if success { HealthStoreManager.setupObservers() }
                        }
                    }
                }
            ))

            Toggle(LS["Settings.SynchronizeWeightWithAppleHealth"], isOn: Binding(
                get: { state.syncWeight },
                set: { newValue in
                    guard newValue else { state.syncWeight = false; return }
                    PermissionManager.standard.checkHealthPermission { success in
                        DispatchQueue.main.async {
                            state.syncWeight = success
                            if success { HealthStoreManager.setupObservers() }
                        }
                    }
                }
            ))

            Toggle(LS["Settings.AutoImportHealthWorkouts"], isOn: $state.autoImport)
                .disabled(!state.syncWorkouts)

            // TODO: Wire up to the Apple Health import flow. The existing list (HKImportListController)
            // is a UIKit controller; this row is a placeholder until a SwiftUI import screen exists.
            Button(LS["Settings.ImportFromAppleHealth"]) {
                // Intentionally empty - awaiting SwiftUI replacement for HKImportListController.
            }
            .foregroundStyle(Color.orPrimary)

            Button(LS["Settings.SyncAll"]) {
                syncAllUnsyncedWorkouts()
            }
            .foregroundStyle(Color.orPrimary)
            .disabled(!state.syncWorkouts)
        } header: {
            Text(LS["Settings.AppleHealthPreferences"])
        } footer: {
            Text(LS["Settings.AppleHealthPreferences.Message"])
        }
    }

    private func syncAllUnsyncedWorkouts() {
        HealthStoreManager.saveAllWorkouts { error, allSavedAlready in
            DispatchQueue.main.async {
                if error != nil {
                    syncResultMessage = LS["Settings.SyncAll.Error"]
                } else if allSavedAlready {
                    syncResultMessage = LS["Settings.SyncAll.AllSyncedAlready"]
                } else {
                    syncResultMessage = LS["Settings.SyncAll.Success"]
                }
                showSyncResult = true
            }
        }
    }

    // MARK: S5 - Data Preferences

    private var dataPreferencesSection: some View {
        Section {
            // TODO: Wire up backup export. ExportManager.displayShareAlert(for:on:) needs a presenting
            // UIViewController; this row is a placeholder until a SwiftUI-friendly share path exists.
            Button(LS["Settings.CreateBackup"]) {
                // Intentionally empty - awaiting UIViewController bridge for ExportManager.
            }
            .foregroundStyle(Color.orPrimary)

            // TODO: Wire up backup import. The import flow is UIKit-based; placeholder for now.
            Button(LS["Settings.ImportBackupData"]) {
                // Intentionally empty - awaiting SwiftUI backup import implementation.
            }
            .foregroundStyle(Color.orPrimary)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text(LS["Settings.DeleteAllData"])
            }
        } header: {
            Text(LS["Settings.DataPreferences"])
        } footer: {
            Text(LS["Settings.DataPreferences.Message"])
        }
    }

    private func deleteAllData() {
        DataManager.deleteAll { success, _ in
            DispatchQueue.main.async {
                if success {
                    UserPreferences.reset()
                    // Return the running app to onboarding (the SwiftUI shell has no window-root swap to rely
                    // on, unlike the legacy UIKit shell which required a relaunch).
                    NotificationCenter.default.post(name: .outRunDidResetData, object: nil)
                } else {
                    showDeleteError = true
                }
            }
        }
    }

    // MARK: S6 - Support

    private var supportSection: some View {
        Section {
            Button {
                showTermsOfService = true
            } label: {
                Text(LS["Settings.TermsOfService"])
                    .foregroundStyle(Color.orPrimary)
            }

            Button {
                showPrivacyPolicy = true
            } label: {
                Text(LS["Settings.PrivacyPolicy"])
                    .foregroundStyle(Color.orPrimary)
            }

            Button {
                if let url = URL(string: "mailto:outrun@tadris.de?subject=OutRun") {
                    UIApplication.shared.open(url)
                }
            } label: {
                detailRow(LS["Settings.Email"], "outrun@tadris.de")
            }
        } header: {
            Text(LS["Settings.Support"])
        }
    }

    // MARK: S7 - App Info

    private var appInfoSection: some View {
        Section {
            NavigationLink {
                ContributorsView()
            } label: {
                Text(LS["Settings.Contribution"])
            }

            Button {
                if let url = URL(string: "https://github.com/timfraedrich/OutRun") {
                    UIApplication.shared.open(url)
                }
            } label: {
                detailRow(LS["Settings.SourceCode"], "github.com")
            }

            detailRow(LS["Settings.AppVersion"], Config.version)
            detailRow(LS["Settings.ReleaseStatus"], Config.releaseStatus.rawValue)
        } header: {
            Text(LS["Settings.AppInfo"])
        } footer: {
            Text("ⓒ 2020 Tim Fraedrich")
        }
    }

    // MARK: Helpers

    /// A title-leading / detail-trailing row used for disclosure and informational entries.
    private func detailRow(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.orPrimary)
            Spacer()
            Text(detail)
                .foregroundStyle(Color.orSecondary)
        }
    }
}

#Preview {
    SettingsView()
}
