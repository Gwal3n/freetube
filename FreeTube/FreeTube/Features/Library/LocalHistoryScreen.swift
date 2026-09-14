import SwiftUI

/// Device-only watch history backed by entries written during local playback.
@available(iOS 17.0, *)
struct LocalHistoryScreen: View {
    @Environment(PlayerStateManager.self) private var player
    @State private var entries: [WatchHistorySnapshot] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    private let pageSize = 50

    var body: some View {
        Group {
            if entries.isEmpty && isLoading {
                MediaListPlaceholder()
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Local History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you watch will appear here on this device.")
                )
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                let video = video(from: entry)
                                VideoRow(
                                    video: video,
                                    showsMoreMenu: true,
                                    offersPlayNext: true,
                                    playbackProgress: showHistoryProgressBars ? entry.resumableProgress : nil
                                ) {
                                    player.load(video)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await remove(entry) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .onAppear {
                                    if entry.videoID == entries.last?.videoID {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                        } header: {
                            Text(dayTitle(group.day))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Local History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if entries.isEmpty && hasMore { await loadMore() }
        }
    }

    private var dayGroups: [(day: Date, entries: [WatchHistorySnapshot])] {
        let calendar = Calendar.autoupdatingCurrent
        return Dictionary(grouping: entries) { calendar.startOfDay(for: $0.watchedAt) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.watchedAt > $1.watchedAt }) }
            .sorted { $0.day > $1.day }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(date: .long, time: .omitted)
    }

    private func video(from entry: WatchHistorySnapshot) -> Video {
        Video(
            id: entry.videoID,
            title: entry.title,
            channelID: "",
            channelName: entry.channelName,
            channelThumbnailURL: nil,
            thumbnailURL: entry.thumbnailURL,
            duration: entry.duration > 0 ? entry.duration : nil,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
    }

    private func remove(_ entry: WatchHistorySnapshot) async {
        await PersistenceWriter.shared.deleteWatchHistory(videoID: entry.videoID)
        entries.removeAll { $0.videoID == entry.videoID }
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        let page = await PersistenceWriter.shared.fetchWatchHistory(
            offset: entries.count,
            limit: pageSize
        )
        let existingIDs = Set(entries.map(\.videoID))
        entries.append(contentsOf: page.filter { !existingIDs.contains($0.videoID) })
        hasMore = page.count == pageSize
    }
}
