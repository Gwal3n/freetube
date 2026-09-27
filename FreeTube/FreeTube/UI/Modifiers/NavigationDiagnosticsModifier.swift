import SwiftUI

/// Temporary event-only diagnostics. Never initiates navigation or changes presentation state.
@available(iOS 17.0, *)
private struct NavigationDiagnosticsModifier: ViewModifier {
    let name: String

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
            .onChange(of: isPresented) { _, _ in record("presentation environment changed") }
            .onChange(of: isEnabled) { _, _ in record("enabled environment changed") }
    }

    private func record(_ event: String) {
        log.info("Trace \(name): \(event) instance=\(instanceID.uuidString) enabled=\(isEnabled) presented=\(isPresented) scene=\(String(describing: scenePhase)) mini=\(player.miniPlayerVisible) expanded=\(player.fullScreenPresented)")
    }
}

@available(iOS 17.0, *)
extension View {
    /// Observes lifecycle/environment changes without installing any gesture recognizers.
    func navigationDiagnostics(_ name: String) -> some View {
        modifier(NavigationDiagnosticsModifier(name: name))
    }
}
