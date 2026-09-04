import SwiftUI

struct IOSSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let privacyURL = URL(string: "https://xuluthebest.com/pinaday/privacy/")!
    private let supportURL = URL(string: "https://xuluthebest.com/pinaday/")!

    private var palette: AppTheme.Palette {
        appState.themePalette
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appState.localized("Appearance")) {
                    Picker(appState.localized("Theme"), selection: themeBinding) {
                        ForEach(AppThemeKind.allCases) { theme in
                            Text(appState.localized(theme.localizationKey)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(appState.localized("Language"), selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                }

                Section {
                    Picker(appState.localized("Storage & Sync"), selection: storageBinding) {
                        Text(appState.localized("Local only")).tag(StorageMode.localOnly)
                        Text(appState.localized("Sync with iCloud")).tag(StorageMode.iCloud)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Label(syncStatusTitle, systemImage: syncStatusIcon)
                            .foregroundStyle(syncStatusColor)
                        Spacer()
                        if appState.storageMode == .iCloud {
                            Button(appState.localized("Sync Now")) {
                                appState.syncNow()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text(appState.localized("Storage & Sync"))
                } footer: {
                    Text("Pinaday always saves an offline copy first. Local-only notes stay on this device.")
                }

                Section("About") {
                    LabeledContent(appState.localized("Version"), value: versionText)
                    Link(destination: privacyURL) {
                        Label(appState.localized("Privacy Policy"), systemImage: "hand.raised")
                    }
                    Link(destination: supportURL) {
                        Label(appState.localized("Feedback"), systemImage: "envelope")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.paper)
            .navigationTitle(appState.localized("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(palette.accent)
        .presentationBackground(palette.paper)
    }

    private var themeBinding: Binding<AppThemeKind> {
        Binding(get: { appState.theme }, set: appState.updateTheme)
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { appState.language }, set: appState.updateLanguage)
    }

    private var storageBinding: Binding<StorageMode> {
        Binding(get: { appState.storageMode }, set: appState.chooseStorageMode)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var syncStatusTitle: String {
        switch appState.cloudSyncStatus {
        case .localOnly:
            appState.localized("Local only")
        case .checkingAccount:
            appState.localized("Checking iCloud")
        case .syncing:
            appState.localized("Syncing")
        case .upToDate:
            appState.localized("Up to date")
        case .offline:
            appState.localized("Offline")
        case .accountUnavailable:
            appState.localized("Sign in to iCloud")
        case .capabilityUnavailable:
            appState.localized("iCloud unavailable")
        case let .failed(message):
            message
        }
    }

    private var syncStatusIcon: String {
        switch appState.cloudSyncStatus {
        case .localOnly: "internaldrive"
        case .checkingAccount, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .offline: "icloud.slash"
        case .accountUnavailable, .capabilityUnavailable, .failed: "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        switch appState.cloudSyncStatus {
        case .accountUnavailable, .capabilityUnavailable, .failed:
            .orange
        default:
            palette.secondaryText
        }
    }
}
