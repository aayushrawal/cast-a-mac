import CastCore
import CastMedia
import Foundation
import Network

public final class LANVideoReceiver: @unchecked Sendable {
    public typealias PacketHandler = @Sendable (MediaPacket) -> Void

    private let queue = DispatchQueue(label: "com.castamac.lan-receiver")
    private let connection: NWConnection
    private var framer = MediaPacketFramer()
    private let packetHandler: PacketHandler
    private let sequenceLock = NSLock()
    private var sequenceNumber: UInt64 = 0

    public var onStateChange: (@Sendable (String) -> Void)?

    public init(host: String, port: UInt16, packetHandler: @escaping PacketHandler) {
        self.packetHandler = packetHandler
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
    }

    public init(endpoint: NWEndpoint, packetHandler: @escaping PacketHandler) {
        self.packetHandler = packetHandler
        connection = NWConnection(to: endpoint, using: .tcp)
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?("connection: \(state)")
        }
        connection.start(queue: queue)
        receive()
    }

    public func stop() {
        connection.cancel()
    }

    public func send(_ message: ControlMessage) {
        guard let data = try? ControlWireCodec.encode(message) else {
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    public func movePointer(x: Double, y: Double) {
        sendInput(.pointerMoved(position: CastPoint(x: x, y: y)))
    }

    public func setPointerButton(
        _ button: PointerButton,
        isPressed: Bool,
        x: Double,
        y: Double
    ) {
        sendInput(
            .pointerButton(
                button: button,
                isPressed: isPressed,
                position: CastPoint(x: x, y: y)
            )
        )
    }

    public func scroll(deltaX: Double, deltaY: Double) {
        sendInput(.scroll(deltaX: deltaX, deltaY: deltaY))
    }

    public func sendText(_ text: String) {
        sendInput(.text(text))
    }

    private func sendInput(_ event: InputEvent) {
        sequenceLock.lock()
        sequenceNumber &+= 1
        let sequence = sequenceNumber
        sequenceLock.unlock()
        send(
            .input(
                InputEnvelope(
                    sequenceNumber: sequence,
                    timestamp: Date.timeIntervalSinceReferenceDate,
                    event: event
                )
            )
        )
    }

    private func receive() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 1_048_576
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                do {
                    for packet in try self.framer.append(data) {
                        self.packetHandler(packet)
                    }
                } catch {
                    self.onStateChange?("framing error: \(error)")
                    self.connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }
}
