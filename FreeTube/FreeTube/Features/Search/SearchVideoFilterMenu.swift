import SwiftUI

/// Hybrid search filters as a trailing text menu on the results subtitle row. Sort / upload /
/// length presets go to YouTube when possible; watch history, views, and custom ranges stay
/// local. Category rows that currently constrain results show a checkmark.
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
                        FilterMenuLabels.option(option.title, selected: filters.source == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Source", active: filters.source != .youtube)
            }
            Menu {
                ForEach(SearchVideoFilters.Sort.allCases) { option in
                    Button {
                        filters.sort = option
                    } label: {
                        FilterMenuLabels.option(option.title, selected: filters.sort == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Sort by", active: filters.sort != .relevance)
            }
            .disabled(!filters.supportsServerConstraints)
            Menu {
                ForEach(SearchVideoFilters.Watch.allCases) { option in
                    Button {
                        filters.watch = option
                    } label: {
                        FilterMenuLabels.option(option.title, selected: filters.watch == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Watch history", active: filters.watch != .all)
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
                        FilterMenuLabels.option(option.title, selected: filters.uploaded == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Upload date", active: filters.uploaded != .anytime)
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
                        FilterMenuLabels.option(option.title, selected: filters.length == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Length", active: filters.length != .any)
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
                        FilterMenuLabels.option(option.title, selected: filters.views == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Views", active: filters.views != .any)
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
