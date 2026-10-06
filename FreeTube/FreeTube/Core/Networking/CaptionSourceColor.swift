import Foundation

/// Converts source caption foreground colors to RGB without pulling UI types into the service layer.
enum CaptionSourceColor {
    static func rgb(from value: Any?) -> UInt32? {
        if let number = value as? NSNumber {
            let raw = number.int64Value
            return (0...0xFFFFFF).contains(raw) ? UInt32(raw) : nil
        }
        guard let value = value as? String else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let named: [String: UInt32] = [
            "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000,
            "green": 0x008000, "lime": 0x00FF00, "blue": 0x0000FF,
            "yellow": 0xFFFF00, "cyan": 0x00FFFF, "magenta": 0xFF00FF
        ]
        if let color = named[raw] { return color }
        if raw.hasPrefix("rgb("), raw.hasSuffix(")") {
            let values = raw.dropFirst(4).dropLast().split(separator: ",")
                .compactMap { UInt8(String($0).trimmingCharacters(in: .whitespaces)) }
            guard values.count == 3 else { return nil }
            return UInt32(values[0]) << 16 | UInt32(values[1]) << 8 | UInt32(values[2])
        }
        if !raw.hasPrefix("#"), !raw.hasPrefix("0x"), raw.count > 6,
           let decimal = UInt32(raw), decimal <= 0xFFFFFF {
            return decimal
        }
        let hex = raw.hasPrefix("#") ? String(raw.dropFirst())
            : raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
        if hex.count == 3, let value = UInt32(hex, radix: 16) {
            let r = (value >> 8) & 0xF
            let g = (value >> 4) & 0xF
            let b = value & 0xF
            return (r * 17) << 16 | (g * 17) << 8 | (b * 17)
        }
        if hex.count == 6, let value = UInt32(hex, radix: 16) { return value }
        if hex.count == 8 { return UInt32(hex.prefix(6), radix: 16) }
        return nil
    }
}
