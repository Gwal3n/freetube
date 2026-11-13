import SwiftUI

@available(iOS 17.0, *)
struct AboutSettingsScreen: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(appVersion).monospacedDigit()
                }
                LabeledContent("Build") {
                    Text(appBuild).monospacedDigit()
                }
                LabeledContent("Revision") {
                    Text(appRevision)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Source") {
                Text("[Project on GitHub](https://github.com/Gwal3n/freetube)")
                Text("[Original project by Leshko](https://github.com/leshkodev/freetube)")
                Text("[MIT license](https://github.com/Gwal3n/freetube/blob/main/LICENSE)")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var appRevision: String {
        guard let revision = Bundle.main.infoDictionary?["FreeTubeCommit"] as? String,
              !revision.isEmpty else { return "local" }
        return revision
    }
}
