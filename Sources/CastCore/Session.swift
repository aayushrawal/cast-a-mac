import Foundation

public enum CastProtocol {
    public static let currentVersion = 1
}

public struct HostIdentity: Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DisplayDescriptor: Codable, Equatable, Sendable {
    public let id: UInt32
    public var name: String
    public var pixelSize: CastSize
    public var scaleFactor: Double

    public init(
        id: UInt32,
        name: String,
        pixelSize: CastSize,
        scaleFactor: Double
    ) {
        self.id = id
        self.name = name
        self.pixelSize = pixelSize
        self.scaleFactor = scaleFactor
    }
}

public struct SessionCapabilities: Codable, Equatable, Sendable {
    public var supportsHEVC: Bool
    public var supportsHDR: Bool
    public var supportsClipboard: Bool
    public var supportsAudio: Bool
    public var supportsVirtualDisplay: Bool

    public init(
        supportsHEVC: Bool,
        supportsHDR: Bool,
        supportsClipboard: Bool,
        supportsAudio: Bool,
        supportsVirtualDisplay: Bool
    ) {
        self.supportsHEVC = supportsHEVC
        self.supportsHDR = supportsHDR
        self.supportsClipboard = supportsClipboard
        self.supportsAudio = supportsAudio
        self.supportsVirtualDisplay = supportsVirtualDisplay
    }
}

public struct SessionOffer: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let sessionID: UUID
    public let host: HostIdentity
    public var displays: [DisplayDescriptor]
    public var capabilities: SessionCapabilities

    public init(
        protocolVersion: Int = CastProtocol.currentVersion,
        sessionID: UUID,
        host: HostIdentity,
        displays: [DisplayDescriptor],
        capabilities: SessionCapabilities
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.host = host
        self.displays = displays
        self.capabilities = capabilities
    }
}

public struct SessionAnswer: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public var selectedDisplayID: UInt32
    public var viewportSize: CastSize
    public var preferredFramesPerSecond: Int
    public var prefersHEVC: Bool

    public init(
        sessionID: UUID,
        selectedDisplayID: UInt32,
        viewportSize: CastSize,
        preferredFramesPerSecond: Int,
        prefersHEVC: Bool
    ) {
        self.sessionID = sessionID
        self.selectedDisplayID = selectedDisplayID
        self.viewportSize = viewportSize
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.prefersHEVC = prefersHEVC
    }
}
