import CastCore
import Foundation

public struct RelayCoordinationClient: Sendable {
    public init() {}

    public func link(
        baseURL: URL,
        code: String
    ) async throws -> RelayClientCredential {
        let url = try RelayURL.http(baseURL: baseURL, path: "/v1/link")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RelayLinkRequest(code: code.uppercased())
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RelayCoordinationError.linkFailed
        }
        let linked = try JSONDecoder().decode(
            RelayLinkResponse.self,
            from: data
        )
        return RelayClientCredential(
            baseURL: baseURL,
            host: linked.host,
            accessToken: linked.accessToken
        )
    }
}

public enum RelayCoordinationError: LocalizedError {
    case linkFailed

    public var errorDescription: String? {
        "The link code is invalid, expired, or the Mac is offline."
    }
}
