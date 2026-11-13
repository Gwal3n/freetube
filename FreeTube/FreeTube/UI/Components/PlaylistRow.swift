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
        playlist.videoCount ?? resolvedVideoCount
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
            guard playlist.videoCount == nil else { return }
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
            ZStack(alignment: .bottom) {
                KFImage(playlist.thumbnailURL)
                    .thumbnail(size: CGSize(width: 96, height: 56)) {
                        MediaStyle.placeholderFill
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 56)

                if let count = videoCount, !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(count.formatted(.number.notation(.compactName))) \(count == 1 ? "video" : "videos")")
                            .accessibilityLabel("\(count) \(count == 1 ? "video" : "videos")")
                        Spacer(minLength: 0)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.76))
                }
            }
            .frame(width: 96, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))

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
                if dynamicTypeSize.isAccessibilitySize, let count = videoCount {
                    Text("\(count.formatted()) \(count == 1 ? "video" : "videos")")
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
}
