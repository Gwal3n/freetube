import SwiftUI
import UIKit

enum WatchIndicatorStyle {
    enum ColorMode: String, CaseIterable {
        case red, accent, custom
    }

    enum FinishedMode: String, CaseIterable {
        case fullBar, checkmark, none
    }

    static func color(mode: ColorMode, accent: AppAccentPreset, accentHex: String, customHex: String) -> Color {
        switch mode {
        case .red: .red
        case .accent: accent.color(customHex: accentHex)
        case .custom: color(hex: customHex) ?? .red
        }
    }

    static func color(hex: String) -> Color? {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        return Color(red: Double((number >> 16) & 0xff) / 255,
                     green: Double((number >> 8) & 0xff) / 255,
                     blue: Double(number & 0xff) / 255)
    }

    static func hex(color: Color) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#FF0000"
        }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()),
                      Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
