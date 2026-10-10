import Foundation

/// Custom playback speeds are stored as a small, locale-independent list of decimal values.
/// Playback itself remains owned by `PlayerStateManager` and accepts the same 0.25×–2× range.
@available(iOS 17.0, *)
enum PlaybackSpeedPresets {
    static let quickRates: [Double] = [0.5, 1, 1.25, 1.5, 2]
    static let settingsRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    static func parse(_ text: String) -> Double? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(input), value.isFinite, (0.25...2).contains(value) else {
            return nil
        }
        let hundredths = value * 100
        guard abs(hundredths - hundredths.rounded()) < 0.000_001 else { return nil }
        return hundredths.rounded() / 100
    }

    static func decode(_ raw: String) -> [Double] {
        Array(Set(raw.split(separator: ";").compactMap { parse(String($0)) })).sorted()
    }

    static func encode(_ rates: [Double]) -> String {
        Array(Set(rates)).sorted().map { String($0) }.joined(separator: ";")
    }

    static func label(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
