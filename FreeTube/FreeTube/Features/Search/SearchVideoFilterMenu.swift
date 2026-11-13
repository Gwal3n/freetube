import SwiftUI

/// Hybrid search filters, shown as a glass circle at the top trailing edge of the results header
/// like Feed's toolbar filter. The icon becomes a music note while YouTube Music is the source.
/// Sort / type / upload / length presets go to YouTube when possible; watch history, views, and
/// custom ranges stay local. Category rows that currently constrain results show a checkmark.
@available(iOS 17.0, *)
struct SearchVideoFilterMenu: View {
    @Binding var filters: SearchVideoFilters
    var onCustomUploaded: () -> Void
    var onCustomLength: () -> Void
    var onCustomViews: () -> Void

    var body: some View {
        Menu {
            Menu {
                ForEach(SearchVideoFilters.Source.allCases) { option in
                    Button {
                        filters.selectSource(option)
                    } label: {
                        optionLabel(option.title, selected: filters.source == option)
                    }
                }
            } label: {
                categoryLabel("Source", active: filters.source != .youtube)
            }
            Menu {
                ForEach(SearchVideoFilters.Sort.allCases) { option in
                    Button {
                        filters.sort = option
                    } label: {
                        optionLabel(option.title, selected: filters.sort == option)
                    }
                }
            } label: {
                categoryLabel("Sort by", active: filters.sort != .relevance)
            }
            .disabled(!filters.supportsServerConstraints)
            Menu {
                ForEach(SearchVideoFilters.Watch.allCases) { option in
                    Button {
                        filters.watch = option
                    } label: {
                        optionLabel(option.title, selected: filters.watch == option)
                    }
                }
            } label: {
                categoryLabel("Watch history", active: filters.watch != .all)
            }
            Menu {
                ForEach(SearchVideoFilters.Uploaded.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomUploaded()
                        } else {
                            filters.uploaded = option
                        }
                    } label: {
                        optionLabel(option.title, selected: filters.uploaded == option)
                    }
                }
            } label: {
                categoryLabel("Upload date", active: filters.uploaded != .anytime)
            }
            .disabled(!filters.resultType.supportsVideoConstraints || !filters.supportsServerConstraints)
            Menu {
                ForEach(SearchVideoFilters.Length.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomLength()
                        } else {
                            filters.length = option
                        }
                    } label: {
                        optionLabel(option.title, selected: filters.length == option)
                    }
                }
            } label: {
                categoryLabel("Length", active: filters.length != .any)
            }
            .disabled(!filters.resultType.supportsVideoConstraints || !filters.supportsServerConstraints)
            Menu {
                ForEach(SearchVideoFilters.Views.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomViews()
                        } else {
                            filters.views = option
                        }
                    } label: {
                        optionLabel(option.title, selected: filters.views == option)
                    }
                }
            } label: {
                categoryLabel("Views", active: filters.views != .any)
            }
            .disabled(!filters.resultType.supportsVideoConstraints)
            Divider()
            Button("Reset Filters") {
                var reset = filters.resettingFilters()
                reset.resultType = filters.resultType
                filters = reset
            }
            .disabled(!filters.isNarrowedBeyondType)
        } label: {
            // Styled like the result-type subtitle opposite it; the accent color and count mark
            // active filters. The source is a mode rather than a filter, so Music names itself.
            HStack(spacing: 5) {
                // Sized to the widest possible label so a source or count change never resizes
                // the menu label, which briefly clipped the new text until it re-laid out.
                ZStack(alignment: .trailing) {
                    ForEach(Self.widestLabels, id: \.self) { label in
                        Text(verbatim: label).hidden()
                    }
                    Text(verbatim: activeFilterCount > 0 ? "\(sourceTitle) · \(activeFilterCount)" : sourceTitle)
                }
                .font(.subheadline)
                .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(activeFilterCount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .accessibilityLabel("Filter search videos")
        .accessibilityValue(activeFilterCount > 0 ? "\(activeFilterCount) active" : "Off")
    }

    private static var widestLabels: [String] {
        [String(localized: "Filters"), String(localized: "YouTube Music")].map { "\($0) · 5" }
    }

    private var sourceTitle: String {
        filters.source == .music ? String(localized: "YouTube Music") : String(localized: "Filters")
    }

    /// Narrowing categories in the menu; the source and result type are excluded.
    private var activeFilterCount: Int {
        [
            filters.sort != .relevance,
            filters.watch != .all,
            filters.uploaded != .anytime,
            filters.length != .any,
            filters.views != .any
        ].filter { $0 }.count
    }
}

@available(iOS 17.0, *)
extension SearchVideoFilterMenu {
    @ViewBuilder
    private func categoryLabel(_ title: String, active: Bool) -> some View {
        if active {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func optionLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
