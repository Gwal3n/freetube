import SwiftUI

@available(iOS 17.0, *)
struct SearchSuggestionList: View {
    let suggestions: [SearchSuggestion]
    /// The live field text; its match inside each suggestion is emphasized.
    let typedText: String
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
                            Text(highlighted(suggestion.text))
                                .appFont(.body)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 12)
                        .padding(.leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityLabel("Search for \(suggestion.text)")

                    Button {
                        onFill(suggestion)
                    } label: {
                        Image(systemName: "arrow.up.left")
                            .foregroundStyle(.secondary)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityLabel("Fill search with \(suggestion.text)")
                }
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    /// Apple-style emphasis: the part matching what was typed stays primary, and the rest of
    /// the suggestion is secondary. Without a match the whole suggestion stays primary.
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let typed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty,
              let match = result.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            result.foregroundColor = Color.primary
            return result
        }
        result.foregroundColor = Color.secondary
        result[match].foregroundColor = Color.primary
        return result
    }
}
