import SwiftUI

/// Temporary, data-free navigation test presented from RootView rather than Library's stack.
/// If this also fails, the issue is above the Library/Settings feature views.
@available(iOS 17.0, *)
struct NavigationProbeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Int] = []
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "NavigationProbe")

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button("Push with path") {
                        log.info("Root probe path button requested depth=\(path.count)")
                        path.append(1)
                        log.info("Root probe path appended depth=\(path.count)")
                    }

                    NavigationLink("Push with native link") {
                        probeDestination("Native link")
                    }
                } footer: {
                    Text("If either row opens a page saying Navigation succeeded, the root-level stack works.")
                }
            }
            .navigationTitle("Navigation probe")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Int.self) { _ in
                probeDestination("Path push")
            }
            .onAppear { log.info("Root probe appeared") }
            .onDisappear { log.info("Root probe root disappeared") }
        }
        .onChange(of: path.count) { previous, current in
            log.info("Root probe path rendered: \(previous) → \(current)")
        }
    }

    private func probeDestination(_ kind: String) -> some View {
        Text("Navigation succeeded")
            .navigationTitle(kind)
            .onAppear { log.info("Root probe destination appeared: \(kind)") }
            .onDisappear { log.info("Root probe destination disappeared: \(kind)") }
    }
}
