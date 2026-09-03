import SwiftUI

/// Equatable boundary keeps ordinary elapsed-time changes from resetting the open chapter list.
@available(iOS 17.0, *)
struct ChapterPlayerMenu: View, Equatable {
    let chapters: [VideoChapter]
    let currentChapter: VideoChapter
    let onSelect: (TimeInterval) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chapters == rhs.chapters && lhs.currentChapter == rhs.currentChapter
    }

    var body: some View {
        Menu {
            ForEach(chapters) { chapter in
                Button {
                    onSelect(chapter.startTime)
                } label: {
                    if chapter.id == currentChapter.id {
                        Label(chapterMenuTitle(chapter), systemImage: "checkmark")
                    } else {
                        Text(chapterMenuTitle(chapter))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(verbatim: currentChapter.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: 190, alignment: .leading)
        }
        .accessibilityLabel("Current chapter, \(currentChapter.title)")
    }

    private func chapterMenuTitle(_ chapter: VideoChapter) -> String {
        let timestamp = chapter.timeDescription ?? format(chapter.startTime)
        return "\(timestamp)  \(chapter.title)"
    }

    private func format(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
