import Foundation

/// Parses timed TTML paragraphs while preserving italic and foreground-color spans.
final class CaptionTTMLParser: NSObject, @preconcurrency XMLParserDelegate {
    private struct Style {
        var italic: Bool? = nil
        var colorRGB: UInt32? = nil

        func applying(_ override: Style) -> Style {
            Style(
                italic: override.italic ?? italic,
                colorRGB: override.colorRGB ?? colorRGB
            )
        }
    }

    private struct StyleDefinition {
        let references: [String]
        let values: Style
    }

    private var cues: [VideoCaptionCue] = []
    private var startTime: TimeInterval?
    private var endTime: TimeInterval?
    private var duration: TimeInterval?
    private var captionRuns: [VideoCaptionRun] = []
    private var styleDefinitions: [String: StyleDefinition] = [:]
    private var styleStack: [Style] = []

    static func parse(_ data: Data) -> [VideoCaptionCue] {
        let delegate = CaptionTTMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.cues.sorted { $0.startTime < $1.startTime }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch localName(elementName) {
        case "style":
            if let id = attributeDict["xml:id"] ?? attributeDict["id"] {
                styleDefinitions[id] = StyleDefinition(
                    references: references(in: attributeDict),
                    values: directStyle(in: attributeDict)
                )
            }
        case "body", "div", "span", "font":
            styleStack.append(resolvedStyle(in: attributeDict))
        case "i":
            var style = resolvedStyle(in: attributeDict)
            style.italic = true
            styleStack.append(style)
        case "p":
            styleStack.append(resolvedStyle(in: attributeDict))
            // TTML uses begin/end/dur; YouTube's timedtext variant uses t/d in ms.
            startTime = attributeDict["begin"].flatMap(Self.seconds)
                ?? attributeDict["t"].flatMap(Self.milliseconds)
            endTime = attributeDict["end"].flatMap(Self.seconds)
            duration = attributeDict["dur"].flatMap(Self.seconds)
                ?? attributeDict["d"].flatMap(Self.milliseconds)
            captionRuns = []
        case "br" where startTime != nil:
            appendText("\n")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        defer {
            if ["body", "div", "p", "span", "font", "i"].contains(name), !styleStack.isEmpty {
                styleStack.removeLast()
            }
        }
        guard name == "p" else { return }
        defer {
            startTime = nil
            endTime = nil
            duration = nil
            captionRuns = []
        }
        guard let startTime,
              let end = endTime ?? duration.map({ startTime + $0 }),
              end > startTime else { return }
        let runs = VideoCaptionRun.trimmed(captionRuns)
        let text = runs.map(\.text).joined()
        guard !text.isEmpty else { return }
        cues.append(VideoCaptionCue(startTime: startTime, endTime: end, text: text, runs: runs))
    }

    private func appendText(_ text: String) {
        guard startTime != nil, !text.isEmpty else { return }
        let style = styleStack.last ?? Style()
        let italic = style.italic ?? false
        if let previous = captionRuns.last,
           previous.isItalic == italic, previous.colorRGB == style.colorRGB {
            captionRuns[captionRuns.count - 1] = VideoCaptionRun(
                text: previous.text + text,
                isItalic: italic,
                colorRGB: style.colorRGB
            )
        } else {
            captionRuns.append(VideoCaptionRun(
                text: text, isItalic: italic, colorRGB: style.colorRGB
            ))
        }
    }

    private func resolvedStyle(in attributes: [String: String]) -> Style {
        var result = styleStack.last ?? Style()
        for reference in references(in: attributes) {
            result = result.applying(definition(reference, visited: []))
        }
        return result.applying(directStyle(in: attributes))
    }

    private func definition(_ id: String, visited: Set<String>) -> Style {
        guard !visited.contains(id), let definition = styleDefinitions[id] else { return Style() }
        var result = Style()
        let nextVisited = visited.union([id])
        for reference in definition.references {
            result = result.applying(self.definition(reference, visited: nextVisited))
        }
        return result.applying(definition.values)
    }

    private func references(in attributes: [String: String]) -> [String] {
        attributes["style"]?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
    }

    private func directStyle(in attributes: [String: String]) -> Style {
        let fontStyle = attributes.first { localName($0.key) == "fontStyle" }?.value.lowercased()
        let color = attributes.first { localName($0.key) == "color" }?.value
        let italic: Bool?
        switch fontStyle {
        case "italic", "oblique": italic = true
        case "normal": italic = false
        default: italic = nil
        }
        return Style(italic: italic, colorRGB: CaptionSourceColor.rgb(from: color))
    }

    private func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name))
    }

    private static func seconds(_ raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("ms"), let value = Double(text.dropLast(2)) { return value / 1_000 }
        if text.hasSuffix("s"), let value = Double(text.dropLast()) { return value }
        let parts = text.split(separator: ":")
        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let seconds = Double(parts[2]) {
            return hours * 3_600 + minutes * 60 + seconds
        }
        if parts.count == 2,
           let minutes = Double(parts[0]),
           let seconds = Double(parts[1]) {
            return minutes * 60 + seconds
        }
        return Double(text)
    }

    private static func milliseconds(_ raw: String) -> TimeInterval? {
        Double(raw).map { $0 / 1_000 }
    }
}
