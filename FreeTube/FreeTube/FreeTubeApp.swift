//
//  FreeTubeApp.swift
//  FreeTube
//
//  Created by leshko on 17/5/26.
//
//  The deployment target is iOS 26.1. The tab shell uses the system Search tab role;
//  the player is presented by the app's SwiftUI player container above that shell.
//

import SwiftUI
import SwiftData

@main
struct FreeTubeApp: App {
    @State private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment.playerStateManager)
                .modelContainer(PersistenceController.sharedContainer)
                // Dark-only appearance app-wide. No user-facing toggle — the player chrome,
                // mini-player bar, and full-screen content are all designed for dark.
                .preferredColorScheme(.dark)
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
