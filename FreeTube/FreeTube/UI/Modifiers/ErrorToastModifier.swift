import SwiftUI

/// CLAUDE.md §12: "Show errors via a single `ErrorToast` view modifier reading `errorState`."
struct ErrorToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Binding var errorState: ErrorState?
    let bottomClearance: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let errorState {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: errorState.isFatal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(errorState.message)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            self.errorState = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote)
                                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(12)
                    .frame(maxWidth: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomClearance + 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: errorState.id) {
                        // A VoiceOver user must have time to find and read the banner. Fatal
                        // errors also remain until the explicit dismiss button is used.
                        guard !errorState.isFatal, !voiceOverEnabled else { return }
                        do { try await Task.sleep(for: .seconds(6)) }
                        catch { return }
                        if self.errorState?.id == errorState.id { self.errorState = nil }
                    }
                }
            }
            .animation(reduceMotion ? nil : InterfaceMotion.notice, value: errorState?.id)
    }
}

extension View {
    func errorToast(_ state: Binding<ErrorState?>, bottomClearance: CGFloat = 0) -> some View {
        modifier(ErrorToastModifier(errorState: state, bottomClearance: bottomClearance))
    }
}
