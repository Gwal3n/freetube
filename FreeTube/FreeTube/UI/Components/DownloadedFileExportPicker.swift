import SwiftUI
import UIKit

/// The system Files export picker can copy an existing large video directly, unlike a
/// `FileDocument` export that would require wrapping the entire file in app-managed data.
@available(iOS 17.0, *)
struct DownloadedFileExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDismiss()
        }
    }
}
