import SwiftUI
import UIKit

// MARK: - Font presets

@available(iOS 17.0, *)
extension AppFontPreset {
    var label: Text {
        switch self {
        case .system: Text("System")
        case .rounded: Text("Rounded")
        case .serif: Text("Serif")
        case .helveticaNeue: Text(verbatim: "Helvetica Neue")
        case .avenirNext: Text(verbatim: "Avenir Next")
        }
    }

    /// Semantic sizes keep every preset aligned with Dynamic Type instead of freezing text at
    /// one point size. System designs use Apple's own font metrics; named iOS fonts scale against
    /// the same text style via `Font.custom(_:size:relativeTo:)`.
    func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            .system(style, design: .default, weight: weight)
        case .rounded:
            .system(style, design: .rounded, weight: weight)
        case .serif:
            .system(style, design: .serif, weight: weight)
        case .helveticaNeue, .avenirNext:
            .custom(postScriptName(for: weight), size: style.basePointSize, relativeTo: style)
        }
    }

    /// The selectable comment body is UIKit-backed for native text selection. Apply the same
    /// preset there, with UIKit's Dynamic Type metrics, so it matches surrounding SwiftUI text.
    func uiFont(style: UIFont.TextStyle, size: CGFloat) -> UIFont {
        if self == .system { return .preferredFont(forTextStyle: style) }
        if self == .rounded || self == .serif {
            let design: UIFontDescriptor.SystemDesign = self == .rounded ? .rounded : .serif
            let base = UIFont.systemFont(ofSize: size)
            let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
            return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
        }
        let base = UIFont(name: postScriptName(for: .regular), size: size)
            ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    private func postScriptName(for weight: Font.Weight) -> String {
        let bold = weight == .bold || weight == .heavy || weight == .black
        switch self {
        case .avenirNext:
            if bold { return "AvenirNext-Bold" }
            if weight == .semibold { return "AvenirNext-DemiBold" }
            if weight == .medium { return "AvenirNext-Medium" }
            return "AvenirNext-Regular"
        case .helveticaNeue:
            return bold ? "HelveticaNeue-Bold" :
                (weight == .medium || weight == .semibold ? "HelveticaNeue-Medium" : "HelveticaNeue")
        case .system, .rounded, .serif:
            return ""
        }
    }
}

@available(iOS 17.0, *)
private extension Font.TextStyle {
    var basePointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

// MARK: - Content font modifier

/// One place for content typography. It intentionally does not replace navigation bars, system
/// menus, transport glyphs, or the player's monospaced timeline numbers.
@available(iOS 17.0, *)
private struct AppFontModifier: ViewModifier {
    @Environment(\.appFontPreset) private var preset
    let style: Font.TextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(preset.font(style, weight: weight))
    }
}

@available(iOS 17.0, *)
extension View {
    func appFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(style: style, weight: weight))
    }
}
