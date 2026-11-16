import SwiftUI
import Kingfisher

/// Playlist list row. `showsMoreMenu` places a sibling ellipsis so taps do not fire `onTap`.
@available(iOS 17.0, *)
struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppErrorPresenter.self) private var errorPresenter
    @State private var actionsModel = PlaylistActionsModel()
    @State private var resolvedVideoCount: Int?

    /// Leave nil inside NavigationLink — an inner Button swallows the link tap.
    var onTap: (() -> Void)? = nil

    var showsMoreMenu: Bool = false

    private var videoCount: Int? {
        guard !playlist.isMix, let count = playlist.videoCount ?? resolvedVideoCount, count > 0 else {
            return nil
        }
        return count
    }

    private var thumbnailSize: CGSize {
        MediaStyle.compactVideoThumbnailSize(for: dynamicTypeSize)
    }

    private var badgeText: String? {
        if playlist.isMix { return String(localized: "Mix") }
        guard let count = videoCount else { return nil }
        return String(localized: "\(count) videos")
    }

    var body: some View {
        HStack(spacing: 0) {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(ResponsiveButtonStyle())
            } else {
                content
            }

            if showsMoreMenu {
                PlaylistMoreActionsMenu(playlist: playlist, model: actionsModel)
            }
        }
        .mediaListRow()
        .contextMenu {
            PlaylistActionsContent(playlist: playlist, model: actionsModel, offersOpen: true)
        } preview: {
            PlaylistContextPreview(playlist: playlist)
        }
        .task(id: playlist.id) { await actionsModel.refresh(id: playlist.id) }
        .task(id: playlist.id) {
            resolvedVideoCount = nil
            guard playlist.videoCount == nil, !playlist.isMix else { return }
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            let count = await PlaylistCountResolver.shared.count(for: playlist.id)
            guard !Task.isCancelled else { return }
            resolvedVideoCount = count
        }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await actionsModel.refresh(id: playlist.id) }
        }
        .onChange(of: actionsModel.errorState?.id) { _, _ in
            guard let error = actionsModel.errorState else { return }
            errorPresenter.present(error)
        }
    }

    private var content: some View {
        HStack(spacing: MediaStyle.spacing) {
            artwork
            VStack(alignment: .leading, spacing: MediaStyle.labelSpacing) {
                Text(playlist.title)
                    .appFont(.subheadline, weight: .semibold)
                    .lineLimit(MediaStyle.mediaTitleLineLimit(for: dynamicTypeSize))
                if let channelName = playlist.channelName, !channelName.isEmpty {
                    Text(channelName)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                if dynamicTypeSize.isAccessibilitySize, let badgeText {
                    Text(verbatim: badgeText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // No manual chevron — when this row sits inside a `NavigationLink` in a List, iOS adds
            // its own disclosure chevron. Drawing one here was rendering a duplicate accessory.
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Two receding cards peek above the artwork so playlists read as collections beside video
    /// rows. The stack fits inside the video thumbnail's frame, keeping mixed rows aligned.
    private var artwork: some View {
        let stackInset: CGFloat = 6
        let imageSize = CGSize(width: thumbnailSize.width, height: thumbnailSize.height - stackInset)
        let layerRadius = MediaStyle.thumbnailRadius - 2
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: layerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
                .frame(width: imageSize.width - 16, height: imageSize.height)
                .offset(y: -stackInset)
            RoundedRectangle(cornerRadius: layerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: imageSize.width - 8, height: imageSize.height)
                .offset(y: -stackInset / 2)
            artworkImage(size: imageSize)
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height, alignment: .bottom)
    }

    private func artworkImage(size: CGSize) -> some View {
        KFImage(playlist.thumbnailURL)
            .thumbnail(size: thumbnailSize) {
                MediaStyle.placeholderFill
            }
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .background(MediaStyle.placeholderFill)
            .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))
            .mediaArtworkOutline()
            .overlay(alignment: .bottomTrailing) {
                if let badgeText, !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 3) {
                        Image(systemName: playlist.isMix ? "infinity" : "rectangle.stack.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(verbatim: badgeText)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
                }
            }
    }
}
