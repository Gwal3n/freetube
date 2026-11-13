//
//  FreeTubeApp.swift
//  FreeTube
//
//  Created by leshko on 17/5/26.
//

import SwiftUI
import SwiftData

@main
@available(iOS 17.0, *)
struct FreeTubeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appEnvironment = AppEnvironment()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue
    @AppStorage("useAccentTheme") private var useAccentTheme = false
    @AppStorage("appAccentPreset") private var appAccentPresetRaw = AppAccentPreset.classic.rawValue
    @AppStorage("appCustomAccentHex") private var appCustomAccentHex = "#FF3B30"
    @AppStorage("accentNavigationOnly") private var accentNavigationOnly = false
    // A new app session starts on Feed. Keep selection in memory so presentations and player
    // transitions cannot change the current tab within that session.
    @State private var selectedTab = RootView.Tab.feed

    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab)
                .environment(appEnvironment.playerStateManager)
                .environment(appEnvironment.appVisitState)
                .modelContainer(PersistenceController.sharedContainer)
                .tint(useAccentTheme && !accentNavigationOnly
                      ? (AppAccentPreset(rawValue: appAccentPresetRaw) ?? .classic).color(customHex: appCustomAccentHex)
                      : .primary)
                .environment(\.settingsToggleTint,
                             useAccentTheme && !accentNavigationOnly
                             ? (AppAccentPreset(rawValue: appAccentPresetRaw) ?? .classic).color(customHex: appCustomAccentHex)
                             : .green)
                // The app and player interface follow the chosen appearance.
                .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .dark).colorScheme)
        }
        // Mac menu bar / keyboard shortcuts; harmless on iPhone.
        .commands {
            MacCommands(player: appEnvironment.playerStateManager)
        }
    }
}

private struct SettingsToggleTintKey: EnvironmentKey {
    static let defaultValue: Color = .green
}

extension EnvironmentValues {
    var settingsToggleTint: Color {
        get { self[SettingsToggleTintKey.self] }
        set { self[SettingsToggleTintKey.self] = newValue }
    }
}
