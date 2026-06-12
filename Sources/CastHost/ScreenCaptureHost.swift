#if os(macOS)
import CastMedia
import CastTransport
import CoreMedia
import CoreVideo
import Foundation
import CoreGraphics
import ScreenCaptureKit

final class ScreenCaptureHost: NSObject, SCStreamOutput, SCStreamDelegate,
    @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "com.castamac.capture")
    private let broadcaster: LANVideoBroadcaster
    private var stream: SCStream?
    private var encoder: H264Encoder?
    private var inputController: RemoteInputController?
    private var powerAssertion: HostPowerAssertion?

    init(port: UInt16) throws {
        broadcaster = try LANVideoBroadcaster(port: port)
        super.init()
        broadcaster.onStateChange = { print($0) }
    }

    func start() async throws {
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

        let dimensions = Self.outputDimensions(
            width: display.width,
            height: display.height,
            maximumLongEdge: 2_732
        )
        encoder = try H264Encoder(
            width: Int32(dimensions.width),
            height: Int32(dimensions.height),
            framesPerSecond: 60,
            averageBitRate: 18_000_000
        ) { [broadcaster] packet in
            broadcaster.broadcast(packet)
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
        try await stream.startCapture()
        print(
            "Capturing display \(display.displayID) at "
                + "\(dimensions.width)x\(dimensions.height)"
        )
    }

    func stop() async throws {
        try await stream?.stopCapture()
        broadcaster.stop()
        stream = nil
        encoder = nil
        powerAssertion = nil
    }

    func stream(
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

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        fputs("Capture stopped: \(error)\n", stderr)
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
}

enum HostError: LocalizedError {
    case noDisplays
    case screenRecordingPermissionDenied

    var errorDescription: String? {
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
