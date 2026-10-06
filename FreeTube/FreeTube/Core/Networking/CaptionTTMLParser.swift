import Foundation

/// Parses the TTML format NewPipe requests from YouTube timedtext URLs. Only timed `<p>`
/// elements become cues; nested spans are flattened to readable text.
final class CaptionTTMLParser: NSObject, @preconcurrency XMLParserDelegate {
    private var cues: [VideoCaptionCue] = []
    private var startTime: TimeInterval?
    private var endTime: TimeInterval?
    private var duration: TimeInterval?
    private var captionText = ""

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
        switch elementName {
        case "p":
            // TTML uses begin/end/dur; YouTube's timedtext variant uses t/d in ms.
            startTime = attributeDict["begin"].flatMap(Self.seconds)
                ?? attributeDict["t"].flatMap(Self.milliseconds)
            endTime = attributeDict["end"].flatMap(Self.seconds)
            duration = attributeDict["dur"].flatMap(Self.seconds)
                ?? attributeDict["d"].flatMap(Self.milliseconds)
            captionText = ""
        case "br" where startTime != nil:
            captionText += "\n"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if startTime != nil { captionText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if startTime != nil { captionText += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "p" else { return }
        defer {
            startTime = nil
            endTime = nil
            duration = nil
            captionText = ""
        }
        guard let startTime,
              let end = endTime ?? duration.map({ startTime + $0 }),
              end > startTime else { return }
        let text = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cues.append(VideoCaptionCue(startTime: startTime, endTime: end, text: text))
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
