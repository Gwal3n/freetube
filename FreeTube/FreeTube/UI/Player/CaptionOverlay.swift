import SwiftUI

/// Readable external-caption rendering that stays above the custom timeline chrome.
@available(iOS 17.0, *)
struct CaptionOverlay: View {
    let text: String
    let bottomPadding: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 34)
            .padding(.bottom, bottomPadding)
            .allowsHitTesting(false)
    }
}
