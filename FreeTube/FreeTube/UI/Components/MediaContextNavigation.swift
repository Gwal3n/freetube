import Foundation

@available(iOS 17.0, *)
@MainActor
enum MediaContextNavigation {
    static func open(_ name: Notification.Name, id: String, player: PlayerStateManager) {
        let wasExpanded = player.fullScreenPresented
        if wasExpanded { player.fullScreenPresented = false }
        Task { @MainActor in
            // Wait for the native menu to dismiss before changing navigation.
            try? await Task.sleep(for: .milliseconds(wasExpanded ? 180 : 100))
            NotificationCenter.default.post(name: name, object: id)
        }
    }
}
