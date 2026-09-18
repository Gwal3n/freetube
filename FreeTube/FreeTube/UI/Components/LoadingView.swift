import SwiftUI

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
}
