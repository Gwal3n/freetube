import SwiftUI

@available(iOS 17.0, *)
struct AppearanceSettingsScreen: View {
    let model: SettingsViewModel
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceModeRaw) {
                    Text("System").tag(AppearanceMode.system.rawValue)
                    Text("Light").tag(AppearanceMode.light.rawValue)
                    Text("Dark").tag(AppearanceMode.dark.rawValue)
                }
                Picker("Text font", selection: Bindable(model).appFontPreset) {
                    ForEach(AppFontPreset.allCases) { preset in
                        preset.label
                            .font(preset.font(.body))
                            .tag(preset)
                    }
                }
            } footer: {
                Text("The video player keeps a dark canvas in every appearance.")
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
