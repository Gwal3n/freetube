import Foundation

/// User-editable choices shown in the player. The active timer itself is never persisted.
@available(iOS 17.0, *)
enum SleepTimerPresets {
    static let defaultMinutes = [15, 30, 60]
    static let minimumMinutes = 1
    static let maximumMinutes = 720
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter
    }()

    static func decode(_ raw: String) -> [Int] {
        guard !raw.isEmpty else { return defaultMinutes }
        let values = raw.split(separator: ",").compactMap { Int($0) }
            .filter { (minimumMinutes...maximumMinutes).contains($0) }
        return values.isEmpty ? defaultMinutes : Array(Set(values)).sorted()
    }

    static func encode(_ minutes: [Int]) -> String {
        Array(Set(minutes.filter { (minimumMinutes...maximumMinutes).contains($0) }))
            .sorted()
            .map(String.init)
            .joined(separator: ",")
    }

    static func parse(_ text: String) -> Int? {
        guard let minutes = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (minimumMinutes...maximumMinutes).contains(minutes) else { return nil }
        return minutes
    }

    static func label(_ minutes: Int) -> String {
        durationFormatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }
}
