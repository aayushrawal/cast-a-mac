import Foundation

public enum ControlWireCodecError: Error, Equatable {
    case invalidLength
    case messageTooLarge
}

public enum ControlWireCodec {
    public static let maximumMessageLength = 1_048_576

    public static func encode(_ message: ControlMessage) throws -> Data {
        let payload = try ControlCodec.encode(message)
        guard payload.count <= maximumMessageLength else {
            throw ControlWireCodecError.messageTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        data.append(payload)
        return data
    }
}

public struct ControlWireFramer: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [ControlMessage] {
        buffer.append(data)
        var messages: [ControlMessage] = []

        while buffer.count >= 4 {
            let payloadLength = Int(buffer.prefix(4).withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            })
            guard payloadLength <= ControlWireCodec.maximumMessageLength else {
                throw ControlWireCodecError.messageTooLarge
            }
            guard buffer.count >= 4 + payloadLength else {
                break
            }

            let payload = buffer.subdata(in: 4..<(4 + payloadLength))
            messages.append(try ControlCodec.decode(payload))
            buffer = Data(buffer.dropFirst(4 + payloadLength))
        }

        return messages
    }
}
