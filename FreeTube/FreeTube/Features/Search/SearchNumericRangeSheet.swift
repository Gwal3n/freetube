import SwiftUI

/// Native numeric interval editor shared by the local duration and view-count filters.
/// One dual-thumb slider snaps to round stops; text fields stay available for exact values.
/// Duration custom ranges are stored and applied in seconds. The trailing stop is Unlimited.
@available(iOS 17.0, *)
struct SearchNumericRangeSheet: View {
    enum Kind: Equatable {
        case duration
        case views

        var title: String {
            switch self {
            case .duration: "Duration Range"
            case .views: "View Count Range"
            }
        }
    }

    private enum DurationUnit: String, CaseIterable, Identifiable {
        case minutes, seconds
        var id: String { rawValue }
        var label: String {
            switch self {
            case .minutes: "Minutes"
            case .seconds: "Seconds"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var lowerIndex: Double
    @State private var upperIndex: Double
    @State private var durationUnit: DurationUnit

    let kind: Kind
    let onApply: (SearchVideoFilters.NumericRange) -> Void

    init(
        kind: Kind,
        range: SearchVideoFilters.NumericRange?,
        onApply: @escaping (SearchVideoFilters.NumericRange) -> Void
    ) {
        self.kind = kind
        self.onApply = onApply
        let unit: DurationUnit = .minutes
        _durationUnit = State(initialValue: unit)
        let stops = Self.stops(for: kind, unit: unit)
        let minimumStored = max(0, range?.minimum ?? 0)
        let maximumStored = range?.maximum
        let minimumDisplay = kind == .duration
            ? Self.displayValue(seconds: minimumStored, unit: unit)
            : minimumStored
        let maximumDisplay = maximumStored.map {
            kind == .duration ? Self.displayValue(seconds: $0, unit: unit) : $0
        }
        _minimumText = State(initialValue: String(minimumDisplay))
        _maximumText = State(initialValue: maximumDisplay.map(String.init) ?? "")
        _lowerIndex = State(initialValue: Double(Self.nearestStopIndex(minimumDisplay, in: stops)))
        _upperIndex = State(
            initialValue: maximumDisplay.map { Double(Self.nearestStopIndex($0, in: stops)) }
                ?? Double(stops.count) // Unlimited
        )
    }

    private var stops: [Int] {
        Self.stops(for: kind, unit: durationUnit)
    }

    /// Finite stops plus one Unlimited slot at `stops.count`.
    private var maxIndex: Double {
        Double(stops.count)
    }

    private var minimumDisplay: Int? {
        Int(minimumText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var maximumDisplay: Int? {
        let text = maximumText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Int(text)
    }

    private var maximumIsUnlimited: Bool {
        maximumDisplay == nil || Int(upperIndex.rounded()) >= stops.count
    }

    private var canApply: Bool {
        guard let minimumDisplay, minimumDisplay >= 0 else { return false }
        guard let maximumDisplay else { return true }
        return maximumDisplay >= minimumDisplay
    }

    private var unitLabel: String {
        switch kind {
        case .duration: durationUnit.label
        case .views: "Views"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .duration {
                    Section {
                        Picker("Unit", selection: $durationUnit) {
                            ForEach(DurationUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: durationUnit) { oldUnit, newUnit in
                            convertDisplayedValues(from: oldUnit, to: newUnit)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Minimum")
                        Spacer()
                        TextField("0", text: $minimumText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityLabel("Minimum \(unitLabel)")
                    }
                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("Unlimited", text: $maximumText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityLabel("Maximum \(unitLabel)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SearchNumericRangeSlider(
                            lower: lowerBinding,
                            upper: upperBinding,
                            lowerAccessibilityValue: minimumDisplay.map(Self.formatStop) ?? "0",
                            upperAccessibilityValue: maximumIsUnlimited
                                ? "Unlimited"
                                : (maximumDisplay.map(Self.formatStop) ?? "Unlimited")
                        )
                        HStack {
                            Text(verbatim: formatLeadingStop)
                            Spacer()
                            Text("Unlimited")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text(unitLabel)
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard canApply, let minimumDisplay else { return }
                        onApply(
                            .init(
                                minimum: storedValue(fromDisplay: minimumDisplay),
                                maximum: maximumDisplay.map { storedValue(fromDisplay: $0) }
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
            .onChange(of: minimumText) { _, _ in syncLowerFromText() }
            .onChange(of: maximumText) { _, _ in syncUpperFromText() }
        }
        .presentationDetents([.medium, .large])
    }

    private var formatLeadingStop: String {
        stops.first.map(Self.formatStop) ?? "0"
    }

    private var footerText: String {
        switch kind {
        case .duration:
            return "Drag either end of the range. Stops are logarithmic round values; the right end is Unlimited. Switch between minutes and seconds above, or type an exact value."
        case .views:
            return "Drag either end of the range. Stops snap to round view counts; the right end is Unlimited. Type an exact count when you need one."
        }
    }

    private var lowerBinding: Binding<Double> {
        Binding(
            get: { lowerIndex / maxIndex },
            set: { normalized in
                let index = snapIndex(normalized * maxIndex, upperBound: upperIndex)
                lowerIndex = min(index, Double(stops.count - 1))
                applyLowerIndex()
            }
        )
    }

    private var upperBinding: Binding<Double> {
        Binding(
            get: { upperIndex / maxIndex },
            set: { normalized in
                let index = snapIndex(normalized * maxIndex, lowerBound: lowerIndex)
                upperIndex = max(index, 0)
                applyUpperIndex()
            }
        )
    }

    private func snapIndex(_ raw: Double, lowerBound: Double? = nil, upperBound: Double? = nil) -> Double {
        var index = raw.rounded()
        if let lowerBound { index = max(index, lowerBound.rounded()) }
        if let upperBound { index = min(index, upperBound.rounded()) }
        return min(maxIndex, max(0, index))
    }

    private func syncLowerFromText() {
        guard let minimumDisplay, minimumDisplay >= 0 else { return }
        let index = Double(Self.nearestStopIndex(minimumDisplay, in: stops))
        lowerIndex = min(index, upperIndex, Double(stops.count - 1))
    }

    private func syncUpperFromText() {
        let text = maximumText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            upperIndex = maxIndex
            return
        }
        guard let maximumDisplay, maximumDisplay >= 0 else { return }
        let index = Double(Self.nearestStopIndex(maximumDisplay, in: stops))
        upperIndex = max(index, lowerIndex)
    }

    private func applyLowerIndex() {
        let idx = Int(lowerIndex.rounded())
        guard stops.indices.contains(idx) else { return }
        minimumText = String(stops[idx])
    }

    private func applyUpperIndex() {
        let idx = Int(upperIndex.rounded())
        if idx >= stops.count {
            maximumText = ""
            return
        }
        guard stops.indices.contains(idx) else { return }
        maximumText = String(stops[idx])
    }

    private func convertDisplayedValues(from oldUnit: DurationUnit, to newUnit: DurationUnit) {
        guard kind == .duration, oldUnit != newUnit else { return }
        if let minimumDisplay {
            let seconds = Self.seconds(fromDisplay: minimumDisplay, unit: oldUnit)
            let converted = Self.displayValue(seconds: seconds, unit: newUnit)
            minimumText = String(converted)
        }
        if let maximumDisplay {
            let seconds = Self.seconds(fromDisplay: maximumDisplay, unit: oldUnit)
            let converted = Self.displayValue(seconds: seconds, unit: newUnit)
            maximumText = String(converted)
        } else {
            maximumText = ""
        }
        let newStops = Self.stops(for: .duration, unit: newUnit)
        if let minimumDisplay = Int(minimumText) {
            lowerIndex = Double(Self.nearestStopIndex(minimumDisplay, in: newStops))
        }
        if maximumText.isEmpty {
            upperIndex = Double(newStops.count)
        } else if let maximumDisplay = Int(maximumText) {
            upperIndex = Double(Self.nearestStopIndex(maximumDisplay, in: newStops))
        }
        lowerIndex = min(lowerIndex, upperIndex, Double(newStops.count - 1))
        upperIndex = max(upperIndex, lowerIndex)
    }

    private func storedValue(fromDisplay value: Int) -> Int {
        switch kind {
        case .duration: Self.seconds(fromDisplay: value, unit: durationUnit)
        case .views: value
        }
    }

    private static func seconds(fromDisplay value: Int, unit: DurationUnit) -> Int {
        switch unit {
        case .minutes: value * 60
        case .seconds: value
        }
    }

    private static func displayValue(seconds: Int, unit: DurationUnit) -> Int {
        switch unit {
        case .minutes: Int((Double(seconds) / 60.0).rounded())
        case .seconds: seconds
        }
    }

    private static func nearestStopIndex(_ value: Int, in stops: [Int]) -> Int {
        guard let first = stops.first else { return 0 }
        if value <= first { return 0 }
        if let last = stops.last, value >= last { return stops.count - 1 }
        var best = 0
        var bestDistance = Int.max
        for (index, stop) in stops.enumerated() {
            let distance = abs(stop - value)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func stops(for kind: Kind, unit: DurationUnit) -> [Int] {
        switch kind {
        case .views:
            return [0, 100, 500, 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000, 10_000_000]
        case .duration:
            switch unit {
            case .minutes:
                return [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
            case .seconds:
                return [0, 15, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1_200, 1_800, 3_600, 7_200]
            }
        }
    }

    private static func formatStop(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            let millions = Double(value) / 1_000_000
            return millions.rounded() == millions ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        case 1_000...:
            let thousands = Double(value) / 1_000
            return thousands.rounded() == thousands ? "\(Int(thousands))K" : String(format: "%.1fK", thousands)
        default:
            return value.formatted()
        }
    }
}
