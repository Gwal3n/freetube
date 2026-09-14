import SwiftUI

/// CLAUDE.md §12: "Show errors via a single `ErrorToast` view modifier reading `errorState`."
struct ErrorToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var errorState: ErrorState?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let errorState {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: errorState.isFatal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        Text(errorState.message)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Button {
                            self.errorState = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: errorState.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if self.errorState?.id == errorState.id { self.errorState = nil }
                    }
                }
            }
            .animation(reduceMotion ? nil : InterfaceMotion.notice, value: errorState?.id)
    }
}

extension View {
    func errorToast(_ state: Binding<ErrorState?>) -> some View {
        modifier(ErrorToastModifier(errorState: state))
    }
}
