import Foundation

public enum MediaPacket: Equatable, Sendable {
    case videoConfiguration(sps: Data, pps: Data)
    case videoFrame(data: Data, presentationTimeNanoseconds: Int64, isKeyFrame: Bool)
    case heartbeat(sentAtNanoseconds: Int64)
}

public enum MediaPacketCodecError: Error, Equatable {
    case invalidHeader
    case unsupportedVersion
    case invalidPacket
    case packetTooLarge
}

public enum MediaPacketCodec {
    public static let headerLength = 20
    public static let maximumPayloadLength = 32 * 1_024 * 1_024

    private static let magic: [UInt8] = [0x43, 0x41, 0x53, 0x54]
    private static let version: UInt8 = 1

    public static func encode(_ packet: MediaPacket) throws -> Data {
        let kind: UInt8
        let flags: UInt8
        let timestamp: Int64
        let payload: Data

        switch packet {
        case let .videoConfiguration(sps, pps):
            guard sps.count <= UInt16.max, pps.count <= UInt16.max else {
                throw MediaPacketCodecError.packetTooLarge
            }
            kind = 1
            flags = 0
            timestamp = 0
            var body = Data()
            body.appendInteger(UInt16(sps.count))
            body.appendInteger(UInt16(pps.count))
            body.append(sps)
            body.append(pps)
            payload = body
        case let .videoFrame(data, presentationTimeNanoseconds, isKeyFrame):
            kind = 2
            flags = isKeyFrame ? 1 : 0
            timestamp = presentationTimeNanoseconds
            payload = data
        case let .heartbeat(sentAtNanoseconds):
            kind = 3
            flags = 0
            timestamp = sentAtNanoseconds
            payload = Data()
        }

        guard payload.count <= maximumPayloadLength else {
            throw MediaPacketCodecError.packetTooLarge
        }

        var result = Data(magic)
        result.append(version)
        result.append(kind)
        result.append(flags)
        result.append(0)
        result.appendInteger(UInt32(payload.count))
        result.appendInteger(UInt64(bitPattern: timestamp))
        result.append(payload)
        return result
    }

    public static func decode(_ data: Data) throws -> MediaPacket {
        guard data.count >= headerLength else {
            throw MediaPacketCodecError.invalidHeader
        }
        guard Array(data.prefix(4)) == magic else {
            throw MediaPacketCodecError.invalidHeader
        }
        guard data[4] == version else {
            throw MediaPacketCodecError.unsupportedVersion
        }

        let kind = data[5]
        let flags = data[6]
        let payloadLength = Int(data.readInteger(at: 8, as: UInt32.self))
        let timestampBits = data.readInteger(at: 12, as: UInt64.self)
        let payloadStart = headerLength

        guard payloadLength <= maximumPayloadLength,
              data.count == payloadStart + payloadLength else {
            throw MediaPacketCodecError.invalidPacket
        }

        let payload = data.subdata(in: payloadStart..<data.count)
        switch kind {
        case 1:
            guard payload.count >= 4 else {
                throw MediaPacketCodecError.invalidPacket
            }
            let spsLength = Int(payload.readInteger(at: 0, as: UInt16.self))
            let ppsLength = Int(payload.readInteger(at: 2, as: UInt16.self))
            guard payload.count == 4 + spsLength + ppsLength else {
                throw MediaPacketCodecError.invalidPacket
            }
            let spsStart = 4
            let ppsStart = spsStart + spsLength
            return .videoConfiguration(
                sps: payload.subdata(in: spsStart..<ppsStart),
                pps: payload.subdata(in: ppsStart..<payload.count)
            )
        case 2:
            return .videoFrame(
                data: payload,
                presentationTimeNanoseconds: Int64(bitPattern: timestampBits),
                isKeyFrame: flags & 1 == 1
            )
        case 3:
            guard payload.isEmpty else {
                throw MediaPacketCodecError.invalidPacket
            }
            return .heartbeat(sentAtNanoseconds: Int64(bitPattern: timestampBits))
        default:
            throw MediaPacketCodecError.invalidPacket
        }
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func readInteger<T: FixedWidthInteger>(at offset: Int, as: T.Type) -> T {
        let size = MemoryLayout<T>.size
        return subdata(in: offset..<(offset + size)).withUnsafeBytes {
            T(bigEndian: $0.loadUnaligned(as: T.self))
        }
    }
}
