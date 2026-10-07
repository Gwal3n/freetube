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
        Text("Local downloads use \(formattedCacheUsage) of storage. They remain on this device until you delete them. Playback does not save a copy. More parallel fragments may speed up downloads but can trigger rate limits.")
    }
}
