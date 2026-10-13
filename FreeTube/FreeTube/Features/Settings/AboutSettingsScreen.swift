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
            } footer: {
                Text("An account-free YouTube client for personal use. Playback and downloads may break when YouTube changes its internal APIs.")
                Text("[freetube.io](https://freetube.io)")
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
