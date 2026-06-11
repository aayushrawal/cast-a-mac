import CastMedia
import Foundation
import Network

public final class LANVideoBroadcaster: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.castamac.lan-broadcaster")
    private let listener: NWListener
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var latestConfiguration: Data?

    public var onStateChange: (@Sendable (String) -> Void)?

    public init(port: UInt16) throws {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw NWError.posix(.EINVAL)
        }
        listener = try NWListener(using: .tcp, on: networkPort)
        listener.service = NWListener.Service(
            name: ProcessInfo.processInfo.hostName,
            type: "_castamac._tcp"
        )
    }

    public func start() {
        listener.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?("listener: \(state)")
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async { [self] in
            listener.cancel()
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    public func broadcast(_ packet: MediaPacket) {
        guard let data = try? MediaPacketCodec.encode(packet) else {
            return
        }
        queue.async { [self] in
            if case .videoConfiguration = packet {
                latestConfiguration = data
            }
            for connection in connections.values {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.onStateChange?("client \(connection.endpoint): \(state)")
            if case .ready = state, let configuration = self.latestConfiguration {
                connection.send(
                    content: configuration,
                    completion: .contentProcessed { _ in }
                )
            }
            if case .failed = state {
                self.connections.removeValue(forKey: id)
            } else if case .cancelled = state {
                self.connections.removeValue(forKey: id)
            }
        }
        connection.start(queue: queue)
    }
}
