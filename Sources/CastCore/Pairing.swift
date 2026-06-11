import Foundation

public struct PairingChallenge: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let nonce: Data
    public let expiresAt: Date

    public init(hostID: UUID, nonce: Data, expiresAt: Date) {
        self.hostID = hostID
        self.nonce = nonce
        self.expiresAt = expiresAt
    }
}

public struct PairingResponse: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let deviceName: String
    public let publicKey: Data
    public let signedNonce: Data

    public init(
        deviceID: UUID,
        deviceName: String,
        publicKey: Data,
        signedNonce: Data
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.signedNonce = signedNonce
    }
}
