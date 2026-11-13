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
        removeLegacyYtDlpModule()
        migrateLegacyDiagnostics()
        scrubLegacySignedDownloadURLs()
        return true
    }()

    /// Older builds downloaded an executable Python module into Application Support.
    private static func removeLegacyYtDlpModule() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent("io.github.kewlbear.youtubedl-ios", isDirectory: true)
        let module = directory.appendingPathComponent("yt_dlp")
        try? FileManager.default.removeItem(at: module)
        // This only succeeds when the dependency's directory is empty.
        try? FileManager.default.removeItem(at: directory)
    }

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

    /// Query strings on media URLs can contain CDN authorization material.
    static func redactedForLog(_ url: URL?) -> String {
        guard let url else { return "?" }
        var value = url.scheme.map { "\($0)://" } ?? ""
        value += url.host ?? "?"
        if let port = url.port { value += ":\(port)" }
        value += url.path
        if url.query != nil { value += "?…" }
        return value
    }

    /// Prefer domain/code over `String(describing:)` — NSError userInfo can embed signed URLs.
    static func redactedForLog(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["domain=\(nsError.domain) code=\(nsError.code)"]
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)/\(underlying.code)")
        }
        return parts.joined(separator: " ")
    }

    /// Defense-in-depth for mirrored file logs: strip query strings from any http(s) URL.
    static func sanitizeLogMessage(_ message: String) -> String {
        guard message.contains("://") || message.contains("?") else { return message }
        guard let regex = urlRegex else { return message }
        let nsMessage = message as NSString
        let full = NSRange(location: 0, length: nsMessage.length)
        let matches = regex.matches(in: message, options: [], range: full)
        guard !matches.isEmpty else { return message }

        var result = message
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let raw = String(result[range])
            if let url = URL(string: raw) {
                result.replaceSubrange(range, with: redactedForLog(url))
            } else if let queryIndex = raw.firstIndex(of: "?") {
                result.replaceSubrange(range, with: String(raw[..<queryIndex]) + "?…")
            }
        }
        return result
    }

    /// Signed stream / googlevideo URLs must not remain in download xattrs.
    static func isSensitiveMediaURLString(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            // Malformed values are safer cleared than left on disk.
            return true
        }
        if host.contains("googlevideo.com") { return true }
        if url.path.lowercased().contains("videoplayback") { return true }
        let query = url.query?.lowercased() ?? ""
        if query.contains("signature=") || query.contains("sig=") { return true }
        if query.contains("expire=") && query.contains("ip=") { return true }
        return false
    }

    private static let urlRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"https?://[^\s\]\)\"'<>]+"#,
        options: [.caseInsensitive]
    )

    private static let scrubSignedURLDefaultsKey = "com.leshko.freetube.scrubbedLegacySignedDownloadURLs.v1"

    /// One-shot: clear signed stream URLs left in download metadata by older builds.
    private static func scrubLegacySignedDownloadURLs() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: scrubSignedURLDefaultsKey) else { return }
        defaults.set(true, forKey: scrubSignedURLDefaultsKey)
        Task.detached(priority: .utility) {
            guard #available(iOS 17.0, *) else { return }
            let scrubbed = DownloadsStore.scrubSensitiveOriginalURLsOffMain()
            if scrubbed > 0 {
                await MainActor.run {
                    NotificationCenter.default.post(name: DownloadsStore.didChange, object: nil)
                }
            }
        }
    }
}
