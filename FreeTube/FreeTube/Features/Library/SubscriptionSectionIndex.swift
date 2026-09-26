import SwiftUI

/// Keeps finger-tracking state in the small index rather than recomputing the complete grouped
/// subscriptions List each time the drag crosses a letter. Scroll and selection behavior are unchanged.
@available(iOS 17.0, *)
struct SubscriptionSectionIndex: View {
    let titles: [String]
    let onSelect: (String) -> Void
    @State private var activeIndexTitle: String?

    var body: some View {
        GeometryReader { geometry in
            let itemHeight = min(18, geometry.size.height / CGFloat(max(1, titles.count)))
            let topInset = max(0, (geometry.size.height - itemHeight * CGFloat(titles.count)) / 2)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(titles, id: \.self) { title in
                    Button { onSelect(title) } label: {
                        Text(verbatim: title)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: itemHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(title)")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !titles.isEmpty else { return }
                        let position = (value.location.y - topInset) / max(itemHeight, 1)
                        let index = min(max(Int(position), 0), titles.count - 1)
                        let title = titles[index]
                        guard activeIndexTitle != title else { return }
                        activeIndexTitle = title
                        onSelect(title)
                    }
                    .onEnded { _ in activeIndexTitle = nil }
            )
        }
        .frame(width: 26)
    }
}
