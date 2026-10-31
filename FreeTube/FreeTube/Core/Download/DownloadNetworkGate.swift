import Foundation
import Network

/// Tracks the current network path and applies the user's cellular download preference.
@available(iOS 17.0, *)
@MainActor
final class DownloadNetworkGate {
    private let pathMonitor = NWPathMonitor()
    private var currentPath: NWPath?

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in self.currentPath = path }
        }
        pathMonitor.start(queue: DispatchQueue(label: "DownloadManager.path"))
    }

    /// Checks the current path before a transfer starts. The original gate does not wait for
    /// connectivity to change; a disallowed path fails immediately with a retryable error.
    func requireAllowedNetwork(allowCellularDownloads: Bool) throws {
        if allowCellularDownloads { return }
        let path = currentPath ?? pathMonitor.currentPath
        if path.usesInterfaceType(.wifi) { return }
        throw YouTubeServiceError.network(NSError(
            domain: "FreeTube.DownloadManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Cellular downloads are disabled in Settings, but Wi-Fi isn't currently available."]
        ))
    }
}
