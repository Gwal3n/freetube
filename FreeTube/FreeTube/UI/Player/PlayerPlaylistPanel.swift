import SwiftUI

/// Playlist context lives outside the scrolling details feed. The compact control opens a
/// non-modal browser beneath the video (or beside it in landscape), so playback remains usable.
/// Rows are lazy but not windowed: every fetched item is available, with continuation pages
/// requested as the user reaches the end.
@available(iOS 17.0, *)
struct PlayerPlaylistPanel: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let isPresented: Bool
    let isLandscape: Bool
    let usesOLEDBackground: Bool
    @Binding var expansionProgress: CGFloat
    let expansionTravel: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let onOpenPlaylist: (String) -> Void

    @State private var lastAutomaticPageCount: Int?
    @State private var dismissTranslation: CGFloat = 0
    @State private var dragStartProgress: CGFloat?

    private var playlist: Playlist? { player.activePlaylist }

    private var isPlayingPlaylistItem: Bool {
        guard let current = player.queue.current else { return false }
        return current.id == player.currentVideo?.id
    }

    var body: some View {
        Group {
            if isPresented {
                browser
                    .transition(isLandscape ? .identity : .move(edge: .bottom).combined(with: .opacity))
            } else {
                dock
                    .transition(.opacity)
            }
        }
        .onChange(of: playlist?.id) { _, _ in
            lastAutomaticPageCount = nil
        }
    }

    @ViewBuilder
    private var dock: some View {
        if let playlist {
            Button(action: onOpen) {
                if isLandscape {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                        .frame(width: 46, height: 46)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Group {
                                if isPlayingPlaylistItem {
                                    Text("\(player.queue.currentIndex + 1) of \(playlist.videoCount ?? player.queue.items.count)")
                                } else {
                                    Text("Resumes after queue")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(ResponsiveButtonStyle())
            .background {
                if usesOLEDBackground {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black)
                        .allowsHitTesting(false)
                } else {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(.regularMaterial)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .padding(.horizontal, isLandscape ? 0 : 16)
            .padding(.bottom, isLandscape ? 0 : PlayerLayoutMetrics.safeAreaInsets.bottom + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLandscape ? .center : .bottom)
            .accessibilityLabel("Open playlist, \(playlist.title)")
        }
    }

    @ViewBuilder
    private var browser: some View {
        if let playlist {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !isLandscape {
                        Capsule()
                            .fill(.secondary.opacity(0.55))
                            .frame(width: 36, height: 5)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(player.queue.items.count) videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            onOpenPlaylist(playlist.id)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .contentShape(.interaction, Rectangle().inset(by: -6))
                        .accessibilityLabel("Open playlist page")
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 32, height: 32)
                                .background(.quaternary, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(.interaction, Rectangle().inset(by: -6))
                        .accessibilityLabel("Close playlist")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(headerDragGesture)

                Divider().opacity(0.45)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        let items = player.queue.items
                        LazyVStack(spacing: 2) {
                            ForEach(items.indices, id: \.self) { index in
                                row(items[index], index: index)
                                    .id(index)
                            }
                            if player.canLoadMorePlaylistItems {
                                Button {
                                    Task { await player.loadMorePlaylistItems() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if player.isLoadingMorePlaylistVideos {
                                            ProgressView()
                                        } else {
                                            Text("Load more videos")
                                        }
                                        Spacer()
                                    }
                                    .frame(height: 54)
                                }
                                .buttonStyle(.plain)
                                .disabled(player.isLoadingMorePlaylistVideos)
                                .task(id: items.count) {
                                    await loadNextPageIfNeeded(after: items.count)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.bottom, PlayerLayoutMetrics.safeAreaInsets.bottom)
                    }
                    .scrollIndicators(.visible)
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .onAppear {
                        guard player.queue.items.indices.contains(player.queue.currentIndex) else { return }
                        scrollProxy.scrollTo(player.queue.currentIndex, anchor: .center)
                    }
                }
            }
            .background {
                if usesOLEDBackground {
                    Color.black
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 0 : 16 * (1 - expansionProgress), style: .continuous))
            .overlay(alignment: isLandscape ? .leading : .top) {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: isLandscape ? 0.5 : nil, height: isLandscape ? nil : 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 14)
            .offset(y: isLandscape ? 0 : dismissTranslation)
        }
    }

    private func row(_ video: Video, index: Int) -> some View {
        let isCurrent = isPlayingPlaylistItem && index == player.queue.currentIndex
        return DeArrowVideoContent(video: video) { branding in
            Button {
                // Keep the browser mounted and its scroll offset intact while playback changes.
                player.load(video, skipRecommendations: true)
            } label: {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                    VideoThumbnail(
                        video: video,
                        size: CGSize(width: 88, height: 50),
                        replacementData: branding.thumbnailData(for: video),
                        replacementCacheKey: branding.thumbnailCacheKey(for: video),
                        compactBadge: true
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(branding.title(for: video))
                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.9))
                            .lineLimit(2)
                        Text(video.channelName.isEmpty ? (playlist?.channelName ?? "") : video.channelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 96 : 72)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.09))
                            .padding(.horizontal, 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isCurrent)
        }
    }

    private func loadNextPageIfNeeded(after count: Int) async {
        guard lastAutomaticPageCount != count, player.canLoadMorePlaylistItems else { return }
        lastAutomaticPageCount = count
        await player.loadMorePlaylistItems()
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if dragStartProgress == nil { dragStartProgress = expansionProgress }
                let start = dragStartProgress ?? 0
                expansionProgress = min(1, max(0, start - value.translation.height / max(1, expansionTravel)))
                dismissTranslation = start == 0 ? max(0, value.translation.height) : 0
            }
            .onEnded { value in
                guard !isLandscape else { return }
                guard let start = dragStartProgress else { return }
                dragStartProgress = nil
                if start == 0, value.translation.height > 70,
                   value.predictedEndTranslation.height > 70 {
                    dismissTranslation = 0
                    onDismiss()
                } else {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                        let projected = start - value.predictedEndTranslation.height / max(1, expansionTravel)
                        expansionProgress = projected > 0.5 ? 1 : 0
                        dismissTranslation = 0
                    }
                }
            }
    }
}
