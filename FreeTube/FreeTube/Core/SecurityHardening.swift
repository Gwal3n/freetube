import Foundation
import Security

/// Process-wide privacy defaults that must be established before logging or networking starts.
nonisolated enum SecurityHardening {
    static func configureAtLaunch() {
        _ = configured
    }

    private static let configured: Bool = {
        lockDownSharedCookieJar()
        removeLegacyAccountCredentials()
        migrateLegacyDiagnostics()
        return true
    }()

    /// FreeTube is account-free. Reject and erase any response cookies that Foundation might
    /// otherwise retain implicitly, even though app requests never provide account credentials.
    private static func lockDownSharedCookieJar() {
        let jar = HTTPCookieStorage.shared
        jar.cookieAcceptPolicy = .never
        purgeSharedCookieJar()
    }

    private static func purgeSharedCookieJar() {
        let jar = HTTPCookieStorage.shared
        for cookie in jar.cookies ?? [] {
            jar.deleteCookie(cookie)
        }
    }

    /// Account login is no longer part of FreeTube. Remove credentials left in the Keychain by
    /// older builds so an upgrade cannot silently resume an authenticated YouTube session.
    private static func removeLegacyAccountCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.leshko.freetube",
            kSecAttrAccount as String: "com.leshko.freetube.cookies",
        ]
        SecItemDelete(query as CFDictionary)
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
