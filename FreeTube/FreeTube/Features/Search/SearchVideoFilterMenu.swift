import SwiftUI

/// Hybrid search filters, styled like `FeedFilterMenu` for toolbar placement. The icon becomes a
/// music note while YouTube Music is the search source.
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
                ForEach(SearchVideoFilters.ResultType.allCases) { option in
                    Button {
                        filters.resultType = option
                    } label: {
                        optionLabel(option.title, selected: filters.resultType == option)
                    }
                }
            } label: {
                categoryLabel("Type", active: filters.resultType != .any)
            }
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
                filters = filters.resettingFilters()
            }
            .disabled(!filters.isActive)
        } label: {
            Image(systemName: filters.source == .music ? "music.note" : "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if filters.isActive {
                        Circle()
                            .fill(.primary)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .accessibilityLabel("Filter search videos")
        .accessibilityValue(filters.isActive ? "On" : "Off")
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
