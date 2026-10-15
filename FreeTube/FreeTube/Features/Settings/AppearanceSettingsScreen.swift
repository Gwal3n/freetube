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
                .settingsSearchRow("Appearance")
                Picker("Accent color", selection: $appAccentPresetRaw) {
                    ForEach(AppAccentPreset.allCases) { preset in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 18, height: 18)
                            Text(preset.label)
                                .foregroundStyle(.primary)
                        }
                        .tag(preset.rawValue)
                    }
                }
                .settingsSearchRow("Accent color")
                Picker("Text font", selection: Bindable(model).appFontPreset) {
                    ForEach(AppFontPreset.allCases) { preset in
                        preset.label
                            .font(preset.font(.body))
                            .tag(preset)
                    }
                }
                .settingsSearchRow("Text font")
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
                .settingsSearchRow("Tab Bar")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
