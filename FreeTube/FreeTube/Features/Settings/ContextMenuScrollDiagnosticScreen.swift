import SwiftUI

/// Temporary experiment that separates List's native context-menu transition from the app's
/// composite video-row structure. Remove this screen before merging the experiment into main.
@available(iOS 17.0, *)
struct ContextMenuScrollDiagnosticScreen: View {
    var body: some View {
        List {
            Section {
                Text(verbatim: "Long-press a row, dismiss the menu, then immediately scroll. Compare all three sections.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(0..<20, id: \.self) { index in
                    Text(verbatim: "Plain row \(index + 1)")
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {} label: {
                                Label("Test action", systemImage: "checkmark")
                            }
                        }
                }
            } header: {
                Text(verbatim: "Plain List rows")
            } footer: {
                Text(verbatim: "No thumbnail, nested buttons, swipe actions, or custom preview.")
            }

            Section {
                ForEach(0..<20, id: \.self) { index in
                    Menu {
                        Button {} label: {
                            Label("Test action", systemImage: "checkmark")
                        }
                    } label: {
                        Text(verbatim: "Menu row \(index + 1)")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                    } primaryAction: {}
                }
            } header: {
                Text(verbatim: "Native Menu with primary tap")
            } footer: {
                Text(verbatim: "A tap performs a no-op; a long press opens a native Menu without a custom preview.")
            }

            Section {
                ForEach(0..<20, id: \.self) { index in
                    compositeRow(index)
                }
            } header: {
                Text(verbatim: "App-like rows")
            } footer: {
                Text(verbatim: "Static thumbnail, playback button, ellipsis menu, and swipe action. No networking.")
            }
        }
        .listStyle(.plain)
        .navigationTitle("Context Menu Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func compositeRow(_ index: Int) -> some View {
        HStack(spacing: 0) {
            Button {} label: {
                HStack(alignment: .top, spacing: MediaStyle.spacing) {
                    RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                        .fill(Color.secondary.opacity(0.25))
                        .overlay {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 144, height: 81)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Video row \(index + 1)")
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: "Example channel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: "1,234 views • 2 days ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())

            Menu {
                Button {} label: {
                    Label("Test action", systemImage: "checkmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Rectangle())
            }
        }
        .contextMenu {
            Button {} label: {
                Label("Test action", systemImage: "checkmark")
            }
        }
        .swipeActions(edge: .leading) {
            Button {} label: {
                Label("Test action", systemImage: "checkmark")
            }
        }
        .mediaListRow()
    }
}
