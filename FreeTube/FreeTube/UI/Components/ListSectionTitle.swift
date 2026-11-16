import SwiftUI

/// Bold browsing-section title, as in Music and TV ("Recently Played"), drawn as row content
/// so it aligns with the screen's large title instead of the indented system header.
struct ListSectionTitle<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Text(title)
        self.trailing = trailing
    }

    init(verbatim title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Text(verbatim: title)
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .appFont(.title3, weight: .bold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension ListSectionTitle where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }

    init(verbatim title: String) {
        self.init(verbatim: title) { EmptyView() }
    }
}
