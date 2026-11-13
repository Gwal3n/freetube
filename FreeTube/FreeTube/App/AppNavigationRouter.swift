import Foundation
import Observation

/// One-shot player and context-menu routes for the currently selected tab.
@available(iOS 17.0, *)
@Observable
@MainActor
final class AppNavigationRouter {
    var feed: AppNavigationRequest?
    var search: AppNavigationRequest?
    var library: AppNavigationRequest?
    var downloads: AppNavigationRequest?
    var settings: AppNavigationRequest?
}
