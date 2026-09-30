import Foundation
import Observation

/// One-shot player and context-menu routes for the currently selected tab.
/// Native TabView may retain tab content, so each tab observes this stable object
/// directly instead of receiving values captured when its tab closure was built.
@available(iOS 17.0, *)
@Observable
@MainActor
final class AppNavigationRouter {
    var feed: AppNavigationRequest?
    var search: AppNavigationRequest?
    var library: AppNavigationRequest?
    var downloads: AppNavigationRequest?
}
