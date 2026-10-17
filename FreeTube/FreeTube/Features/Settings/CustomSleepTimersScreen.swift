import SwiftUI

@available(iOS 17.0, *)
struct CustomSleepTimersScreen: View {
    @AppStorage("sleepTimerMinuteChoices") private var savedMinutesRaw = ""
    @State private var isAddingDuration = false
    @State private var minutesText = ""

    private var savedMinutes: [Int] {
        SleepTimerPresets.decode(savedMinutesRaw)
    }

    var body: some View {
        List {
            Section {
                ForEach(savedMinutes, id: \.self) { minutes in
                    Text(verbatim: SleepTimerPresets.label(minutes))
                        .deleteDisabled(savedMinutes.count == 1)
                }
                .onDelete(perform: deleteDurations)
            } footer: {
                Text("Swipe left to remove a duration. At least one remains available. You can also enter a custom duration in the player.")
            }
        }
        .navigationTitle("Sleep timer durations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    minutesText = ""
                    isAddingDuration = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add sleep timer duration")
            }
        }
        .alert("Add duration", isPresented: $isAddingDuration) {
            TextField("Minutes", text: $minutesText)
                .keyboardType(.numberPad)
            Button("Save") { addDuration() }
                .disabled(SleepTimerPresets.parse(minutesText) == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a duration from 1 to 720 minutes.")
        }
    }

    private func addDuration() {
        guard let minutes = SleepTimerPresets.parse(minutesText) else { return }
        savedMinutesRaw = SleepTimerPresets.encode(savedMinutes + [minutes])
    }

    private func deleteDurations(at offsets: IndexSet) {
        var remaining = savedMinutes
        remaining.remove(atOffsets: offsets)
        guard !remaining.isEmpty else { return }
        savedMinutesRaw = SleepTimerPresets.encode(remaining)
    }
}
