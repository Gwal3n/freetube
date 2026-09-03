import SwiftUI

/// Equatable boundary keeps playback-time ticks from rebuilding an open native speed menu.
@available(iOS 17.0, *)
struct SpeedPlayerMenu: View, Equatable {
    let selectedRate: Double
    let onSelect: (Double) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        abs(lhs.selectedRate - rhs.selectedRate) < 0.001
    }

    var body: some View {
        Menu {
            ForEach([0.5, 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button {
                    onSelect(rate)
                } label: {
                    if abs(selectedRate - rate) < 0.01 {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            Text(rateLabel(selectedRate))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 42, minHeight: 36)
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
