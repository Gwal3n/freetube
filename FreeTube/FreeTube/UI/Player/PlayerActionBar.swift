import SwiftUI

/// Presentation state for the player's download control. The download manager and its side
/// effects remain outside this view; this value only determines button chrome.
@available(iOS 17.0, *)
enum PlayerDownloadPresentationState: Equatable {
    case available
    case downloading
    case downloaded
}

/// The compact save/share/download row shown alongside channel metadata.
///
/// All mutations are expressed as callbacks so this view remains a lightweight presentation
/// component rather than acquiring playlist, clipboard, or download-manager responsibilities.
@available(iOS 17.0, *)
struct PlayerActionBar: View {
    let isSavedToPlaylist: Bool
    let watchURL: URL?
    let downloadedFileURL: URL?
    let downloadState: PlayerDownloadPresentationState
    let onSaveToPlaylist: () -> Void
    let onCopyURL: () -> Void
    let onCopyURLAtCurrentTime: () -> Void
    let onShareDownloadedFile: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSaveToPlaylist) {
                Image(systemName: isSavedToPlaylist ? "bookmark.fill" : "bookmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ResponsiveButtonStyle())
            .foregroundStyle(.primary)
            .accessibilityLabel("Save to playlist")
            .accessibilityValue(isSavedToPlaylist ? "Saved" : "Not saved")

            Menu {
                if let watchURL {
                    ShareLink(item: watchURL) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: watchURL) {
                        Label("Open in browser", systemImage: "safari")
                    }
                    Button(action: onCopyURL) {
                        Label("Copy URL", systemImage: "link")
                    }
                }
                Button(action: onCopyURLAtCurrentTime) {
                    Label("Copy URL at current time", systemImage: "clock")
                }
                if downloadedFileURL != nil {
                    Button(action: onShareDownloadedFile) {
                        Label("Share downloaded file…", systemImage: "doc")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3.weight(.semibold))
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .foregroundStyle(.primary)
            .accessibilityLabel("Share")

            Button(action: onDownload) {
                downloadLabel
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .foregroundStyle(.primary)
            .disabled(downloadState != .available)
            .opacity(downloadState == .downloading ? 0.72 : 1)
            .accessibilityLabel(downloadAccessibilityLabel)
        }
    }

    @ViewBuilder
    private var downloadLabel: some View {
        switch downloadState {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
        case .downloading:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "arrow.down.circle")
                .font(.title3.weight(.semibold))
        }
    }

    private var downloadAccessibilityLabel: String {
        switch downloadState {
        case .downloaded: "Downloaded"
        case .downloading: "Downloading"
        case .available: "Download"
        }
    }
}
