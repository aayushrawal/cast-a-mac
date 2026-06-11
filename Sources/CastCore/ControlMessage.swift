import Foundation

public enum DisconnectReason: String, Codable, Equatable, Sendable {
    case userRequested
    case hostUnavailable
    case protocolMismatch
    case permissionDenied
    case transportFailure
}

public enum ControlMessage: Codable, Equatable, Sendable {
    case sessionOffer(SessionOffer)
    case sessionAnswer(SessionAnswer)
    case input(InputEnvelope)
    case clipboard(String)
    case requestKeyFrame
    case ping(sequenceNumber: UInt64, sentAt: TimeInterval)
    case pong(sequenceNumber: UInt64, sentAt: TimeInterval)
    case disconnect(DisconnectReason)
}

public enum ControlCodec {
    public static func encode(_ message: ControlMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(message)
    }

    public static func decode(_ data: Data) throws -> ControlMessage {
        try JSONDecoder().decode(ControlMessage.self, from: data)
    }
}
