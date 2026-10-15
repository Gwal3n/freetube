import SwiftUI

@available(iOS 17.0, *)
struct CaptionsSettingsScreen: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Dark caption background", isOn: Bindable(model).captionBackgroundEnabled)
                    .settingsSearchRow("Dark caption background")
                Toggle("Use source formatting", isOn: Bindable(model).formattedCaptions)
                    .settingsSearchRow("Use source formatting")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Caption text size")
                        Spacer()
                        Text(verbatim: "\(Int((model.captionTextScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Bindable(model).captionTextScale, in: 0.8...1.5, step: 0.1)
                        .accessibilityLabel("Caption text size")
                }
                .settingsSearchRow("Caption text size")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Captions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
