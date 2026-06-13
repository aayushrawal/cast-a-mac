import CastCore
import CastMedia
import Foundation

public final class RelayVideoReceiver: @unchecked Sendable {
    public typealias PacketHandler = @Sendable (MediaPacket) -> Void

    private let task: URLSessionWebSocketTask
    private let sender: RelayMessageSender
    private let packetHandler: PacketHandler
    private let sequenceLock = NSLock()
    private var sequenceNumber: UInt64 = 0
    private var receiveTask: Task<Void, Never>?

    public var onStateChange: (@Sendable (String) -> Void)?

    public init(
        baseURL: URL,
        hostID: UUID,
        accessToken: String,
        packetHandler: @escaping PacketHandler
    ) throws {
        self.packetHandler = packetHandler
        let url = try RelayURL.websocket(
            baseURL: baseURL,
            path: "/v1/client/\(hostID.uuidString)"
        )
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        sender = RelayMessageSender(
            task: task,
            maximumPendingMessages: 256
        )
    }

    public func start() {
        task.resume()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await task.send(.string("ready"))
                onStateChange?("relay: ready")
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard case let .data(data) = message else {
                        continue
                    }
                    packetHandler(try MediaPacketCodec.decode(data))
                }
            } catch {
                onStateChange?("relay: failed \(error.localizedDescription)")
            }
        }
    }

    public func stop() {
        receiveTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
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

    public func sendKey(
        keyCode: UInt16,
        isPressed: Bool,
        modifiers: KeyModifiers = []
    ) {
        sendInput(
            .key(
                keyCode: keyCode,
                isPressed: isPressed,
                modifiers: modifiers
            )
        )
    }

    private func sendInput(_ event: InputEvent) {
        sequenceLock.lock()
        sequenceNumber &+= 1
        let sequence = sequenceNumber
        sequenceLock.unlock()
        let message = ControlMessage.input(
            InputEnvelope(
                sequenceNumber: sequence,
                timestamp: Date.timeIntervalSinceReferenceDate,
                event: event
            )
        )
        guard let data = try? ControlWireCodec.encode(message) else {
            return
        }
        sender.enqueue(.data(data))
    }
}
