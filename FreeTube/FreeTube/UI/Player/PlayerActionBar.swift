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
/// All mutations are expressed as callbacks so this view remains a lightweight presentation
@available(iOS 17.0, *)
struct PlayerActionBar: View {
    let video: Video
    let isSavedToPlaylist: Bool
    let watchURL: URL?
    let downloadedFileURL: URL?
    let downloadState: PlayerDownloadPresentationState
    let onSaveToPlaylist: () -> Void
    let onCopyURL: () -> Void
    let onCopyURLAtCurrentTime: () -> Void
    let onShareDownloadedFile: () -> Void
    let onDownload: () -> Void
    let onDownloadChoice: (VideoQuality) -> Void
    @AppStorage("showPlayerSaveButton") private var showSaveButton = true
    @AppStorage("showPlayerShareButton") private var showShareButton = true
    @AppStorage("showPlayerDownloadButton") private var showDownloadButton = true
    @State private var savedMomentStore = SavedMomentStore.shared

    private var isSaved: Bool {
        isSavedToPlaylist || savedMomentStore.hasMoments(for: video.id)
    }

    var body: some View {
        if showSaveButton || showShareButton || showDownloadButton {
            HStack(spacing: 4) {
                if showSaveButton {
                    Button(action: onSaveToPlaylist) {
                        actionGlyph(isSaved ? "bookmark.fill" : "bookmark", height: 20)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Rectangle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Save")
                    .accessibilityValue(isSaved ? "Saved" : "Not saved")
                }

                if showShareButton {
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
                        // The arrow rises above the box, so the glyph's bounding box sits low;
                        // lift it so the box lines up with the neighbouring symbols.
                        actionGlyph("square.and.arrow.up", height: 23)
                            .offset(y: -1)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Share")
                }

                if showDownloadButton {
                    if downloadState == .available {
                        DownloadOptionsMenu(video: video, onSelect: onDownloadChoice) {
                            actionGlyph("arrow.down.circle", height: 21)
                                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                                .contentShape(Rectangle())
                        }
                            .id(video.id)
                            .buttonStyle(ResponsiveButtonStyle())
                            .foregroundStyle(.primary)
                    } else {
                        Button(action: onDownload) {
                            downloadLabel
                                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ResponsiveButtonStyle())
                        .foregroundStyle(.primary)
                        .opacity(downloadState == .downloading ? 0.72 : 1)
                        .accessibilityLabel(downloadAccessibilityLabel)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var downloadLabel: some View {
        switch downloadState {
        case .downloaded:
            actionGlyph("checkmark.circle.fill", height: 21)
        case .downloading:
            ProgressView().controlSize(.small)
        case .available:
            actionGlyph("arrow.down.circle", height: 21)
        }
    }

    /// Bookmark, share, and circled symbols have different intrinsic heights at one point size.
    /// Explicit heights make the row read as one size.
    private func actionGlyph(_ systemName: String, height: CGFloat) -> some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .frame(height: height)
    }

    private var downloadAccessibilityLabel: String {
        switch downloadState {
        case .downloaded: "Delete download"
        case .downloading: "Cancel download"
        case .available: "Download"
        }
    }
}
