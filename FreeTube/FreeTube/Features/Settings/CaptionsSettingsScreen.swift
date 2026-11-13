import SwiftUI

@available(iOS 17.0, *)
struct CaptionsSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Dark background", isOn: Bindable(model).captionBackgroundEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Dark background")
                Toggle("Keep original formatting", isOn: Bindable(model).formattedCaptions)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Keep original formatting")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Text size")
                        Spacer()
                        Text(verbatim: "\(Int((model.captionTextScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Bindable(model).captionTextScale, in: 0.8...1.5, step: 0.1)
                        .tint(.blue)
                        .accessibilityLabel("Text size")
                }
                .settingsSearchRow("Text size")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Captions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
