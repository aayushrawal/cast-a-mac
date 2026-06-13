import CastCore
import CastMedia
import Foundation

public final class RelayHostConnection: @unchecked Sendable {
    private let configuration: RelayHostConfiguration
    private let task: URLSessionWebSocketTask
    private let sender: RelayMessageSender
    private var receiveTask: Task<Void, Never>?
    private var controlFramer = ControlWireFramer()

    public var onStateChange: (@Sendable (String) -> Void)?
    public var onControlMessage: (@Sendable (ControlMessage) -> Void)?

    public init(configuration: RelayHostConfiguration) throws {
        self.configuration = configuration
        let url = try RelayURL.websocket(
            baseURL: configuration.baseURL,
            path: "/v1/host/\(configuration.hostID.uuidString)"
        )
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer \(configuration.hostSecret)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            configuration.hostName,
            forHTTPHeaderField: "X-Cast-Host-Name"
        )
        request.setValue(
            configuration.linkCode,
            forHTTPHeaderField: "X-Cast-Link-Code"
        )
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        sender = RelayMessageSender(
            task: task,
            maximumPendingMessages: 30
        )
    }

    public func start() {
        task.resume()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await task.send(.string("ready"))
                onStateChange?("relay host: ready")
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard case let .data(data) = message else {
                        continue
                    }
                    for control in try controlFramer.append(data) {
                        onControlMessage?(control)
                    }
                }
            } catch {
                onStateChange?(
                    "relay host: failed \(error.localizedDescription)"
                )
            }
        }
    }

    public func stop() {
        receiveTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
    }

    public func broadcast(_ packet: MediaPacket) {
        guard let data = try? MediaPacketCodec.encode(packet) else {
            return
        }
        sender.enqueue(.data(data))
    }
}
