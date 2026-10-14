import SwiftUI

@available(iOS 17.0, *)
struct DownloadsSettingsScreen: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("Default download quality", selection: Bindable(model).defaultDownloadQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        switch quality {
                        case .auto:
                            Text("Automatic (up to 1080p)").tag(quality)
                        case .audioOnly:
                            Text("Audio only").tag(quality)
                        default:
                            Text("Up to \(quality.displayName)").tag(quality)
                        }
                    }
                }
                Toggle("Allow cellular data", isOn: Bindable(model).allowCellularDownloads)
                Picker("Parallel fragments", selection: Bindable(model).concurrentFragments) {
                    ForEach([1, 2, 4, 8, 16], id: \.self) { value in
                        Text(value == 1 ? "1 (sequential)" : "\(value)").tag(value)
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist downloads use the default quality. You can still choose a different quality for each individual video.")
                    DownloadsSettingsFooter()
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
    }
}
