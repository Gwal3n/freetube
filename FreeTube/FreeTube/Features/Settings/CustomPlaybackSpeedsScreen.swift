import SwiftUI

@available(iOS 17.0, *)
struct CustomPlaybackSpeedsScreen: View {
    @AppStorage("customPlaybackSpeeds") private var savedRatesRaw = ""
    @State private var isAddingSpeed = false
    @State private var speedText = ""

    private var savedRates: [Double] {
        PlaybackSpeedPresets.decode(savedRatesRaw)
    }

    var body: some View {
        List {
            Section {
                if savedRates.isEmpty {
                    Text("No custom speeds")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedRates, id: \.self) { rate in
                        Text(verbatim: PlaybackSpeedPresets.label(rate))
                    }
                    .onDelete(perform: deleteSpeeds)
                }
            } footer: {
                Text("Saved speeds appear in the player’s speed menu and in the default speed picker.")
            }
        }
        .navigationTitle("Custom speeds")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    speedText = ""
                    isAddingSpeed = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add custom speed")
            }
        }
        .alert("Custom speed", isPresented: $isAddingSpeed) {
            TextField("Speed", text: $speedText)
                .keyboardType(.decimalPad)
            Button("Save") { addSpeed() }
                .disabled(PlaybackSpeedPresets.parse(speedText) == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter 0.25× to 5×, with up to two decimal places.")
        }
    }

    private func addSpeed() {
        guard let rate = PlaybackSpeedPresets.parse(speedText) else { return }
        savedRatesRaw = PlaybackSpeedPresets.encode(savedRates + [rate])
    }

    private func deleteSpeeds(at offsets: IndexSet) {
        var rates = savedRates
        rates.remove(atOffsets: offsets)
        savedRatesRaw = PlaybackSpeedPresets.encode(rates)
    }
}
