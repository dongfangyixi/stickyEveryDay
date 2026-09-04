import SwiftUI

enum IOSSystemLanguageResolver {
    static func language(for preferredIdentifiers: [String]) -> AppLanguage {
        for identifier in preferredIdentifiers {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "fr": return .french
            case "es": return .spanish
            case "zh": return .simplifiedChinese
            case "ja": return .japanese
            case "ko": return .korean
            case "de": return .german
            case "pt": return .portugueseBrazil
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}

@main
struct PinadayIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState

    init() {
        let dateService = DateKeyService()
        let state = AppState(
            dataStore: JSONAppDataStore(),
            dateKeyService: dateService,
            cloudSyncService: CloudKitSyncService()
        )
        if !state.hasSeenWelcome && !state.hasChosenStorageMode {
            state.updateLanguage(
                IOSSystemLanguageResolver.language(
                    for: Locale.preferredLanguages
                )
            )
        }
        _appState = StateObject(wrappedValue: state)
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.theme == .dark ? .dark : .light)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                appState.appDidBecomeActive()
            case .inactive, .background:
                appState.saveImmediately()
                appState.appDidResignActive()
            @unknown default:
                break
            }
        }
    }
}
