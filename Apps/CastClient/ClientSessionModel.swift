import CastMedia
import CastTransport
import CoreVideo
import Foundation
import SwiftUI

@MainActor
final class ClientSessionModel: ObservableObject {
    enum ConnectionState: Equatable {
        case browsing
        case connecting(String)
        case connected(String)
        case failed(String)
    }

    @Published private(set) var hosts: [LANDiscoveredHost] = []
    @Published private(set) var connectionState: ConnectionState = .browsing
    @Published private(set) var latestFrame: CVPixelBuffer?
    @Published var showsInternetPreview = false
    @Published private(set) var internetStatus =
        "Internet connections need the Cast-a-mac account and relay service."

    private let discovery = LANHostDiscovery()
    private var receiver: LANVideoReceiver?
    private var decoder: H264Decoder?

    init() {
        discovery.onHostsChanged = { [weak self] hosts in
            Task { @MainActor in
                self?.hosts = hosts
            }
        }
        discovery.onStateChange = { [weak self] state in
            guard state.contains("failed") else { return }
            Task { @MainActor in
                self?.connectionState = .failed("Mac discovery failed.")
            }
        }
    }

    func startBrowsing() {
        discovery.start()
    }

    func stopBrowsing() {
        discovery.stop()
    }

    func connect(to host: LANDiscoveredHost) {
        disconnect()
        connectionState = .connecting(host.name)

        let decoder = H264Decoder { [weak self] pixelBuffer, _ in
            Task { @MainActor in
                self?.latestFrame = pixelBuffer
            }
        }
        let receiver = LANVideoReceiver(endpoint: host.endpoint) { [weak decoder] packet in
            do {
                try decoder?.consume(packet)
            } catch {
                print("Decode failed: \(error)")
            }
        }
        receiver.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if state.contains("ready") {
                    self.connectionState = .connected(host.name)
                } else if state.contains("failed") {
                    self.connectionState = .failed("Could not connect to \(host.name).")
                }
            }
        }

        self.decoder = decoder
        self.receiver = receiver
        receiver.start()
    }

    func disconnect() {
        receiver?.stop()
        receiver = nil
        decoder = nil
        latestFrame = nil
        connectionState = .browsing
    }

    func movePointer(x: Double, y: Double) {
        receiver?.movePointer(x: x, y: y)
    }

    func setPrimaryButton(isPressed: Bool, x: Double, y: Double) {
        receiver?.setPointerButton(
            .primary,
            isPressed: isPressed,
            x: x,
            y: y
        )
    }

    func rightClick(x: Double, y: Double) {
        receiver?.setPointerButton(.secondary, isPressed: true, x: x, y: y)
        receiver?.setPointerButton(.secondary, isPressed: false, x: x, y: y)
    }

    func click(x: Double, y: Double) {
        setPrimaryButton(isPressed: true, x: x, y: y)
        setPrimaryButton(isPressed: false, x: x, y: y)
    }

    func scroll(deltaX: Double, deltaY: Double) {
        receiver?.scroll(deltaX: deltaX, deltaY: deltaY)
    }

    func sendText(_ text: String) {
        receiver?.sendText(text)
    }

    func sendKey(keyCode: UInt16, isPressed: Bool) {
        receiver?.sendKey(keyCode: keyCode, isPressed: isPressed)
    }
}
