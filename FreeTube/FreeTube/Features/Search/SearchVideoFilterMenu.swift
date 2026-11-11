import SwiftUI

/// Hybrid search filters in a trailing navigation-bar menu. Matches `FeedFilterMenu` so the
/// control picks up the system Liquid Glass treatment of other top-right toolbar buttons.
/// Sort / type / upload / length presets go to YouTube when possible; watch history, views, and
/// custom ranges stay local.
@available(iOS 17.0, *)
struct SearchVideoFilterMenu: View {
    @Binding var filters: SearchVideoFilters
    var onCustomUploaded: () -> Void
    var onCustomLength: () -> Void
    var onCustomViews: () -> Void

    var body: some View {
        Menu {
            Menu {
                ForEach(SearchVideoFilters.Sort.allCases) { option in
                    Button {
                        filters.sort = option
                    } label: {
                        if filters.sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Sort by")
            }
            Menu {
                ForEach(SearchVideoFilters.ResultType.allCases) { option in
                    Button {
                        filters.resultType = option
                    } label: {
                        if filters.resultType == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Type")
            }
            Menu {
                ForEach(SearchVideoFilters.Watch.allCases) { option in
                    Button {
                        filters.watch = option
                    } label: {
                        if filters.watch == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Watch history")
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
                        if filters.uploaded == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Upload date")
            }
            .disabled(!filters.resultType.supportsVideoConstraints)
            Menu {
                ForEach(SearchVideoFilters.Length.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomLength()
                        } else {
                            filters.length = option
                        }
                    } label: {
                        if filters.length == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Length")
            }
            .disabled(!filters.resultType.supportsVideoConstraints)
            Menu {
                ForEach(SearchVideoFilters.Views.allCases) { option in
                    Button {
                        if option == .custom {
                            onCustomViews()
                        } else {
                            filters.views = option
                        }
                    } label: {
                        if filters.views == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Views")
            }
            .disabled(!filters.resultType.supportsVideoConstraints)
            Divider()
            Button("Reset Filters") {
                filters = SearchVideoFilters()
            }
            .disabled(!filters.isActive)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
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
