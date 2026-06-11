import Foundation

public struct MediaPacketFramer: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [MediaPacket] {
        buffer.append(data)
        var packets: [MediaPacket] = []

        while buffer.count >= MediaPacketCodec.headerLength {
            let payloadLength = Int(buffer.subdata(in: 8..<12).withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            })
            guard payloadLength <= MediaPacketCodec.maximumPayloadLength else {
                throw MediaPacketCodecError.packetTooLarge
            }

            let packetLength = MediaPacketCodec.headerLength + payloadLength
            guard buffer.count >= packetLength else {
                break
            }

            let packetData = buffer.prefix(packetLength)
            packets.append(try MediaPacketCodec.decode(Data(packetData)))
            buffer = Data(buffer.dropFirst(packetLength))
        }

        return packets
    }
}
