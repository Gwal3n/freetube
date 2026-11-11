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
            case .minutes: String(localized: "Minutes")
            case .seconds: String(localized: "Seconds")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var lowerIndex: Int
    @State private var upperIndex: Int
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
        let minimumDisplay = kind == .duration
            ? Self.displayValue(seconds: minimumStored, unit: unit)
            : minimumStored
        let maximumDisplay = range?.maximum.map {
            kind == .duration ? Self.displayValue(seconds: $0, unit: unit) : $0
        }
        _minimumText = State(initialValue: Self.grouped(minimumDisplay))
        _maximumText = State(initialValue: maximumDisplay.map(Self.grouped) ?? "")
        let lower = min(Self.nearestStopIndex(minimumDisplay, in: stops), stops.count - 1)
        _lowerIndex = State(initialValue: lower)
        _upperIndex = State(
            initialValue: maximumDisplay.map { max(Self.nearestStopIndex($0, in: stops), lower) }
                ?? stops.count // Unlimited
        )
    }

    private var stops: [Int] {
        Self.stops(for: kind, unit: durationUnit)
    }

    /// Finite stops plus one Unlimited slot at `stops.count`.
    private var unlimitedIndex: Int {
        stops.count
    }

    private var minimumValue: Int? {
        Self.parse(minimumText)
    }

    private var maximumValue: Int? {
        Self.parse(maximumText)
    }

    private var canApply: Bool {
        guard let minimumValue, minimumValue >= 0 else { return false }
        guard let maximumValue else { return true }
        return maximumValue >= minimumValue
    }

    private var unitLabel: String {
        switch kind {
        case .duration: durationUnit.label
        case .views: String(localized: "Views")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        rangeSummary
                        SearchNumericRangeSlider(
                            lower: lowerBinding,
                            upper: upperBinding,
                            maxIndex: unlimitedIndex,
                            lowerAccessibilityValue: Self.grouped(minimumValue ?? 0),
                            upperAccessibilityValue: maximumValue.map(Self.grouped)
                                ?? String(localized: "Unlimited")
                        )
                        HStack {
                            Text(verbatim: stops.first.map(Self.abbreviated) ?? "0")
                            Spacer()
                            Text("Unlimited")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } header: {
                    HStack {
                        Text(kind == .duration ? String(localized: "Duration") : String(localized: "Views"))
                        Spacer()
                        if kind == .duration {
                            unitMenu
                        }
                    }
                }

                Section {
                    valueField("Minimum", placeholder: "0", text: $minimumText)
                    valueField("Maximum", placeholder: "Unlimited", text: $maximumText)
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
                        guard canApply, let minimumValue else { return }
                        onApply(
                            .init(
                                minimum: storedValue(fromDisplay: minimumValue),
                                maximum: maximumValue.map { storedValue(fromDisplay: $0) }
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
            .onChange(of: minimumText) { _, text in
                if reformat(text, into: $minimumText) { return }
                syncLowerFromText()
            }
            .onChange(of: maximumText) { _, text in
                if reformat(text, into: $maximumText) { return }
                syncUpperFromText()
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Subviews

    private var rangeSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if (minimumValue ?? 0) == 0, maximumValue == nil {
                Text("Any")
                    .font(.title3.weight(.semibold))
            } else {
                Text(verbatim: summaryValue)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(unitLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .animation(.snappy(duration: 0.2), value: summaryValue)
    }

    private var summaryValue: String {
        let low = Self.grouped(minimumValue ?? 0)
        guard let maximumValue else { return "\(low)+" }
        return "\(low) – \(Self.grouped(maximumValue))"
    }

    private var unitMenu: some View {
        Menu {
            Picker("Unit", selection: unitBinding) {
                ForEach(DurationUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(durationUnit.label)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote)
            .textCase(nil)
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Unit")
        .accessibilityValue(durationUnit.label)
    }

    private func valueField(
        _ title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        LabeledContent(title) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 140)
                .accessibilityLabel(Text(title) + Text(verbatim: " ") + Text(unitLabel))
        }
    }

    private var footerText: String {
        switch kind {
        case .duration:
            return String(localized: "Drag either end to snap to round lengths, or type an exact value.")
        case .views:
            return String(localized: "Drag either end to snap to round view counts, or type an exact count.")
        }
    }

    // MARK: - Bindings

    private var lowerBinding: Binding<Int> {
        Binding(
            get: { lowerIndex },
            set: { index in
                lowerIndex = min(max(0, index), upperIndex, unlimitedIndex - 1)
                minimumText = Self.grouped(stops[lowerIndex])
            }
        )
    }

    private var upperBinding: Binding<Int> {
        Binding(
            get: { upperIndex },
            set: { index in
                upperIndex = min(max(index, lowerIndex), unlimitedIndex)
                maximumText = upperIndex >= unlimitedIndex ? "" : Self.grouped(stops[upperIndex])
            }
        )
    }

    /// Converts the typed values and slider positions in the same update as the unit change, so
    /// the slider never renders indices from one unit against the other unit's stop count.
    private var unitBinding: Binding<DurationUnit> {
        Binding(
            get: { durationUnit },
            set: { newUnit in
                guard newUnit != durationUnit else { return }
                let oldUnit = durationUnit
                let minimumSeconds = minimumValue.map { Self.seconds(fromDisplay: $0, unit: oldUnit) }
                let maximumSeconds = maximumValue.map { Self.seconds(fromDisplay: $0, unit: oldUnit) }
                let newStops = Self.stops(for: kind, unit: newUnit)

                let minimum = minimumSeconds.map { Self.displayValue(seconds: $0, unit: newUnit) } ?? 0
                let lower = min(Self.nearestStopIndex(minimum, in: newStops), newStops.count - 1)
                var upper = newStops.count
                var maximumDisplay: Int?
                if let maximumSeconds {
                    let value = Self.displayValue(seconds: maximumSeconds, unit: newUnit)
                    maximumDisplay = value
                    upper = max(Self.nearestStopIndex(value, in: newStops), lower)
                }

                durationUnit = newUnit
                lowerIndex = lower
                upperIndex = upper
                minimumText = Self.grouped(minimum)
                maximumText = maximumDisplay.map(Self.grouped) ?? ""
            }
        )
    }

    // MARK: - Text sync

    /// Re-applies digit grouping to typed text. Returns true when the text was rewritten; the
    /// resulting change callback performs the slider sync.
    private func reformat(_ text: String, into binding: Binding<String>) -> Bool {
        let formatted = Self.parse(text).map(Self.grouped) ?? ""
        guard formatted != text else { return false }
        binding.wrappedValue = formatted
        return true
    }

    private func syncLowerFromText() {
        guard let minimumValue else { return }
        let index = Self.nearestStopIndex(minimumValue, in: stops)
        lowerIndex = min(index, upperIndex, unlimitedIndex - 1)
    }

    private func syncUpperFromText() {
        guard let maximumValue else {
            upperIndex = unlimitedIndex
            return
        }
        upperIndex = max(Self.nearestStopIndex(maximumValue, in: stops), lowerIndex)
    }

    // MARK: - Values

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

    /// Digits only; grouping separators and other typed characters are ignored.
    private static func parse(_ text: String) -> Int? {
        let digits = text.filter(\.isWholeNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits.prefix(15))
    }

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
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
            return [
                0, 100, 250, 500,
                1_000, 2_500, 5_000,
                10_000, 25_000, 50_000,
                100_000, 250_000, 500_000,
                1_000_000, 2_500_000, 5_000_000,
                10_000_000, 25_000_000, 50_000_000,
                100_000_000, 250_000_000, 500_000_000,
                1_000_000_000
            ]
        case .duration:
            switch unit {
            case .minutes:
                return [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
            case .seconds:
                return [0, 15, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1_200, 1_800, 3_600, 7_200]
            }
        }
    }

    private static func abbreviated(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }
}
