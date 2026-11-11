import SwiftUI

/// Native numeric interval editor shared by the local duration and view-count filters.
/// One dual-thumb slider sets both bounds; the text fields stay available for exact values.
/// The trailing end of the track is Unlimited (open maximum).
@available(iOS 17.0, *)
struct SearchNumericRangeSheet: View {
    enum Kind: Equatable {
        /// Minutes: linear finite track, then Unlimited.
        case minutes
        /// Views: logarithmic finite track, then Unlimited.
        case views

        var unitLabel: String {
            switch self {
            case .minutes: "Minutes"
            case .views: "Views"
            }
        }

        var title: String {
            switch self {
            case .minutes: "Duration Range"
            case .views: "View Count Range"
            }
        }

        /// Highest concrete value on the track before the Unlimited stop.
        fileprivate var finiteUpperBound: Double {
            switch self {
            case .minutes: 180
            case .views: 10_000_000
            }
        }
    }

    /// Normalized track: `0...finiteEnd` maps to concrete values; `1` is Unlimited for the max thumb.
    private static let finiteEnd = 0.92

    @Environment(\.dismiss) private var dismiss
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var lowerPosition: Double
    @State private var upperPosition: Double

    let kind: Kind
    let onApply: (SearchVideoFilters.NumericRange) -> Void

    init(
        kind: Kind,
        range: SearchVideoFilters.NumericRange?,
        onApply: @escaping (SearchVideoFilters.NumericRange) -> Void
    ) {
        self.kind = kind
        self.onApply = onApply
        let minimum = max(0, range?.minimum ?? 0)
        let maximum = range?.maximum
        _minimumText = State(initialValue: String(minimum))
        _maximumText = State(initialValue: maximum.map(String.init) ?? "")
        _lowerPosition = State(initialValue: Self.sliderPosition(for: minimum, kind: kind))
        _upperPosition = State(
            initialValue: maximum.map { Self.sliderPosition(for: $0, kind: kind) } ?? 1
        )
    }

    private var minimum: Int? {
        Int(minimumText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var maximum: Int? {
        let text = maximumText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Int(text)
    }

    private var maximumIsUnlimited: Bool {
        maximumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || upperPosition >= Self.finiteEnd
    }

    private var canApply: Bool {
        guard let minimum, minimum >= 0 else { return false }
        guard let maximum else { return true }
        return maximum >= minimum
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Minimum")
                        Spacer()
                        TextField("0", text: $minimumText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityLabel("Minimum \(kind.unitLabel)")
                    }
                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("Unlimited", text: $maximumText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityLabel("Maximum \(kind.unitLabel)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SearchNumericRangeSlider(
                            lower: lowerBinding,
                            upper: upperBinding,
                            lowerAccessibilityValue: minimum.map(String.init) ?? "0",
                            upperAccessibilityValue: maximumIsUnlimited
                                ? "Unlimited"
                                : (maximum.map(String.init) ?? "Unlimited")
                        )
                        HStack {
                            Text(verbatim: "0")
                            Spacer()
                            Text("Unlimited")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text(kind.unitLabel)
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
                        guard canApply, let minimum else { return }
                        onApply(.init(minimum: minimum, maximum: maximum))
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

    private var footerText: String {
        switch kind {
        case .minutes:
            return "Drag either end of the range. The right end is Unlimited; you can also type exact minutes."
        case .views:
            return "Drag either end of the range. The right end is Unlimited. The track is logarithmic up to 10M; type a larger number when needed."
        }
    }

    private var lowerBinding: Binding<Double> {
        Binding(
            get: { lowerPosition },
            set: { newValue in
                lowerPosition = min(newValue, upperPosition)
                applyLowerPosition()
            }
        )
    }

    private var upperBinding: Binding<Double> {
        Binding(
            get: { upperPosition },
            set: { newValue in
                upperPosition = max(newValue, lowerPosition)
                applyUpperPosition()
            }
        )
    }

    private func syncLowerFromText() {
        guard let minimum, minimum >= 0 else { return }
        let position = Self.sliderPosition(for: minimum, kind: kind)
        lowerPosition = min(position, upperPosition)
    }

    private func syncUpperFromText() {
        let text = maximumText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            upperPosition = 1
            return
        }
        guard let maximum, maximum >= 0 else { return }
        let position = Self.sliderPosition(for: maximum, kind: kind)
        upperPosition = max(position, lowerPosition)
    }

    private func applyLowerPosition() {
        // The lower thumb stays on the finite band; Unlimited is only a maximum stop.
        let capped = min(lowerPosition, Self.finiteEnd - 0.001)
        if capped != lowerPosition { lowerPosition = capped }
        minimumText = String(Self.finiteValue(at: lowerPosition, kind: kind))
    }

    private func applyUpperPosition() {
        if upperPosition >= Self.finiteEnd {
            maximumText = ""
            return
        }
        maximumText = String(Self.finiteValue(at: upperPosition, kind: kind))
    }

    /// Position on `0...finiteEnd` for a concrete value. Values above the finite band sit at the
    /// band’s end so Unlimited remains a distinct final gesture for the upper thumb.
    private static func sliderPosition(for value: Int, kind: Kind) -> Double {
        let clamped = max(0, Double(value))
        let upper = kind.finiteUpperBound
        guard upper > 0 else { return 0 }
        let normalized: Double
        switch kind {
        case .minutes:
            normalized = min(1, clamped / upper)
        case .views:
            guard clamped > 0 else { return 0 }
            normalized = min(1, log(min(clamped, upper)) / log(upper))
        }
        return normalized * finiteEnd
    }

    private static func finiteValue(at position: Double, kind: Kind) -> Int {
        let t = min(finiteEnd, max(0, position)) / finiteEnd
        let upper = kind.finiteUpperBound
        switch kind {
        case .minutes:
            return Int((t * upper).rounded())
        case .views:
            guard t > 0 else { return 0 }
            return Int(pow(upper, t).rounded())
        }
    }
}
