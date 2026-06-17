#if os(macOS)
import CastCore
import CastMedia
import CastTransport
import CoreMedia
import CoreVideo
import Foundation
import CoreGraphics
import ScreenCaptureKit

public final class ScreenCaptureHost: NSObject, SCStreamOutput, SCStreamDelegate,
    @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "com.castamac.capture")
    private let broadcaster: LANVideoBroadcaster
    private let relay: RelayHostConnection?
    private var stream: SCStream?
    private var encoder: H264Encoder?
    private var inputController: RemoteInputController?
    private var powerAssertion: HostPowerAssertion?
    private var heartbeatTask: Task<Void, Never>?
    private let stateLock = NSLock()
    private var isStopping = false

    public var onCaptureStopped: (@Sendable (String) -> Void)?

    public init(
        port: UInt16,
        relayConfiguration: RelayHostConfiguration? = nil
    ) throws {
        let identity = HostIdentityStore.loadOrCreate()
        broadcaster = try LANVideoBroadcaster(
            port: port,
            hostID: identity.id,
            hostName: identity.name
        )
        relay = try relayConfiguration.map {
            try RelayHostConnection(configuration: $0)
        }
        super.init()
        broadcaster.onStateChange = { print($0) }
        relay?.onStateChange = { print($0) }
    }

    public func start() async throws {
        stateLock.withLock {
            isStopping = false
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw HostError.screenRecordingPermissionDenied
        }
        do {
            powerAssertion = try HostPowerAssertion()
        } catch {
            fputs("Warning: could not prevent idle sleep: \(error)\n", stderr)
        }
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw HostError.noDisplays
        }
        RemoteInputController.requestAccessibilityPermission()
        let inputController = RemoteInputController(displayID: display.displayID)
        self.inputController = inputController
        broadcaster.onControlMessage = { [weak inputController] message in
            inputController?.handle(message)
        }
        relay?.onControlMessage = { [weak inputController] message in
            inputController?.handle(message)
        }

        let dimensions = Self.outputDimensions(
            width: CGDisplayPixelsWide(display.displayID),
            height: CGDisplayPixelsHigh(display.displayID),
            maximumLongEdge: 4_096
        )
        encoder = try H264Encoder(
            width: Int32(dimensions.width),
            height: Int32(dimensions.height),
            framesPerSecond: 60,
            averageBitRate: 32_000_000
        ) { [broadcaster, relay] packet in
            broadcaster.broadcast(packet)
            relay?.broadcast(packet)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.sourceRect = CGRect(
            x: 0,
            y: 0,
            width: display.width,
            height: display.height
        )
        configuration.destinationRect = CGRect(
            x: 0,
            y: 0,
            width: dimensions.width,
            height: dimensions.height
        )
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        self.stream = stream

        broadcaster.start()
        relay?.start()
        startHeartbeat()
        try await stream.startCapture()
        print(
            "Capturing display \(display.displayID) at "
                + "\(dimensions.width)x\(dimensions.height)"
        )
    }

    public func stop() async throws {
        stateLock.withLock {
            isStopping = true
        }
        var stopError: (any Error)?
        do {
            try await stream?.stopCapture()
        } catch {
            stopError = error
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        broadcaster.stop()
        relay?.stop()
        stream = nil
        encoder = nil
        inputController = nil
        powerAssertion = nil
        if let stopError {
            throw stopError
        }
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        let presentationTime = sampleBuffer.presentationTimeStamp
        let duration = sampleBuffer.duration.isValid
            ? sampleBuffer.duration
            : CMTime(value: 1, timescale: 60)
        do {
            try encoder?.encode(
                pixelBuffer: pixelBuffer,
                presentationTimeStamp: presentationTime,
                duration: duration
            )
        } catch {
            fputs("Encode failed: \(error)\n", stderr)
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        fputs("Capture stopped: \(error)\n", stderr)
        let shouldRecover = stateLock.withLock {
            !isStopping
        }
        if shouldRecover {
            onCaptureStopped?(error.localizedDescription)
        }
    }

    private static func outputDimensions(
        width: Int,
        height: Int,
        maximumLongEdge: Int
    ) -> (width: Int, height: Int) {
        let scale = min(1, Double(maximumLongEdge) / Double(max(width, height)))
        let outputWidth = max(2, Int(Double(width) * scale) & ~1)
        let outputHeight = max(2, Int(Double(height) * scale) & ~1)
        return (outputWidth, outputHeight)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else {
                    return
                }
                let packet = MediaPacket.heartbeat(
                    sentAtNanoseconds: Int64(
                        Date.timeIntervalSinceReferenceDate * 1_000_000_000
                    )
                )
                self.broadcaster.broadcast(packet)
                self.relay?.broadcast(packet)
            }
        }
    }
}

public enum HostError: LocalizedError {
    case noDisplays
    case screenRecordingPermissionDenied

    public var errorDescription: String? {
        switch self {
        case .noDisplays:
            "No active Mac display is available to capture."
        case .screenRecordingPermissionDenied:
            """
            Screen Recording permission is denied. Open System Settings > \
            Privacy & Security > Screen & System Audio Recording, enable the \
            terminal app running cast-host, then quit and reopen that terminal.
            """
        }
    }
}
#endif
