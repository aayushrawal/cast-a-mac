import Foundation
import Testing
@testable import CastCore

@Test
func controlWireFramerHandlesFragmentation() throws {
    let first = ControlMessage.input(
        InputEnvelope(
            sequenceNumber: 1,
            timestamp: 1,
            event: .pointerMoved(position: CastPoint(x: 0.25, y: 0.75))
        )
    )
    let second = ControlMessage.clipboard("hello")
    let data = try ControlWireCodec.encode(first) + ControlWireCodec.encode(second)
    var framer = ControlWireFramer()

    #expect(try framer.append(data.prefix(5)).isEmpty)
    #expect(try framer.append(data.dropFirst(5)) == [first, second])
}
