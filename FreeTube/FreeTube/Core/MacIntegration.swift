import Foundation

/// Mac-only helpers (Designed for iPad / Catalyst). No-ops on iPhone/iPad.
enum MacIntegration {
    static var isRunningOnMac: Bool {
        let info = ProcessInfo.processInfo
        return info.isMacCatalystApp || info.isiOSAppOnMac
    }

    /// Reveals a file in Finder via runtime `NSWorkspace` lookup (no AppKit import).
    static func revealInFinder(_ url: URL) {
        guard isRunningOnMac else { return }
        guard let workspaceClass = NSClassFromString("NSWorkspace") as? NSObject.Type else { return }
        let sel = NSSelectorFromString("sharedWorkspace")
        let workspace = workspaceClass.perform(sel)?.takeUnretainedValue() as? NSObject
        _ = workspace?.perform(
            NSSelectorFromString("activateFileViewerSelectingURLs:"),
            with: [url] as NSArray
        )
    }
}
