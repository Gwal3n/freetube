import SwiftUI

/// App-wide default: indeterminate spinners stay neutral gray instead of inheriting the accent
/// tint, while determinate bars keep it. A spinner that must stay white over video sets
/// `.progressViewStyle(.circular)` explicitly, which takes precedence over this default.
struct NeutralSpinnerProgressViewStyle: ProgressViewStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if configuration.fractionCompleted == nil {
            ProgressView(configuration)
                .progressViewStyle(.circular)
                .tint(.secondary)
        } else {
            ProgressView(configuration)
                .progressViewStyle(.linear)
        }
    }
}
