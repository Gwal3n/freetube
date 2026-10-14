import SwiftUI

@available(iOS 17.0, *)
struct AppearanceSettingsScreen: View {
    let model: SettingsViewModel
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue
    @AppStorage("appAccentPreset") private var appAccentPresetRaw = AppAccentPreset.classic.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceModeRaw) {
                    Text("System").tag(AppearanceMode.system.rawValue)
                    Text("Light").tag(AppearanceMode.light.rawValue)
                    Text("Dark").tag(AppearanceMode.dark.rawValue)
                }
                Picker("Accent color", selection: $appAccentPresetRaw) {
                    ForEach(AppAccentPreset.allCases) { preset in
                        Label {
                            Text(preset.label)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(preset.color)
                        }
                        .tag(preset.rawValue)
                    }
                }
                Picker("Text font", selection: Bindable(model).appFontPreset) {
                    ForEach(AppFontPreset.allCases) { preset in
                        preset.label
                            .font(preset.font(.body))
                            .tag(preset)
                    }
                }
            } footer: {
                Text("The player interface follows your appearance; the video canvas stays black.")
            }

            Section("Navigation") {
                NavigationLink {
                    TabBarSettingsScreen()
                } label: {
                    Label("Tab Bar", systemImage: "square.grid.2x2")
                }
                .tint(.primary)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
