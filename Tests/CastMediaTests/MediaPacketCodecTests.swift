import Foundation
import Testing
@testable import CastMedia

@Test
func configurationRoundTrips() throws {
    let packet = MediaPacket.videoConfiguration(
        sps: Data([0x67, 0x64, 0x00, 0x1f]),
        pps: Data([0x68, 0xee, 0x3c, 0x80])
    )

    #expect(try MediaPacketCodec.decode(MediaPacketCodec.encode(packet)) == packet)
}

@Test
func videoFrameRoundTrips() throws {
    let packet = MediaPacket.videoFrame(
        data: Data([0, 0, 0, 2, 0x65, 0x88]),
        presentationTimeNanoseconds: 9_876_543,
        isKeyFrame: true
    )

    #expect(try MediaPacketCodec.decode(MediaPacketCodec.encode(packet)) == packet)
}

@Test
func framerHandlesSplitAndCombinedPackets() throws {
    let first = try MediaPacketCodec.encode(
        .videoConfiguration(sps: Data([1, 2]), pps: Data([3]))
    )
    let secondPacket = MediaPacket.videoFrame(
        data: Data([4, 5, 6]),
        presentationTimeNanoseconds: 100,
        isKeyFrame: false
    )
    let second = try MediaPacketCodec.encode(secondPacket)
    let combined = first + second
    var framer = MediaPacketFramer()

    #expect(try framer.append(combined.prefix(7)).isEmpty)
    let packets = try framer.append(combined.dropFirst(7))

    #expect(packets.count == 2)
    #expect(packets[1] == secondPacket)
}
