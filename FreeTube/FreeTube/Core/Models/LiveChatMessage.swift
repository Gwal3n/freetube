import Foundation

/// One read-only live chat row. Continuations and payloads stay in memory only.
nonisolated struct LiveChatMessage: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case text
        case superChat
        case membership
        case sticker
        case system
    }

    let id: String
    let authorName: String
    /// YouTube channel id when the renderer supplies `authorExternalChannelId`.
    let authorChannelID: String?
    let text: String
    let kind: Kind
    /// Super Chat / sticker amount label when YouTube supplies one (e.g. "$5.00").
    let amountText: String?
    let publishedAt: Date?
}

/// One anonymous poll page. `timeout` is YouTube's suggested wait before the next poll.
nonisolated struct LiveChatPage: Sendable {
    let messages: [LiveChatMessage]
    let continuation: String?
    let timeout: Duration
    let chatEnded: Bool
}
