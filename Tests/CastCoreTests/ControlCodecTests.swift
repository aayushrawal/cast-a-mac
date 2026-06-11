import Foundation
import Testing
@testable import CastCore

@Test
func controlMessageRoundTrips() throws {
    let sessionID = UUID()
    let offer = SessionOffer(
        sessionID: sessionID,
        host: HostIdentity(id: UUID(), name: "Studio Mac"),
        displays: [
            DisplayDescriptor(
                id: 42,
                name: "Built-in Display",
                pixelSize: CastSize(width: 3024, height: 1964),
                scaleFactor: 2
            )
        ],
        capabilities: SessionCapabilities(
            supportsHEVC: true,
            supportsHDR: false,
            supportsClipboard: true,
            supportsAudio: true,
            supportsVirtualDisplay: false
        )
    )

    let original = ControlMessage.sessionOffer(offer)
    let encoded = try ControlCodec.encode(original)
    let decoded = try ControlCodec.decode(encoded)

    #expect(decoded == original)
}

@Test
func inputEventRoundTripsWithModifiers() throws {
    let original = ControlMessage.input(
        InputEnvelope(
            sequenceNumber: 9,
            timestamp: 123.45,
            event: .key(
                keyCode: 0,
                isPressed: true,
                modifiers: [.command, .shift]
            )
        )
    )

    let encoded = try ControlCodec.encode(original)
    let decoded = try ControlCodec.decode(encoded)

    #expect(decoded == original)
}
