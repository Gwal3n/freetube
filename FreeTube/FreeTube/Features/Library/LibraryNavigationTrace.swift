import SwiftUI

/// Temporary, non-interactive trace for the iOS 26 Library navigation-host regression.
/// It observes lifecycle and presentation environment only; it installs no gesture recognizer.
@available(iOS 17.0, *)
private struct LibraryNavigationTrace: ViewModifier {
    let location: String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isPresented) private var isPresented
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerStateManager.self) private var player
    @State private var instanceID = UUID()
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    func body(content: Content) -> some View {
        content
            .onAppear { record("appear") }
            .onDisappear { record("disappear") }
            .onChange(of: isPresented) { _, _ in record("presentation changed") }
            .onChange(of: isEnabled) { _, _ in record("enabled changed") }
    }

    private func record(_ event: String) {
        log.info("Library A/B \(location): \(event) instance=\(instanceID.uuidString) enabled=\(isEnabled) presented=\(isPresented) scene=\(String(describing: scenePhase)) mini=\(player.miniPlayerVisible) expanded=\(player.fullScreenPresented)")
    }
}

@available(iOS 17.0, *)
extension View {
    func libraryNavigationTrace(_ location: String) -> some View {
        modifier(LibraryNavigationTrace(location: location))
    }
}
