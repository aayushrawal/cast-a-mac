import Foundation

public struct RemoteMacRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var isOnline: Bool
    public var lastSeenAt: Date

    public init(id: UUID, name: String, isOnline: Bool, lastSeenAt: Date) {
        self.id = id
        self.name = name
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
    }
}

public struct InternetSessionTicket: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let hostID: UUID
    public let expiresAt: Date
    public let signalingURL: URL
    public let accessToken: String
    public let iceServers: [ICEServer]

    public init(
        sessionID: UUID,
        hostID: UUID,
        expiresAt: Date,
        signalingURL: URL,
        accessToken: String,
        iceServers: [ICEServer]
    ) {
        self.sessionID = sessionID
        self.hostID = hostID
        self.expiresAt = expiresAt
        self.signalingURL = signalingURL
        self.accessToken = accessToken
        self.iceServers = iceServers
    }
}

public struct ICEServer: Codable, Equatable, Sendable {
    public let urls: [URL]
    public let username: String?
    public let credential: String?

    public init(urls: [URL], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

public protocol InternetSessionProvider: Sendable {
    func availableMacs() async throws -> [RemoteMacRecord]
    func createSessionTicket(for hostID: UUID) async throws -> InternetSessionTicket
}
