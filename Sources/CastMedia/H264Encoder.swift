import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum H264EncoderError: Error {
    case sessionCreationFailed(OSStatus)
    case propertyConfigurationFailed(OSStatus)
    case frameEncodingFailed(OSStatus)
}

public final class H264Encoder: @unchecked Sendable {
    public typealias PacketHandler = @Sendable (MediaPacket) -> Void

    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var lastParameterSets: (sps: Data, pps: Data)?
    private let packetHandler: PacketHandler

    public init(
        width: Int32,
        height: Int32,
        framesPerSecond: Int32 = 30,
        averageBitRate: Int = 8_000_000,
        packetHandler: @escaping PacketHandler
    ) throws {
        self.packetHandler = packetHandler

        var createdSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &createdSession
        )
        guard status == noErr, let createdSession else {
            throw H264EncoderError.sessionCreationFailed(status)
        }
        session = createdSession

        try setProperty(kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        try setProperty(kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        try setProperty(
            kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Main_AutoLevel
        )
        try setProperty(
            kVTCompressionPropertyKey_AverageBitRate,
            value: averageBitRate as CFNumber
        )
        try setProperty(
            kVTCompressionPropertyKey_ExpectedFrameRate,
            value: framesPerSecond as CFNumber
        )
        try setProperty(
            kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: (framesPerSecond * 2) as CFNumber
        )

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(createdSession)
        guard prepareStatus == noErr else {
            throw H264EncoderError.propertyConfigurationFailed(prepareStatus)
        }
    }

    deinit {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
    }

    public func encode(
        pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        duration: CMTime
    ) throws {
        guard let session else {
            throw H264EncoderError.sessionCreationFailed(kVTInvalidSessionErr)
        }
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        guard status == noErr else {
            throw H264EncoderError.frameEncodingFailed(status)
        }
    }

    private func setProperty(_ key: CFString, value: CFTypeRef) throws {
        guard let session else {
            throw H264EncoderError.sessionCreationFailed(kVTInvalidSessionErr)
        }
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else {
            throw H264EncoderError.propertyConfigurationFailed(status)
        }
    }

    private static let outputCallback: VTCompressionOutputCallback = {
        refcon,
        _,
        status,
        infoFlags,
        sampleBuffer
        in
        guard status == noErr,
              !infoFlags.contains(.frameDropped),
              let refcon,
              let sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleEncodedSample(sampleBuffer)
    }

    private func handleEncodedSample(_ sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[CFString: Any]]
        let isKeyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil

        if isKeyFrame,
           let format = CMSampleBufferGetFormatDescription(sampleBuffer),
           let parameterSets = Self.parameterSets(from: format) {
            lock.lock()
            let changed = lastParameterSets?.sps != parameterSets.sps
                || lastParameterSets?.pps != parameterSets.pps
            if changed {
                lastParameterSets = parameterSets
            }
            lock.unlock()
            if changed {
                packetHandler(
                    .videoConfiguration(sps: parameterSets.sps, pps: parameterSets.pps)
                )
            }
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: bytes.baseAddress!
            )
        }
        guard status == noErr else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let nanoseconds = Int64(timestamp.seconds * 1_000_000_000)
        packetHandler(
            .videoFrame(
                data: data,
                presentationTimeNanoseconds: nanoseconds,
                isKeyFrame: isKeyFrame
            )
        )
    }

    private static func parameterSets(
        from format: CMFormatDescription
    ) -> (sps: Data, pps: Data)? {
        var spsPointer: UnsafePointer<UInt8>?
        var spsSize = 0
        var parameterSetCount = 0
        var nalHeaderLength: Int32 = 0
        let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalHeaderLength
        )

        var ppsPointer: UnsafePointer<UInt8>?
        var ppsSize = 0
        let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )

        guard spsStatus == noErr,
              ppsStatus == noErr,
              parameterSetCount >= 2,
              let spsPointer,
              let ppsPointer else {
            return nil
        }
        return (
            Data(bytes: spsPointer, count: spsSize),
            Data(bytes: ppsPointer, count: ppsSize)
        )
    }
}
