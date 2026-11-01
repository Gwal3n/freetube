import SwiftUI

/// Shared singletons placed into the SwiftUI environment by `FreeTubeApp`.
/// Views observe these via `@Environment(PlayerStateManager.self)` etc.
@available(iOS 17.0, *)
@MainActor
final class AppEnvironment {
    let playerStateManager = PlayerStateManager()
    let appVisitState = AppVisitState()

    init() {
        SecurityHardening.configureAtLaunch()
        // Touch `LogFileWriter.shared` first so the file-logging writer (if enabled)
        // captures every subsequent line in this init — audio session setup, remote
        // commands, and background task registration.
        _ = LogFileWriter.shared
        AudioSessionConfigurator.configure()
        RemoteCommandCenter.wire(to: playerStateManager)
        BackgroundDownloadCoordinator.shared.registerBackgroundTasks()
        BackgroundDownloadCoordinator.shared.resumePending()
        // Explicit local-playlist metadata jobs are app-owned, not tied to a playlist screen.
        // The saved per-video checkpoint lets an interrupted session resume on relaunch.
        Task { await LocalPlaylistRefreshCoordinator.shared.resumePending() }
        if let cutoff = UserPreferences().historyRetentionPolicy.cutoffDate() {
            Task { await PersistenceWriter.shared.clearWatchHistory(olderThan: cutoff) }
        }
    }
}
