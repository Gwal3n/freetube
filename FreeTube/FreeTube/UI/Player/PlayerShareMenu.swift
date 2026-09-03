import SwiftUI
import UIKit

/// Equatable boundary keeps playback-time ticks from rebuilding an open native share menu.
@available(iOS 17.0, *)
struct PlayerShareMenu: View, Equatable {
    let watchURL: URL?
    let downloadedFileURL: URL?
    let onCopyAtCurrentTime: () -> Void
    let onShareDownloadedFile: (URL) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.watchURL == rhs.watchURL && lhs.downloadedFileURL == rhs.downloadedFileURL
    }

    var body: some View {
        Menu {
            if let watchURL {
                ShareLink(item: watchURL) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Link(destination: watchURL) {
                    Label("Open in browser", systemImage: "safari")
                }
                Button {
                    UIPasteboard.general.string = watchURL.absoluteString
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
            }
            Button(action: onCopyAtCurrentTime) {
                Label("Copy URL at current time", systemImage: "clock")
            }
            if let downloadedFileURL {
                Button {
                    onShareDownloadedFile(downloadedFileURL)
                } label: {
                    Label("Share downloaded file…", systemImage: "doc")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Share")
    }
}
