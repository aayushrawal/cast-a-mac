import CastCore
import CastMedia
import Foundation
import Network

public final class LANVideoBroadcaster: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.castamac.lan-broadcaster")
    private let listener: NWListener
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var latestConfiguration: Data?
    private var controlFramers: [ObjectIdentifier: ControlWireFramer] = [:]

    public var onStateChange: (@Sendable (String) -> Void)?
    public var onControlMessage: (@Sendable (ControlMessage) -> Void)?

    public init(
        port: UInt16,
        hostID: UUID,
        hostName: String
    ) throws {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw NWError.posix(.EINVAL)
        }
        listener = try NWListener(using: .tcp, on: networkPort)
        let txtRecord = NWTXTRecord([
            "hostID": hostID.uuidString,
            "version": String(CastProtocol.currentVersion)
        ])
        listener.service = NWListener.Service(
            name: hostName,
            type: "_castamac._tcp",
            txtRecord: txtRecord
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
            controlFramers.removeAll()
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
        controlFramers[id] = ControlWireFramer()
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
                self.controlFramers.removeValue(forKey: id)
            } else if case .cancelled = state {
                self.connections.removeValue(forKey: id)
                self.controlFramers.removeValue(forKey: id)
            }
        }
        connection.start(queue: queue)
        receiveControl(from: connection, id: id)
    }

    private func receiveControl(from connection: NWConnection, id: ObjectIdentifier) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let data {
                do {
                    var framer = self.controlFramers[id] ?? ControlWireFramer()
                    let messages = try framer.append(data)
                    self.controlFramers[id] = framer
                    messages.forEach { self.onControlMessage?($0) }
                } catch {
                    self.onStateChange?("control framing error: \(error)")
                    connection.cancel()
                    return
                }
            }
            if !isComplete, error == nil {
                self.receiveControl(from: connection, id: id)
            }
        }
    }
}
