import SwiftUI

@available(iOS 17.0, *)
struct CustomPlaybackSpeedsScreen: View {
    @Binding var defaultPlaybackRate: Double
    @AppStorage("playbackSpeedChoices") private var savedRatesRaw = ""
    @AppStorage("customPlaybackSpeeds") private var legacyCustomRatesRaw = ""
    @State private var isAddingSpeed = false
    @State private var speedText = ""

    private var savedRates: [Double] {
        PlaybackSpeedPresets.availableRates(
            savedRaw: savedRatesRaw,
            legacyCustomRaw: legacyCustomRatesRaw
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(savedRates, id: \.self) { rate in
                    Text(verbatim: PlaybackSpeedPresets.label(rate))
                        .deleteDisabled(rate == 1)
                }
                .onDelete(perform: deleteSpeeds)
            } footer: {
                Text("Speeds appear in the player and default speed picker. 1× cannot be removed.")
            }
        }
        .navigationTitle("Playback speeds")
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
        let remaining = Array(Set(rates + [1])).sorted()
        savedRatesRaw = PlaybackSpeedPresets.encode(remaining)
        if !remaining.contains(defaultPlaybackRate) {
            defaultPlaybackRate = 1
        }
    }
}
