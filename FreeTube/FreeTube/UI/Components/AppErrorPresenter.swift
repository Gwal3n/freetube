import Observation

/// Presents errors from reusable rows and menus at the app's stable screen boundary.
/// Screen-local errors may continue to use ErrorToastModifier directly.
@available(iOS 17.0, *)
@MainActor
@Observable
final class AppErrorPresenter {
    var errorState: ErrorState?

    func present(_ error: ErrorState) {
        errorState = error
    }
}
