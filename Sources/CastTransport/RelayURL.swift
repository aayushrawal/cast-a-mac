import Foundation

enum RelayURL {
    static func websocket(
        baseURL: URL,
        path: String
    ) throws -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            throw URLError(.unsupportedURL)
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    static func http(baseURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        switch components.scheme?.lowercased() {
        case "wss":
            components.scheme = "https"
        case "ws":
            components.scheme = "http"
        case "https", "http":
            break
        default:
            throw URLError(.unsupportedURL)
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}
