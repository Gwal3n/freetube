import SwiftUI

@available(iOS 17.0, *)
struct ConditionalSearchable: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let enabled: Bool
    var prompt: String = "Search"

    func body(content: Content) -> some View {
        if enabled {
            // Keep the field always visible; inactive searchable otherwise collapses on scroll.
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(prompt)
            )
        } else {
            content
        }
    }
}
