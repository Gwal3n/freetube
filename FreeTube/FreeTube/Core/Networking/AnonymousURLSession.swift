import Foundation

/// Shared factory for cookie-free ephemeral `URLSession`s used by anonymous networking.
enum AnonymousURLSession {
    static func make(
        configure: ((URLSessionConfiguration) -> Void)? = nil
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configure?(configuration)
        return URLSession(configuration: configuration)
    }
}
