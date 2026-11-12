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
            // A fixed square that fits either symbol keeps the button from resizing when the
            // source changes, so the List row never re-measures.
            Image(systemName: filters.source == .music ? "music.note" : "line.3.horizontal.decrease")
                .frame(width: 24, height: 24)
        }
        .modifier(FilterButtonStyle())
        .overlay(alignment: .topTrailing) {
            if filters.isNarrowedBeyondType {
                Circle()
                    .fill(.tint)
                    .frame(width: 7, height: 7)
                    .allowsHitTesting(false)
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityLabel("Filter search videos")
        .accessibilityValue(filters.isNarrowedBeyondType ? "On" : "Off")
    }
}

/// The system's native glass circular button on iOS 26, like Feed's toolbar filter; earlier
/// systems show a plain icon there, so this does too.
@available(iOS 17.0, *)
private struct FilterButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            content
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
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
