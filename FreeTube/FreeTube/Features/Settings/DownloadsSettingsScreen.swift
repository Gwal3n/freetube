import SwiftUI

@available(iOS 17.0, *)
struct DownloadsSettingsScreen: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Allow cellular data", isOn: Bindable(model).allowCellularDownloads)
                Picker("Parallel fragments", selection: Bindable(model).concurrentFragments) {
                    ForEach([1, 2, 4, 8, 16], id: \.self) { value in
                        Text(value == 1 ? "1 (sequential)" : "\(value)").tag(value)
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                DownloadsSettingsFooter()
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
    }
}
