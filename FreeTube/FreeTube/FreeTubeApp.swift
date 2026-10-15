//
//  FreeTubeApp.swift
//  FreeTube
//
//  Created by leshko on 17/5/26.
//
//  CLAUDE.md says iOS 16.0+, but SwiftData and `@Observable` require iOS 17.0+. The deployment
//  target should be bumped to 17.0 in the Xcode project; this file requires iOS 17.
//

import SwiftUI
import SwiftData

@main
@available(iOS 17.0, *)
struct FreeTubeApp: App {
    @State private var appEnvironment = AppEnvironment()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue
    // A new app session starts on Feed. Keep selection in memory so presentations and player
    // transitions cannot change the current tab within that session.
    @State private var selectedTab = RootView.Tab.feed

    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab)
                .environment(appEnvironment.playerStateManager)
                .environment(appEnvironment.appVisitState)
                .modelContainer(PersistenceController.sharedContainer)
                // Keep navigation and player controls neutral. Switches set their native
                // green tint locally so their enabled track remains distinct from the thumb.
                .tint(.primary)
                // The app and player interface follow the chosen appearance.
                .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .dark).colorScheme)
        }
        // Menu-bar items + keyboard shortcuts. Only meaningful on Mac (via "Designed for
        // iPad on Mac" — Catalyst would also pick them up if we ever enable it), but
        // harmless to register everywhere — iPhone shows no menu bar, iPad-with-keyboard
        // picks up the shortcuts which is a fine bonus. See `MacCommands`.
        .commands {
            MacCommands(player: appEnvironment.playerStateManager)
        }
    }
}
