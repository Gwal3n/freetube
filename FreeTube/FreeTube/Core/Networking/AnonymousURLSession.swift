import Foundation

/// Shared factory for cookie-free ephemeral `URLSession`s used by anonymous networking.
enum AnonymousURLSession {
    static func configuration(
        configure: ((URLSessionConfiguration) -> Void)? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configure?(configuration)
        return configuration
    }

    static func make(
        configure: ((URLSessionConfiguration) -> Void)? = nil
    ) -> URLSession {
        URLSession(configuration: configuration(configure: configure))
    }
}
