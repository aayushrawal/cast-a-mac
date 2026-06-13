import Foundation

public struct RelayHostConfiguration: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let hostID: UUID
    public let hostName: String
    public let hostSecret: String
    public let linkCode: String

    public init(
        baseURL: URL,
        hostID: UUID,
        hostName: String,
        hostSecret: String,
        linkCode: String
    ) {
        self.baseURL = baseURL
        self.hostID = hostID
        self.hostName = hostName
        self.hostSecret = hostSecret
        self.linkCode = linkCode
    }
}

public struct RelayClientCredential: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let host: RemoteMacRecord
    public let accessToken: String

    public init(
        baseURL: URL,
        host: RemoteMacRecord,
        accessToken: String
    ) {
        self.baseURL = baseURL
        self.host = host
        self.accessToken = accessToken
    }
}

public struct RelayLinkRequest: Codable, Equatable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct RelayLinkResponse: Codable, Equatable, Sendable {
    public let host: RemoteMacRecord
    public let accessToken: String

    public init(host: RemoteMacRecord, accessToken: String) {
        self.host = host
        self.accessToken = accessToken
    }
}
