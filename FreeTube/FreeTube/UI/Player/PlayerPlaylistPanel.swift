import SwiftUI
import UIKit

/// Playlist context lives outside the scrolling details feed. The compact control opens a
/// non-modal browser beneath the video (or beside it in landscape), so playback remains usable.
/// Rows are lazy but not windowed: every fetched item is available, with continuation pages
/// requested as the user reaches the end.
@available(iOS 17.0, *)
struct PlayerPlaylistPanel: View {
    private static let dismissalThreshold: CGFloat = 42

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    let isPresented: Bool
    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
    let expansionTravel: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let onOpenPlaylist: (String) -> Void

    @State private var lastAutomaticPageCount: Int?
    @State private var dismissTranslation: CGFloat = 0
    @State private var dragStartProgress: CGFloat?
    @State private var listScrollOffset: CGFloat = 0
    @State private var listOverscroll: CGFloat = 0
    @State private var listDismissOrigin: CGFloat = 0
    @State private var listDragStartExpansion: CGFloat = 0
    @State private var isDraggingListSheet = false
    @State private var suppressPlaylistSelection = false
    @State private var selectionSuppressionGeneration = 0
    @State private var isSavedLocally = false
    @State private var hasLoadedSavedState = false
    @State private var isSavingLocally = false
    @State private var saveError: ErrorState?
    @State private var showsSavedNotice = false
    @State private var savedNoticeIsRemoval = false
    @State private var savedNoticeGeneration = 0
    private let localPlaylistService = LocalPlaylistService()

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
            isSavedLocally = false
            hasLoadedSavedState = false
            isSavingLocally = false
            saveError = nil
            showsSavedNotice = false
            savedNoticeGeneration &+= 1
        }
        .task(id: playlist?.id) {
            guard let playlist, !playlist.id.hasPrefix("local:") else { return }
            await refreshSavedState(for: playlist.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            guard let playlist, !playlist.id.hasPrefix("local:") else { return }
            Task { await refreshSavedState(for: playlist.id) }
        }
        .onChange(of: isPresented) { _, presented in
            guard !presented else { return }
            showsSavedNotice = false
            savedNoticeGeneration &+= 1
            dismissTranslation = 0
            dragStartProgress = nil
            listScrollOffset = 0
            listOverscroll = 0
            listDismissOrigin = 0
            listDragStartExpansion = 0
            isDraggingListSheet = false
            suppressPlaylistSelection = false
        }
        .overlay(alignment: .bottom) {
            if isPresented && showsSavedNotice {
                TransientNoticePill(
                    title: savedNoticeIsRemoval ? Text("Playlist removed") : Text("Playlist saved"),
                    systemImage: savedNoticeIsRemoval ? "bookmark.slash" : "checkmark",
                    onUndo: nil
                )
                .padding(.bottom, PlayerLayoutMetrics.safeAreaInsets.bottom + 12)
                .allowsHitTesting(false)
            }
        }
        .errorToast($saveError)
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
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.black)
                    .allowsHitTesting(false)
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
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(player.queue.items.count) videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 2) {
                            Button {
                                onOpenPlaylist(playlist.id)
                            } label: {
                                Image(systemName: "arrow.up.right")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open playlist page")
                            if !playlist.id.hasPrefix("local:") {
                                Button {
                                    Task { await toggleLocalSave(playlist) }
                                } label: {
                                    Group {
                                        if isSavingLocally || !hasLoadedSavedState {
                                            ProgressView()
                                        } else {
                                            Image(systemName: isSavedLocally ? "bookmark.fill" : "bookmark")
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isSavingLocally || !hasLoadedSavedState)
                                .accessibilityLabel(isSavedLocally ? "Remove saved playlist" : "Save playlist")
                                if let url = playlist.youtubeURL {
                                    Menu {
                                        Button {
                                            UIPasteboard.general.url = url
                                        } label: {
                                            Label("Copy link", systemImage: "link")
                                        }
                                        Button {
                                            openURL(url)
                                        } label: {
                                            Label("Open in browser", systemImage: "safari")
                                        }
                                        ShareLink(item: url) {
                                            Label("Share playlist", systemImage: "square.and.arrow.up")
                                        }
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundStyle(.white)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Share playlist")
                                }
                            }
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 32, height: 32)
                                    .background(.quaternary, in: Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close playlist")
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(headerDragGesture)

                Divider().opacity(0.45)

                ScrollViewReader { scrollProxy in
                    Group {
                        if #available(iOS 18.0, *) {
                            playlistRows
                                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                    geometry.contentOffset.y + geometry.contentInsets.top
                                } action: { _, rawOffset in
                                    listScrollOffset = max(0, rawOffset)
                                    listOverscroll = max(0, -rawOffset)
                                    if isDraggingListSheet, listDismissOrigin == 0,
                                       listOverscroll <= 0.5 {
                                        isDraggingListSheet = false
                                    }
                                }
                                .simultaneousGesture(listHandoffDismissGesture)
                        } else {
                            playlistRows
                        }
                    }
                    .onAppear {
                        guard player.queue.items.indices.contains(player.queue.currentIndex) else { return }
                        scrollProxy.scrollTo(player.queue.currentIndex, anchor: .center)
                    }
                }

                Button {
                    player.leavePlaylist()
                } label: {
                    Label("Continue without playlist", systemImage: "minus.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.bottom, PlayerLayoutMetrics.safeAreaInsets.bottom)
                .accessibilityHint("Keep this video playing and return to regular recommendations")
            }
            .background(Color.black)
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

    private var playlistRows: some View {
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
            .padding(.bottom, 8)
            .offset(y: isDraggingListSheet ? -listOverscroll : 0)
        }
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.always, axes: .vertical)
    }

    private func row(_ video: Video, index: Int) -> some View {
        let isCurrent = isPlayingPlaylistItem && index == player.queue.currentIndex
        return DeArrowVideoContent(video: video) { branding in
            Button {
                // Keep the browser mounted and its scroll offset intact while playback changes.
                guard !suppressPlaylistSelection else { return }
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
                            .appFont(.subheadline, weight: isCurrent ? .semibold : .regular)
                            .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.9))
                            .lineLimit(2)
                        Text(video.channelName.isEmpty ? (playlist?.channelName ?? "") : video.channelName)
                            .appFont(.caption)
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

    private func refreshSavedState(for playlistID: String) async {
        let saved = await localPlaylistService.isRemoteSaved(id: playlistID)
        guard playlist?.id == playlistID else { return }
        isSavedLocally = saved
        hasLoadedSavedState = true
    }

    private func toggleLocalSave(_ target: Playlist) async {
        guard hasLoadedSavedState, !isSavingLocally, playlist?.id == target.id else { return }
        isSavingLocally = true
        defer {
            if playlist?.id == target.id { isSavingLocally = false }
        }
        if isSavedLocally {
            await localPlaylistService.removeRemotePlaylist(id: target.id)
            if playlist?.id == target.id {
                isSavedLocally = false
                showSavedConfirmation(isRemoval: true)
            }
        } else {
            do {
                try await localPlaylistService.saveRemotePlaylist(target)
                if playlist?.id == target.id {
                    isSavedLocally = true
                    showSavedConfirmation(isRemoval: false)
                }
            } catch {
                if playlist?.id == target.id { saveError = ErrorState(from: error) }
            }
        }
    }

    private func showSavedConfirmation(isRemoval: Bool) {
        savedNoticeGeneration &+= 1
        let generation = savedNoticeGeneration
        savedNoticeIsRemoval = isRemoval
        withAnimation(reduceMotion ? nil : InterfaceMotion.notice) {
            showsSavedNotice = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard savedNoticeGeneration == generation else { return }
            withAnimation(reduceMotion ? nil : InterfaceMotion.notice) {
                showsSavedNotice = false
            }
        }
    }

    /// Match the chapter browser's handoff: the list scrolls normally until it reaches its
    /// top, then the entire sheet follows a continued downward drag. The expanded detent
    /// returns to the compact detent first; a subsequent pull dismisses it.
    private var listHandoffDismissGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape, value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if !isDraggingListSheet {
                    guard listScrollOffset <= 1 else { return }
                    listDismissOrigin = value.translation.height
                    listDragStartExpansion = expansionProgress
                    isDraggingListSheet = true
                    suppressPlaylistSelection = true
                    selectionSuppressionGeneration &+= 1
                }
                let travel = max(0, value.translation.height - listDismissOrigin)
                if listDragStartExpansion > 0 {
                    expansionProgress = max(0, listDragStartExpansion - travel / max(1, expansionTravel))
                } else {
                    dismissTranslation = travel
                }
            }
            .onEnded { value in
                guard !isLandscape else { return }
                if isDraggingListSheet {
                    let finalTravel = max(0, value.translation.height - listDismissOrigin)
                    let projectedTravel = max(0, value.predictedEndTranslation.height - listDismissOrigin)
                    if listDragStartExpansion > 0 {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                            let projected = listDragStartExpansion - projectedTravel / max(1, expansionTravel)
                            expansionProgress = projected < 0.5 ? 0 : 1
                        }
                    } else if finalTravel >= Self.dismissalThreshold,
                              projectedTravel >= Self.dismissalThreshold {
                        onDismiss()
                    } else {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                            dismissTranslation = 0
                        }
                    }
                }
                listDismissOrigin = 0
                if listOverscroll <= 0.5 { isDraggingListSheet = false }
                releasePlaylistSelectionSuppression()
            }
    }

    private func releasePlaylistSelectionSuppression() {
        let generation = selectionSuppressionGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard generation == selectionSuppressionGeneration else { return }
            suppressPlaylistSelection = false
        }
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
