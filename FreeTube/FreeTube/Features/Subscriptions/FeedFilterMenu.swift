import SwiftUI

/// Feed filter controls; the screen owns the selected values and popover presentation.
@available(iOS 17.0, *)
struct FeedFilterMenu: View {
    @Binding var watchFilterRaw: String
    @Binding var durationFilterRaw: String
    @Binding var isWatchFilterPresented: Bool
    @Binding var isCustomDurationPresented: Bool

    private var watchFilter: FeedWatchFilter {
        FeedWatchFilter(rawValue: watchFilterRaw) ?? .all
    }

    private var durationFilter: FeedDurationFilter {
        FeedDurationFilter(rawValue: durationFilterRaw) ?? .all
    }

    var body: some View {
        Menu {
            Button {
                isWatchFilterPresented = true
            } label: {
                if watchFilter == .all {
                    Text("Watch status")
                } else {
                    Label("Watch status", systemImage: "checkmark")
                }
            }
            Menu {
                ForEach(FeedDurationFilter.allCases) { option in
                    Button {
                        if option == .custom {
                            isCustomDurationPresented = true
                        } else {
                            durationFilterRaw = option.rawValue
                        }
                    } label: {
                        if durationFilter == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                if durationFilter == .all {
                    Text("Duration")
                } else {
                    Label("Duration", systemImage: "checkmark")
                }
            }
            if watchFilter != .all || durationFilter != .all {
                Divider()
                Button("Reset Filters") {
                    watchFilterRaw = FeedWatchFilter.all.rawValue
                    durationFilterRaw = FeedDurationFilter.all.rawValue
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if watchFilter != .all || durationFilter != .all {
                        Circle()
                            .fill(.primary)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .accessibilityLabel("Feed filters")
        .accessibilityValue(watchFilter == .all && durationFilter == .all ? "Off" : "On")
        .popover(isPresented: $isWatchFilterPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Watch status")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                ForEach(FeedWatchFilter.allCases) { option in
                    Button {
                        watchFilterRaw = option.rawValue
                        isWatchFilterPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.title)
                            Spacer(minLength: 8)
                            if watchFilter == option {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    if option != FeedWatchFilter.allCases.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .frame(width: 270)
            .padding(.bottom, 6)
            .presentationCompactAdaptation(.popover)
        }
    }
}
