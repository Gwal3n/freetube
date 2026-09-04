import SwiftUI
import Kingfisher

/// Non-modal chapter browser. In portrait it covers only the feed below the player; in landscape
/// it occupies a dedicated trailing column, leaving the video and its controls interactive.
@available(iOS 17.0, *)
struct ChapterListPanel: View {
    let chapters: [VideoChapter]
    let elapsed: TimeInterval
    let isLandscape: Bool
    let usesOLEDBackground: Bool
    let onSeek: (TimeInterval) -> Void
    let onDismiss: () -> Void
    @State private var listScrollOffset: CGFloat = 0
    @State private var dismissTranslation: CGFloat = 0
    @State private var dismissDragOrigin: CGFloat = 0
    @State private var isTrackingDismiss = false
    @State private var panelHeight: CGFloat = 0

    private var currentChapterID: VideoChapter.ID? {
        chapters.last { $0.startTime <= elapsed }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isLandscape {
                Capsule()
                    .fill(.secondary.opacity(0.55))
                    .frame(width: 36, height: 5)
                    .padding(.top, 7)
                    .padding(.bottom, 1)
                    .accessibilityHidden(true)
            }
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
                .scrollDisabled(isTrackingDismiss)
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
        .simultaneousGesture(chapterDismissGesture)
        .background {
            if usesOLEDBackground {
                Color.black
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChapterPanelHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(ChapterPanelHeightKey.self) { panelHeight = $0 }
        .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 0 : 16, style: .continuous))
        .overlay(alignment: isLandscape ? .leading : .top) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: isLandscape ? 0.5 : nil, height: isLandscape ? nil : 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 14)
        // Move the complete sheet after applying its background and clipping. Applying offset
        // earlier leaves the material parked in place and reveals a gray rectangle instead of the
        // underlying player feed.
        .offset(y: isLandscape ? 0 : max(0, dismissTranslation))
    }

    /// A downward pull dismisses only while the chapter list is resting at its top. Upward drags
    /// and drags within scrolled content remain ordinary list scrolling.
    private var chapterDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isLandscape else { return }
                let downward = value.translation.height > 0
                    && abs(value.translation.height) > abs(value.translation.width)
                guard downward else { return }
                if !isTrackingDismiss {
                    guard listScrollOffset <= 1 else { return }
                    // If this drag began by scrolling a long list back to its top, begin sheet
                    // motion from zero here instead of jumping by the drag's full translation.
                    dismissDragOrigin = value.translation.height
                    isTrackingDismiss = true
                }
                dismissTranslation = resistedDistance(
                    max(0, value.translation.height - dismissDragOrigin)
                )
            }
            .onEnded { value in
                guard !isLandscape, isTrackingDismiss else { return }
                let projected = resistedDistance(
                    max(0, value.predictedEndTranslation.height - dismissDragOrigin)
                )
                let threshold = max(110, panelHeight * 0.25)
                if dismissTranslation > threshold || projected > threshold {
                    onDismiss()
                }
                withAnimation(.snappy(duration: 0.24)) {
                    dismissTranslation = 0
                }
                dismissDragOrigin = 0
                isTrackingDismiss = false
            }
    }

    /// A short, heavily resisted opening gives the list native-sheet elasticity before it begins
    /// following the finger more directly.
    private func resistedDistance(_ distance: CGFloat) -> CGFloat {
        let resistanceRange: CGFloat = 30
        if distance <= resistanceRange { return distance * 0.25 }
        return resistanceRange * 0.25 + (distance - resistanceRange) * 0.84
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

private struct ChapterPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
