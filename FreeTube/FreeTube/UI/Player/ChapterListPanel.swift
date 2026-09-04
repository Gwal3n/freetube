import SwiftUI
import Kingfisher

/// Non-modal chapter browser. In portrait it covers only the feed below the player; in landscape
/// it occupies a dedicated trailing column, leaving the video and its controls interactive.
@available(iOS 17.0, *)
struct ChapterListPanel: View {
    let chapters: [VideoChapter]
    let elapsed: TimeInterval
    let isLandscape: Bool
    let onSeek: (TimeInterval) -> Void
    let onDismiss: () -> Void
    @State private var listScrollOffset: CGFloat = 0
    @GestureState private var dismissTranslation: CGFloat = 0

    private var currentChapterID: VideoChapter.ID? {
        chapters.last { $0.startTime <= elapsed }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chapters")
                        .font(.headline)
                    Text("\(chapters.count) in this video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close chapters")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.45)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear
                            .frame(height: 1)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ChapterListScrollOffsetKey.self,
                                        value: max(
                                            0,
                                            -proxy.frame(in: .named("chapterListScroll")).minY
                                        )
                                    )
                                }
                            }
                        ForEach(chapters) { chapter in
                            Button {
                                onSeek(chapter.startTime)
                            } label: {
                                chapterRow(chapter)
                            }
                            .buttonStyle(.plain)
                            .id(chapter.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .coordinateSpace(name: "chapterListScroll")
                .onPreferenceChange(ChapterListScrollOffsetKey.self) {
                    listScrollOffset = $0
                }
                .scrollIndicators(.visible)
                .onAppear {
                    guard let currentChapterID else { return }
                    scrollProxy.scrollTo(currentChapterID, anchor: .center)
                }
            }
        }
        .offset(y: max(0, dismissTranslation))
        .simultaneousGesture(chapterDismissGesture)
        .background(.regularMaterial)
        .overlay(alignment: isLandscape ? .leading : .top) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: isLandscape ? 0.5 : nil, height: isLandscape ? nil : 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 14)
    }

    /// A downward pull dismisses only while the chapter list is resting at its top. Upward drags
    /// and drags within scrolled content remain ordinary list scrolling.
    private var chapterDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dismissTranslation) { value, state, _ in
                guard listScrollOffset <= 1,
                      value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                state = value.translation.height
            }
            .onEnded { value in
                guard listScrollOffset <= 1,
                      value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height > 90 || value.predictedEndTranslation.height > 180 {
                    onDismiss()
                }
            }
    }

    private func chapterRow(_ chapter: VideoChapter) -> some View {
        let isCurrent = chapter.id == currentChapterID
        return HStack(spacing: 12) {
            KFImage(chapter.thumbnailURL)
                .thumbnail(size: CGSize(width: 128, height: 72)) {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.secondary)
                    }
                }
                .resizable()
                .scaledToFill()
                .frame(width: isLandscape ? 112 : 128, height: isLandscape ? 63 : 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text(chapter.timeDescription ?? format(chapter.startTime))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(chapter.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(2)
                if isCurrent {
                    Label("Playing", systemImage: "speaker.wave.2.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
    }

    private func format(_ value: TimeInterval) -> String {
        let total = max(0, Int(value))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ChapterListScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
