import SwiftUI

@available(iOS 17.0, *)
struct SearchSuggestionList: View {
    let suggestions: [SearchSuggestion]
    let onSelect: (SearchSuggestion) -> Void
    let onFill: (SearchSuggestion) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                HStack(spacing: 0) {
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text(suggestion.text)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 12)
                        .padding(.leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onFill(suggestion)
                    } label: {
                        Image(systemName: "arrow.up.left")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fill search with \(suggestion.text)")
                }
                Divider()
            }
        }
    }
}
