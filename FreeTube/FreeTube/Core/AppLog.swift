import Foundation
import OSLog

public enum AppLogPrivacy: Sendable {
    case `public`
    case `private`
}

/// A rendered message suitable for both the unified log and the optional diagnostic file.
public struct AppLogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    fileprivate let text: String

    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.output }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        fileprivate var output: String

        public init(literalCapacity: Int, interpolationCount: Int) {
            output = ""
            output.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) { output.append(literal) }
        public mutating func appendInterpolation<T>(_ value: T) {
            output.append(String(describing: value))
        }
        public mutating func appendInterpolation<T>(_ value: T, privacy: AppLogPrivacy) {
            switch privacy {
            case .public: output.append(String(describing: value))
            case .private: output.append("<private>")
            }
        }
    }
}

/// `os.Logger` facade that directly mirrors rendered messages to `LogFileWriter`. This avoids
/// `OSLogStore.composedMessage`, which can produce `<compose failure […]>` on iOS.
public struct AppLog: Sendable {
    private let logger: Logger
    private let category: String

    public init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    public func debug(_ message: AppLogMessage) {
        logger.debug("\(message.text, privacy: .public)")
        mirror(message, level: "DEBUG")
    }
    public func info(_ message: AppLogMessage) {
        logger.info("\(message.text, privacy: .public)")
        mirror(message, level: "INFO")
    }
    public func notice(_ message: AppLogMessage) {
        logger.notice("\(message.text, privacy: .public)")
        mirror(message, level: "NOTICE")
    }
    public func error(_ message: AppLogMessage) {
        logger.error("\(message.text, privacy: .public)")
        mirror(message, level: "ERROR")
    }
    public func fault(_ message: AppLogMessage) {
        logger.fault("\(message.text, privacy: .public)")
        mirror(message, level: "FAULT")
    }

    private func mirror(_ message: AppLogMessage, level: String) {
        LogFileWriter.record(category: category, level: level, message: message.text)
    }
}
