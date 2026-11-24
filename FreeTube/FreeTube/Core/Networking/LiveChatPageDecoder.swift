import Foundation

/// Decodes `get_live_chat` JSON into app-owned messages. Unknown renderer types are skipped.
nonisolated enum LiveChatPageDecoder {
    static func decode(_ root: Any) -> LiveChatPage {
        let continuationRoot = value(root, "continuationContents", "liveChatContinuation")
            ?? value(root, "contents", "liveChatRenderer")
        let actions = array(continuationRoot, "actions")
        var decoded: [LiveChatMessage] = []
        var seen = Set<String>()
        for action in actions {
            for message in messages(fromAction: action) where seen.insert(message.id).inserted {
                decoded.append(message)
            }
        }
        let continuations = array(continuationRoot, "continuations")
        let next = nextContinuation(from: continuations)
        let chatEnded = continuations.contains {
            value($0, "playerSeekContinuationData") != nil
                || value($0, "liveChatReplayContinuationData") != nil
        } && next.token == nil
        return LiveChatPage(
            messages: decoded,
            continuation: next.token,
            timeout: next.timeout,
            chatEnded: chatEnded && decoded.isEmpty
        )
    }

    // MARK: - Actions

    private static func messages(fromAction action: Any) -> [LiveChatMessage] {
        if let item = value(action, "addChatItemAction", "item") {
            if let message = message(from: item) { return [message] }
        }
        if let item = value(action, "addLiveChatTickerItemAction", "item") {
            if let message = message(from: item) { return [message] }
        }
        // Replay / batch wrappers.
        let replay = array(action, "replayChatItemAction", "actions")
        return replay.flatMap(messages(fromAction:))
    }

    private static func message(from item: Any) -> LiveChatMessage? {
        if let renderer = value(item, "liveChatTextMessageRenderer") {
            return textMessage(renderer, kind: .text, amount: nil)
        }
        if let renderer = value(item, "liveChatPaidMessageRenderer") {
            let amount = simpleText(value(renderer, "purchaseAmountText"))
            return textMessage(renderer, kind: .superChat, amount: amount)
        }
        if let renderer = value(item, "liveChatPaidStickerRenderer") {
            let amount = simpleText(value(renderer, "purchaseAmountText"))
            let author = simpleText(value(renderer, "authorName")) ?? "Viewer"
            let id = (renderer as? [String: Any])?["id"] as? String
                ?? "sticker-\(author)-\(amount ?? "")"
            return LiveChatMessage(
                id: id,
                authorName: author,
                text: "Sticker",
                kind: .sticker,
                amountText: amount,
                publishedAt: timestamp(from: renderer)
            )
        }
        if let renderer = value(item, "liveChatMembershipItemRenderer") {
            let author = simpleText(value(renderer, "authorName")) ?? "Member"
            let header = runsText(value(renderer, "headerSubtext"))
                ?? runsText(value(renderer, "headerPrimaryText"))
                ?? "New member"
            let id = (renderer as? [String: Any])?["id"] as? String ?? "member-\(author)-\(header)"
            return LiveChatMessage(
                id: id,
                authorName: author,
                text: header,
                kind: .membership,
                amountText: nil,
                publishedAt: timestamp(from: renderer)
            )
        }
        if let renderer = value(item, "liveChatViewerEngagementMessageRenderer") {
            let text = runsText(value(renderer, "message")) ?? ""
            guard !text.isEmpty else { return nil }
            let id = (renderer as? [String: Any])?["id"] as? String ?? "system-\(text)"
            return LiveChatMessage(
                id: id,
                authorName: "",
                text: text,
                kind: .system,
                amountText: nil,
                publishedAt: nil
            )
        }
        return nil
    }

    private static func textMessage(
        _ renderer: Any,
        kind: LiveChatMessage.Kind,
        amount: String?
    ) -> LiveChatMessage? {
        let author = simpleText(value(renderer, "authorName")) ?? "Viewer"
        let text = runsText(value(renderer, "message")) ?? ""
        guard !text.isEmpty || amount != nil else { return nil }
        let id = (renderer as? [String: Any])?["id"] as? String
            ?? "\(author)-\(text)-\(amount ?? "")"
        return LiveChatMessage(
            id: id,
            authorName: author,
            text: text.isEmpty ? (amount ?? "") : text,
            kind: kind,
            amountText: amount,
            publishedAt: timestamp(from: renderer)
        )
    }

    // MARK: - Continuation

    private static func nextContinuation(from items: [Any]) -> (token: String?, timeout: Duration) {
        for item in items {
            for key in ["timedContinuationData", "invalidationContinuationData", "reloadContinuationData"] {
                guard let data = value(item, key) as? [String: Any],
                      let token = data["continuation"] as? String,
                      !token.isEmpty else { continue }
                let ms = (data["timeoutMs"] as? Int)
                    ?? (data["timeoutMs"] as? Double).map(Int.init)
                    ?? 1_000
                let clamped = min(15_000, max(500, ms))
                return (token, .milliseconds(clamped))
            }
        }
        return (nil, .seconds(5))
    }

    // MARK: - JSON helpers

    private static func timestamp(from renderer: Any) -> Date? {
        guard let usec = (renderer as? [String: Any])?["timestampUsec"] as? String,
              let value = Double(usec) else { return nil }
        return Date(timeIntervalSince1970: value / 1_000_000)
    }

    private static func simpleText(_ node: Any?) -> String? {
        guard let node else { return nil }
        if let text = (node as? [String: Any])?["simpleText"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return runsText(node)
    }

    private static func runsText(_ node: Any?) -> String? {
        let runs = array(node, "runs")
        let text = runs.compactMap { run -> String? in
            if let text = (run as? [String: Any])?["text"] as? String { return text }
            // Custom emoji: fall back to the shortcut label when present.
            if let emoji = value(run, "emoji") as? [String: Any] {
                if let shortcuts = emoji["shortcuts"] as? [String], let first = shortcuts.first {
                    return first
                }
                return emoji["emojiId"] as? String
            }
            return nil
        }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func value(_ root: Any?, _ path: String...) -> Any? {
        var current: Any? = root
        for key in path {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        return current
    }

    private static func array(_ root: Any?, _ path: String...) -> [Any] {
        var current: Any? = root
        for key in path {
            guard let dict = current as? [String: Any] else { return [] }
            current = dict[key]
        }
        return current as? [Any] ?? []
    }
}
