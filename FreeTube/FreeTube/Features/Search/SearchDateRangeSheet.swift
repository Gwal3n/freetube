import SwiftUI

/// Native date picker for a local, approximate upload-date filter.
@available(iOS 17.0, *)
struct SearchDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstDay: Date
    @State private var lastDay: Date

    let onApply: (SearchVideoFilters.DateRange) -> Void

    init(range: SearchVideoFilters.DateRange?, onApply: @escaping (SearchVideoFilters.DateRange) -> Void) {
        _firstDay = State(initialValue: range?.firstDay
            ?? Calendar.autoupdatingCurrent.date(byAdding: .month, value: -1, to: .now) ?? .now)
        _lastDay = State(initialValue: range?.lastDay ?? .now)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $firstDay, displayedComponents: .date)
                    DatePicker("Through", selection: $lastDay, displayedComponents: .date)
                } footer: {
                    Text("Upload dates are approximate when YouTube only provides a relative age.")
                }
            }
            .navigationTitle("Upload Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(.init(firstDay: firstDay, lastDay: lastDay))
                        dismiss()
                    }
                    .disabled(firstDay > lastDay)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
