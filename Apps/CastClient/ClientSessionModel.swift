import CastCore
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
    @Published private(set) var rememberedMacs: [RememberedMac] = []
    @Published private(set) var connectionState: ConnectionState = .browsing
    @Published private(set) var latestFrame: CVPixelBuffer?
    @Published var showsLinkMac = false
    @Published private(set) var isLinkingMac = false
    @Published private(set) var internetStatus =
        "Enter the relay URL and link code shown by the Mac app."

    private let discovery = LANHostDiscovery()
    private let rememberedStore = RememberedMacStore()
    private let coordinationClient = RelayCoordinationClient()
    private var receiver: (any ClientVideoReceiver)?
    private var decoder: H264Decoder?
    private var activeMacID: UUID?
    private var activeMacName: String?
    private var connectionGeneration = UUID()
    private var lastFrameReceivedAt: Date?
    private var frameWatchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    init() {
        rememberedMacs = rememberedStore.load()
        discovery.onHostsChanged = { [weak self] hosts in
            Task { @MainActor in
                self?.updateDiscoveredHosts(hosts)
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
        remember(host)
        activeMacID = host.hostID
        activeMacName = host.name
        connectLocally(to: host)
    }

    func connect(to rememberedMac: RememberedMac) {
        activeMacID = rememberedMac.id
        activeMacName = rememberedMac.name
        connectToActiveMac()
    }

    func linkMac(relayURLText: String, code: String) async {
        guard let baseURL = URL(
            string: relayURLText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ) else {
            internetStatus = "Enter a valid HTTPS relay URL."
            return
        }

        isLinkingMac = true
        defer { isLinkingMac = false }
        do {
            let credential = try await coordinationClient.link(
                baseURL: baseURL,
                code: code.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
            let mac = RememberedMac(
                id: credential.host.id,
                name: credential.host.name,
                lastSeenAt: credential.host.lastSeenAt,
                relayBaseURL: credential.baseURL,
                relayAccessToken: credential.accessToken
            )
            upsertRememberedMac(mac)
            internetStatus = "\(mac.name) is linked for internet access."
            showsLinkMac = false
        } catch {
            internetStatus = error.localizedDescription
        }
    }

    func disconnect() {
        activeMacID = nil
        activeMacName = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownConnection()
        connectionState = .browsing
    }

    private func tearDownConnection() {
        connectionGeneration = UUID()
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil
        receiver?.stop()
        receiver = nil
        decoder = nil
        lastFrameReceivedAt = nil
        latestFrame = nil
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

    func sendKey(
        keyCode: UInt16,
        isPressed: Bool,
        modifiers: KeyModifiers = []
    ) {
        receiver?.sendKey(
            keyCode: keyCode,
            isPressed: isPressed,
            modifiers: modifiers
        )
    }

    func performThreeFingerSwipe(_ direction: ThreeFingerSwipeDirection) {
        let keyCode: UInt16
        switch direction {
        case .left:
            keyCode = 124
        case .right:
            keyCode = 123
        case .down:
            keyCode = 125
        case .up:
            keyCode = 126
        }
        receiver?.sendKey(keyCode: keyCode, isPressed: true, modifiers: .control)
        receiver?.sendKey(keyCode: keyCode, isPressed: false, modifiers: .control)
    }

    func isNearby(_ rememberedMac: RememberedMac) -> Bool {
        hosts.contains { $0.hostID == rememberedMac.id }
    }

    func hasInternetAccess(_ rememberedMac: RememberedMac) -> Bool {
        rememberedMac.relayBaseURL != nil
            && rememberedMac.relayAccessToken != nil
    }

    private func updateDiscoveredHosts(_ hosts: [LANDiscoveredHost]) {
        self.hosts = hosts
        var changed = false
        for host in hosts {
            guard let hostID = host.hostID,
                  let index = rememberedMacs.firstIndex(where: {
                      $0.id == hostID
                  }) else {
                continue
            }
            rememberedMacs[index].name = host.name
            rememberedMacs[index].lastSeenAt = Date()
            changed = true
        }
        if changed {
            rememberedStore.save(rememberedMacs)
        }
        if receiver == nil,
           reconnectTask == nil,
           let activeMacID,
           hosts.contains(where: { $0.hostID == activeMacID }) {
            connectToActiveMac()
        }
    }

    private func remember(_ host: LANDiscoveredHost) {
        guard let hostID = host.hostID else {
            return
        }
        let record = RememberedMac(
            id: hostID,
            name: host.name,
            lastSeenAt: Date(),
            relayBaseURL: rememberedMacs.first(where: {
                $0.id == hostID
            })?.relayBaseURL,
            relayAccessToken: rememberedMacs.first(where: {
                $0.id == hostID
            })?.relayAccessToken
        )
        upsertRememberedMac(record)
    }

    private func upsertRememberedMac(_ record: RememberedMac) {
        if let index = rememberedMacs.firstIndex(where: {
            $0.id == record.id
        }) {
            rememberedMacs[index] = record
        } else {
            rememberedMacs.append(record)
        }
        rememberedMacs.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        rememberedStore.save(rememberedMacs)
    }

    private func connectOverRelay(
        to mac: RememberedMac,
        baseURL: URL,
        accessToken: String
    ) {
        tearDownConnection()
        connectionState = .connecting(mac.name)
        let generation = connectionGeneration
        lastFrameReceivedAt = Date()

        let decoder = H264Decoder { [weak self] pixelBuffer, _ in
            Task { @MainActor in
                self?.receivedFrame(pixelBuffer, generation: generation)
            }
        }
        do {
            let receiver = try RelayVideoReceiver(
                baseURL: baseURL,
                hostID: mac.id,
                accessToken: accessToken
            ) { [weak decoder] packet in
                do {
                    try decoder?.consume(packet)
                } catch {
                    print("Relay decode failed: \(error)")
                }
            }
            receiver.onStateChange = { [weak self] state in
                Task { @MainActor in
                    guard let self,
                          self.connectionGeneration == generation else {
                        return
                    }
                    if state.contains("ready") {
                        self.connectionState = .connected(mac.name)
                        self.startFrameWatchdog(generation: generation)
                    } else if state.contains("failed")
                                || state.contains("cancelled") {
                        self.scheduleReconnect(generation: generation)
                    }
                }
            }
            self.decoder = decoder
            self.receiver = receiver
            receiver.start()
        } catch {
            scheduleReconnect(generation: generation)
        }
    }

    private func connectLocally(to host: LANDiscoveredHost) {
        tearDownConnection()
        connectionState = .connecting(host.name)
        let generation = connectionGeneration
        lastFrameReceivedAt = Date()

        let decoder = H264Decoder { [weak self] pixelBuffer, _ in
            Task { @MainActor in
                self?.receivedFrame(pixelBuffer, generation: generation)
            }
        }
        let receiver = LANVideoReceiver(
            endpoint: host.endpoint
        ) { [weak decoder] packet in
            do {
                try decoder?.consume(packet)
            } catch {
                print("Decode failed: \(error)")
            }
        }
        receiver.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self,
                      self.connectionGeneration == generation else {
                    return
                }
                if state.contains("ready") {
                    self.connectionState = .connected(host.name)
                    self.startFrameWatchdog(generation: generation)
                } else if state.contains("failed")
                            || state.contains("cancelled") {
                    self.scheduleReconnect(generation: generation)
                }
            }
        }

        self.decoder = decoder
        self.receiver = receiver
        receiver.start()
    }

    private func connectToActiveMac() {
        guard let activeMacID, let activeMacName else {
            return
        }
        if let localHost = hosts.first(where: {
            $0.hostID == activeMacID
        }) {
            connectLocally(to: localHost)
            return
        }
        if let mac = rememberedMacs.first(where: { $0.id == activeMacID }),
           let baseURL = mac.relayBaseURL,
           let accessToken = mac.relayAccessToken {
            connectOverRelay(
                to: mac,
                baseURL: baseURL,
                accessToken: accessToken
            )
            return
        }
        tearDownConnection()
        connectionState = .connecting(activeMacName)
        scheduleReconnect(generation: connectionGeneration)
    }

    private func receivedFrame(
        _ pixelBuffer: CVPixelBuffer,
        generation: UUID
    ) {
        guard connectionGeneration == generation else {
            return
        }
        latestFrame = pixelBuffer
        lastFrameReceivedAt = Date()
    }

    private func startFrameWatchdog(generation: UUID) {
        frameWatchdogTask?.cancel()
        frameWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self,
                      self.connectionGeneration == generation else {
                    return
                }
                guard let lastFrameReceivedAt = self.lastFrameReceivedAt,
                      Date().timeIntervalSince(lastFrameReceivedAt) > 8 else {
                    continue
                }
                self.scheduleReconnect(generation: generation)
                return
            }
        }
    }

    private func scheduleReconnect(generation: UUID) {
        guard connectionGeneration == generation,
              activeMacID != nil,
              reconnectTask == nil else {
            return
        }
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil
        receiver?.stop()
        receiver = nil
        decoder = nil
        latestFrame = nil
        lastFrameReceivedAt = nil
        connectionState = .connecting(activeMacName ?? "Mac")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self,
                  self.connectionGeneration == generation else {
                return
            }
            self.reconnectTask = nil
            self.connectToActiveMac()
        }
    }
}

private protocol ClientVideoReceiver: AnyObject {
    func start()
    func stop()
    func movePointer(x: Double, y: Double)
    func setPointerButton(
        _ button: PointerButton,
        isPressed: Bool,
        x: Double,
        y: Double
    )
    func scroll(deltaX: Double, deltaY: Double)
    func sendText(_ text: String)
    func sendKey(
        keyCode: UInt16,
        isPressed: Bool,
        modifiers: KeyModifiers
    )
}

extension LANVideoReceiver: ClientVideoReceiver {}
extension RelayVideoReceiver: ClientVideoReceiver {}
