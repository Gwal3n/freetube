import Foundation

/// Process-wide privacy defaults that must be established before logging or networking starts.
nonisolated enum SecurityHardening {
    static func configureAtLaunch() {
        _ = configured
    }

    private static let configured: Bool = {
        lockDownSharedCookieJar()
        migrateLegacyDiagnostics()
        return true
    }()

    /// YouTube requests supply their Cookie header explicitly from Keychain. The shared jar has no
    /// legitimate role and otherwise persists rotated response cookies outside that store.
    private static func lockDownSharedCookieJar() {
        let jar = HTTPCookieStorage.shared
        jar.cookieAcceptPolicy = .never
        purgeSharedCookieJar()
    }

    static func purgeSharedCookieJar() {
        let jar = HTTPCookieStorage.shared
        for cookie in jar.cookies ?? [] {
            jar.deleteCookie(cookie)
        }
    }

    /// Diagnostic files stay private until the user explicitly shares them from Settings.
    static let diagnosticsDirectory: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Preserve existing tester logs while removing them from the Files-visible Documents folder.
    private static func migrateLegacyDiagnostics() {
        let fileManager = FileManager.default
        let legacy = AppDirectories.documents.appendingPathComponent("Logs", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        let files = (try? fileManager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: nil
        )) ?? []
        for source in files {
            var destination = diagnosticsDirectory.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                destination = diagnosticsDirectory.appendingPathComponent(
                    "migrated-\(UUID().uuidString)-\(source.lastPathComponent)"
                )
            }
            try? fileManager.moveItem(at: source, to: destination)
        }
        try? fileManager.removeItem(at: legacy)
    }

    /// Query strings on login and media URLs can contain session or CDN authorization material.
    static func redactedForLog(_ url: URL?) -> String {
        guard let url else { return "?" }
        var value = url.scheme.map { "\($0)://" } ?? ""
        value += url.host ?? "?"
        if let port = url.port { value += ":\(port)" }
        value += url.path
        if url.query != nil { value += "?…" }
        return value
    }
}
