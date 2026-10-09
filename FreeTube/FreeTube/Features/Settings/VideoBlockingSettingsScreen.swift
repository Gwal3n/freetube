import SwiftUI

/// Native, device-local controls for hiding unwanted public content. Saved data is untouched.
@available(iOS 17.0, *)
struct VideoBlockingSettingsScreen: View {
    @State private var blocklist = VideoBlocklist.shared
    @State private var keywordInput = ""
    @State private var channelInput = ""

    var body: some View {
        Form {
            Section {
                Toggle("Hide Shorts", isOn: Binding(
                    get: { blocklist.hideShorts },
                    set: { blocklist.hideShorts = $0 }
                ))
            } footer: {
                Text("Shorts are hidden where YouTube identifies a video as a Short.")
            }

            Section {
                HStack {
                    TextField("Keyword in title", text: $keywordInput)
                        .submitLabel(.done)
                        .onSubmit(addKeyword)
                    Button(action: addKeyword) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(keywordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add blocked keyword")
                }
                ForEach(blocklist.rules.keywords, id: \.self) { keyword in
                    Text(verbatim: keyword)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        blocklist.removeKeyword(blocklist.rules.keywords[index])
                    }
                }
            } header: {
                Text("Blocked keywords")
            } footer: {
                Text("Matches words or phrases anywhere in a video or playlist title, ignoring case.")
            }

            Section {
                HStack {
                    TextField("Channel name or ID", text: $channelInput)
                        .submitLabel(.done)
                        .onSubmit(addChannel)
                    Button(action: addChannel) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(channelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add blocked channel")
                }
                ForEach(blocklist.rules.channels) { channel in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: channel.name)
                        if let id = channel.channelID, id != channel.name {
                            Text(verbatim: id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        blocklist.removeChannel(blocklist.rules.channels[index])
                    }
                }
            } header: {
                Text("Blocked channels")
            } footer: {
                Text("Enter an exact channel name, channel ID, or YouTube /channel/ link. You can also block a channel from its page. Swipe a rule left to remove it.")
            }
        }
        .navigationTitle("Blocked content")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addKeyword() {
        if blocklist.addKeyword(keywordInput) { keywordInput = "" }
    }

    private func addChannel() {
        if blocklist.addChannel(channelInput) { channelInput = "" }
    }
}
