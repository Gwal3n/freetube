import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct LibraryAccountSection: View {
    let info: AccountInfo?
    let isSigningOut: Bool
    let onSignIn: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        Section {
            if let info {
                HStack(spacing: MediaStyle.spacing) {
                    KFImage(info.avatarURL)
                        .thumbnail(size: CGSize(width: 56, height: 56)) {
                            Circle().fill(.secondary.opacity(0.12))
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.displayName)
                            .font(.headline)
                        if let handle = info.handle, !handle.isEmpty {
                            Text(handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onSignOut) {
                        if isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 44, minHeight: 30)
                        } else {
                            Text("Sign out")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSigningOut)
                }
            } else {
                Button(action: onSignIn) {
                    Label("Sign in to YouTube", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } footer: {
            if info == nil {
                Text("Sign in to access your watch history, playlists, liked videos, and Watch Later.")
            }
        }
    }
}
