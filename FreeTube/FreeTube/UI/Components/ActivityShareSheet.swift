import SwiftUI
import UIKit

/// `UIActivityViewController` bridge; needed for reliable `file://` share items.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        // Nothing to update — the activity controller doesn't accept post-creation changes.
    }
}
