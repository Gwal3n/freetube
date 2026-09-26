import Foundation
import SwiftUI

/// Observe download-library changes here instead of invalidating the entire Settings form.
@available(iOS 17.0, *)
struct DownloadsSettingsFooter: View {
    private let downloads = DownloadsStore.shared

    private var formattedCacheUsage: String {
        let bytes = downloads.entries.reduce(Int64.zero) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        Text("Currently using \(formattedCacheUsage). When the cache exceeds the limit, the oldest downloads are removed to fit.\n\nDownloads start only when requested; playing a video does not normally save an offline copy.\n\nParallel fragments controls how many HLS chunks are downloaded at once — higher values are faster on good connections; values above 8 can trigger YouTube rate-limiting.")
    }
}
