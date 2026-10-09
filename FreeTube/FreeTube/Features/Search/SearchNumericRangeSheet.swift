import SwiftUI

/// Native numeric interval editor shared by the local duration and view-count filters.
@available(iOS 17.0, *)
struct SearchNumericRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minimumText: String
    @State private var maximumText: String

    let title: String
    let unit: String
    let onApply: (SearchVideoFilters.NumericRange) -> Void

    init(
        title: String,
        unit: String,
        range: SearchVideoFilters.NumericRange?,
        onApply: @escaping (SearchVideoFilters.NumericRange) -> Void
    ) {
        self.title = title
        self.unit = unit
        self.onApply = onApply
        _minimumText = State(initialValue: String(range?.minimum ?? 0))
        _maximumText = State(initialValue: range?.maximum.map { String($0) } ?? "")
    }

    private var minimum: Int? {
        Int(minimumText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var maximum: Int? {
        let text = maximumText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Int(text)
    }

    private var canApply: Bool {
        guard let minimum, minimum >= 0 else { return false }
        let text = maximumText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || (maximum.map { $0 >= minimum } ?? false)
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
                            .accessibilityLabel("Minimum \(unit)")
                    }
                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("No limit", text: $maximumText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityLabel("Maximum \(unit)")
                    }
                } header: {
                    Text(unit)
                } footer: {
                    Text("Leave the maximum empty for no upper limit.")
                }
            }
            .navigationTitle(title)
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
        }
        .presentationDetents([.medium])
    }
}
