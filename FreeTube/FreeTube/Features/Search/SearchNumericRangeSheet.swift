import SwiftUI

/// Native numeric interval editor shared by the local duration and view-count filters.
/// Both the minimum and maximum sliders end at Unlimited; typed values stay authoritative
/// for concrete amounts.
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

    /// Normalized track: `0...finiteEnd` maps to concrete values; `unlimitedPosition` is Unlimited.
    private static let finiteEnd = 0.92
    private static let unlimitedPosition = 1.0

    @Environment(\.dismiss) private var dismiss
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var minimumSlider: Double
    @State private var maximumSlider: Double
    @State private var minimumIsUnlimited: Bool
    @State private var maximumIsUnlimited: Bool

    let kind: Kind
    let onApply: (SearchVideoFilters.NumericRange) -> Void

    init(
        kind: Kind,
        range: SearchVideoFilters.NumericRange?,
        onApply: @escaping (SearchVideoFilters.NumericRange) -> Void
    ) {
        self.kind = kind
        self.onApply = onApply
        // No floor is stored as minimum 0; treat that as Unlimited so both ends share the same stop.
        let minimumUnlimited = range == nil || range?.minimum == 0
        let maximumUnlimited = range?.maximum == nil
        let minimumValue = range?.minimum ?? 0
        _minimumIsUnlimited = State(initialValue: minimumUnlimited)
        _maximumIsUnlimited = State(initialValue: maximumUnlimited)
        _minimumText = State(initialValue: minimumUnlimited ? "" : String(minimumValue))
        _maximumText = State(
            initialValue: maximumUnlimited ? "" : String(range?.maximum ?? 0)
        )
        _minimumSlider = State(
            initialValue: minimumUnlimited
                ? Self.unlimitedPosition
                : Self.sliderPosition(for: minimumValue, kind: kind)
        )
        _maximumSlider = State(
            initialValue: maximumUnlimited
                ? Self.unlimitedPosition
                : Self.sliderPosition(for: range?.maximum ?? 0, kind: kind)
        )
    }

    private var resolvedMinimum: Int? {
        if minimumIsUnlimited { return 0 }
        return Int(minimumText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var resolvedMaximum: Int? {
        if maximumIsUnlimited { return nil }
        return Int(maximumText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canApply: Bool {
        guard let minimum = resolvedMinimum, minimum >= 0 else { return false }
        guard let maximum = resolvedMaximum else { return true }
        return maximum >= minimum
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    boundEditor(
                        title: "Minimum",
                        text: $minimumText,
                        slider: $minimumSlider,
                        isUnlimited: $minimumIsUnlimited,
                        accessibilityNoun: "Minimum"
                    )
                    boundEditor(
                        title: "Maximum",
                        text: $maximumText,
                        slider: $maximumSlider,
                        isUnlimited: $maximumIsUnlimited,
                        accessibilityNoun: "Maximum"
                    )
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
                        guard canApply, let minimum = resolvedMinimum else { return }
                        onApply(.init(minimum: minimum, maximum: resolvedMaximum))
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var footerText: String {
        switch kind {
        case .minutes:
            return "Slide all the way right for Unlimited on either bound, or type an exact minute count."
        case .views:
            return "Slide all the way right for Unlimited on either bound. The track is logarithmic up to 10M; type a larger number when needed."
        }
    }

    private func boundEditor(
        title: String,
        text: Binding<String>,
        slider: Binding<Double>,
        isUnlimited: Binding<Bool>,
        accessibilityNoun: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                Spacer()
                TextField("Unlimited", text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("\(accessibilityNoun) \(kind.unitLabel)")
                    .onChange(of: text.wrappedValue) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            isUnlimited.wrappedValue = true
                            slider.wrappedValue = Self.unlimitedPosition
                            return
                        }
                        guard let parsed = Int(trimmed), parsed >= 0 else { return }
                        isUnlimited.wrappedValue = false
                        slider.wrappedValue = Self.sliderPosition(for: parsed, kind: kind)
                    }
            }
            Slider(
                value: Binding(
                    get: { slider.wrappedValue },
                    set: { newValue in
                        slider.wrappedValue = newValue
                        applySlider(newValue, text: text, isUnlimited: isUnlimited)
                    }
                ),
                in: 0...Self.unlimitedPosition
            )
            .accessibilityLabel("\(accessibilityNoun) \(kind.unitLabel) slider")
            .accessibilityValue(
                isUnlimited.wrappedValue
                    ? "Unlimited"
                    : (text.wrappedValue.isEmpty ? "Unlimited" : text.wrappedValue)
            )
        }
    }

    private func applySlider(
        _ position: Double,
        text: Binding<String>,
        isUnlimited: Binding<Bool>
    ) {
        if position >= Self.finiteEnd {
            isUnlimited.wrappedValue = true
            text.wrappedValue = ""
            return
        }
        isUnlimited.wrappedValue = false
        text.wrappedValue = String(Self.finiteValue(at: position, kind: kind))
    }

    /// Position on `0...finiteEnd` for a concrete value. Values above the finite band sit at the
    /// band’s end so Unlimited remains a distinct final gesture.
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
