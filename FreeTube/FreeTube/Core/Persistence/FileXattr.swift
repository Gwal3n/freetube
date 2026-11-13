import Foundation

/// POSIX xattr helpers. Always use `fileSystemRepresentation` (not `URL.path`) for APFS paths.
enum FileXattr {
    static func read(key: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { cPath -> Data? in
            guard let cPath else { return nil }
            let length = getxattr(cPath, key, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let actual = data.withUnsafeMutableBytes { buf -> ssize_t in
                guard let base = buf.baseAddress else { return -1 }
                return getxattr(cPath, key, base, length, 0, 0)
            }
            guard actual == length else { return nil }
            return data
        }
    }

    /// Write (or replace) an extended attribute. Throws on any failure so callers can log.
    static func write(_ data: Data, key: String, at url: URL) throws {
        let status = url.withUnsafeFileSystemRepresentation { cPath -> Int32 in
            guard let cPath else { return -1 }
            return data.withUnsafeBytes { buf -> Int32 in
                guard let base = buf.baseAddress else { return -1 }
                return setxattr(cPath, key, base, buf.count, 0, 0)
            }
        }
        if status != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "setxattr(\(key)) failed for \(url.lastPathComponent)"
            ])
        }
    }

    /// Remove an attribute. No-op when the attribute doesn't exist (matches the
    /// ObjC reference implementation that early-returns success in that case).
    static func remove(key: String, at url: URL) {
        url.withUnsafeFileSystemRepresentation { cPath in
            guard let cPath else { return }
            _ = removexattr(cPath, key, 0)
        }
    }
}
