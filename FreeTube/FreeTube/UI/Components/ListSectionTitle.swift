import SwiftUI

/// Secondary browsing-section title under a large navigation title. Kept quieter than the
/// screen title so Search / Library hierarchy stays clear.
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
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(.secondary)
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
