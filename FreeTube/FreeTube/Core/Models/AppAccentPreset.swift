import SwiftUI
import UIKit

/// Adaptive system tints for optional accented app chrome. Semantic LIVE colors remain fixed;
/// watch progress can follow this tint only when that separate preference is selected.
enum AppAccentPreset: String, CaseIterable, Identifiable {
    case classic
    case blue
    case indigo
    case teal
    case green
    case orange
    case purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .classic: Color(uiColor: .systemRed)
        case .blue: Color(uiColor: .systemBlue)
        case .indigo: Color(uiColor: .systemIndigo)
        case .teal: Color(uiColor: .systemTeal)
        case .green: Color(uiColor: .systemGreen)
        case .orange: Color(uiColor: .systemOrange)
        case .purple: Color(uiColor: .systemPurple)
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .classic: "Classic red"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .teal: "Teal"
        case .green: "Green"
        case .orange: "Orange"
        case .purple: "Purple"
        }
    }
}
