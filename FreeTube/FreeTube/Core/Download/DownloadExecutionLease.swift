import UIKit

/// Finite UIKit runtime for a transfer that was already started when the app backgrounds.
/// Expiration cancels the attempt; the persisted video request can be retried later.
@available(iOS 17.0, *)
@MainActor
final class DownloadExecutionLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(onExpiration: @escaping @MainActor @Sendable () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish video download") { [weak self] in
            onExpiration()
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
