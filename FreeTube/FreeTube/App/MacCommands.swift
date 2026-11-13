import SwiftUI

/// Mac menu bar and keyboard shortcuts for Settings, tabs, and playback.
@available(iOS 17.0, *)
struct MacCommands: Commands {
    let player: PlayerStateManager

    var body: some Commands {
        // 1. Open the in-window Settings sheet instead of a separate Settings scene.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // 2. Navigate menu — quick-jump to tabs. ⌘F lands on Search.
        CommandMenu("Navigate") {
            Button("Feed") { postTab(.feed) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Search") { postTab(.search) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Find…") { postTab(.search) }
                .keyboardShortcut("f", modifiers: .command)
            Button("Library") { postTab(.library) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Downloads") { postTab(.downloads) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Settings") { openSettings() }
                .keyboardShortcut("5", modifiers: .command)
        }

        // 3. Playback menu — same controls as the lock-screen remote on iOS. Disabled
        // when no video is loaded so the menu doesn't lie about being usable.
        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") {
                player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(player.currentVideo == nil)

            Divider()

            Button("Skip Forward 15s") {
                player.seekRelative(by: 15)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(player.currentVideo == nil)

            Button("Skip Backward 15s") {
                player.seekRelative(by: -15)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(player.currentVideo == nil)

            Divider()

            Button("Next") {
                player.playNext()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(player.currentVideo == nil)

            Button("Previous") {
                player.playPrevious()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(player.currentVideo == nil)
        }
    }

    private func postTab(_ tab: RootView.Tab) {
        NotificationCenter.default.post(name: .freetubeSelectTab, object: tab)
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .freetubeOpenSettings, object: nil)
    }
}

extension Notification.Name {
    /// Posted by `MacCommands` when the user picks a tab via menu / shortcut. `RootView`
    /// listens and updates its `@State selectedTab`. The `object` is a `RootView.Tab`.
    static let freetubeSelectTab = Notification.Name("com.leshko.freetube.selectTab")
    static let freetubeOpenSettings = Notification.Name("com.leshko.freetube.openSettings")
    static let freetubeOpenSubscriptionGroups = Notification.Name("com.leshko.freetube.openSubscriptionGroups")
    /// Requests app-level channel presentation after the expanded player has collapsed.
    /// The object is a channel ID string.
    static let freetubeOpenChannel = Notification.Name("com.leshko.freetube.openChannel")
    /// Requests playlist presentation in the currently selected tab without changing tabs.
    static let freetubeOpenPlaylist = Notification.Name("com.leshko.freetube.openPlaylist")
    static let freetubeOpenLocalPlaylist = Notification.Name("com.leshko.freetube.openLocalPlaylist")
}
