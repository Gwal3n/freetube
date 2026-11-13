import SwiftUI

/// Feed filter controls, structured like Search's filter menu: one submenu per category, a
/// checkmark on narrowed categories, and Reset disabled until something is set. The screen owns
/// the custom-range sheets.
@available(iOS 17.0, *)
struct FeedFilterMenu: View {
    enum CustomRange: String, Identifiable {
        case uploaded, length, views
        var id: String { rawValue }
    }

    @Binding var filter: FeedVideoFilter
    var onCustomRange: (CustomRange) -> Void

    var body: some View {
        Menu {
            Menu {
                ForEach(FeedWatchFilter.allCases) { option in
                    Button {
                        filter.watch = option
                    } label: {
                        FilterMenuLabels.option(option.title, selected: filter.watch == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Watch history", active: filter.watch != .all)
            }
            Menu {
                ForEach(SearchVideoFilters.Uploaded.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomRange(.uploaded)
                        } else {
                            filter.uploaded = option
                        }
                    } label: {
                        FilterMenuLabels.option(option.title, selected: filter.uploaded == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Upload date", active: filter.uploaded != .anytime)
            }
            Menu {
                ForEach(SearchVideoFilters.Length.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomRange(.length)
                        } else {
                            filter.length = option
                        }
                    } label: {
                        FilterMenuLabels.option(option.title, selected: filter.length == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Length", active: filter.length != .any)
            }
            Menu {
                ForEach(SearchVideoFilters.Views.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomRange(.views)
                        } else {
                            filter.views = option
                        }
                    } label: {
                        FilterMenuLabels.option(option.title, selected: filter.views == option)
                    }
                }
            } label: {
                FilterMenuLabels.category("Views", active: filter.views != .any)
            }
            Divider()
            Button("Reset Filters") {
                filter = FeedVideoFilter()
            }
            .disabled(!filter.isActive)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if filter.isActive {
                        Circle()
                            .fill(.primary)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .transaction { $0.animation = nil }
        .accessibilityLabel("Feed filters")
        .accessibilityValue(filter.isActive ? "On" : "Off")
    }
}
