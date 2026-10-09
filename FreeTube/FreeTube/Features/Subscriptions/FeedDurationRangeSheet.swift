import SwiftUI

/// Native form for a minute-based Feed duration range. An empty maximum is open-ended.
@available(iOS 17.0, *)
struct FeedDurationRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minimumText: String
    @State private var maximumText: String

    let onApply: (Int, Int) -> Void

    init(minimumMinutes: Int, maximumMinutes: Int, onApply: @escaping (Int, Int) -> Void) {
        _minimumText = State(initialValue: String(max(0, minimumMinutes)))
        _maximumText = State(initialValue: maximumMinutes > 0 ? String(maximumMinutes) : "")
        self.onApply = onApply
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
        if text.isEmpty { return true }
        guard let maximum, maximum > 0 else { return false }
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
                            .frame(maxWidth: 90)
                            .accessibilityLabel("Minimum minutes")
                    }
                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("No limit", text: $maximumText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .accessibilityLabel("Maximum minutes")
                    }
                } header: {
                    Text("Minutes")
                } footer: {
                    Text("Leave the maximum empty for videos of any length above the minimum.")
                }
            }
            .navigationTitle("Duration Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard canApply, let minimum else { return }
                        onApply(minimum, maximum ?? 0)
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
