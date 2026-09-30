import Foundation
import Observation

/// Delivers player/context-menu destinations directly to the Feed's navigation stack.
/// The native TabView can retain its tab content, so forwarding a new value through the
/// tab's construction closure does not reliably refresh an already-mounted Feed screen.
@available(iOS 17.0, *)
@Observable
@MainActor
final class FeedNavigationRouter {
    var request: AppNavigationRequest?
}
