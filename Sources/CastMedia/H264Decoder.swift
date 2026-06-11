import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum H264DecoderError: Error {
    case invalidConfiguration
    case formatDescriptionFailed(OSStatus)
    case blockBufferFailed(OSStatus)
    case sampleBufferFailed(OSStatus)
    case sessionCreationFailed(OSStatus)
    case decodeFailed(OSStatus)
}

public final class H264Decoder: @unchecked Sendable {
    public typealias PixelBufferHandler = @Sendable (CVPixelBuffer, CMTime) -> Void

    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private let pixelBufferHandler: PixelBufferHandler

    public init(pixelBufferHandler: @escaping PixelBufferHandler) {
        self.pixelBufferHandler = pixelBufferHandler
    }

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    public func consume(_ packet: MediaPacket) throws {
        switch packet {
        case let .videoConfiguration(sps, pps):
            try configure(sps: sps, pps: pps)
        case let .videoFrame(data, timestamp, _):
            try decode(data: data, presentationTimeNanoseconds: timestamp)
        }
    }

    private func configure(sps: Data, pps: Data) throws {
        var description: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBytes.bindMemory(to: UInt8.self).baseAddress!
                ]
                let sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }
        guard status == noErr, let description else {
            throw H264DecoderError.formatDescriptionFailed(status)
        }

        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        var newSession: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ] as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        guard sessionStatus == noErr, let newSession else {
            throw H264DecoderError.sessionCreationFailed(sessionStatus)
        }
        formatDescription = description
        session = newSession
    }

    private func decode(data: Data, presentationTimeNanoseconds: Int64) throws {
        guard let formatDescription, let session else {
            throw H264DecoderError.invalidConfiguration
        }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = data.withUnsafeBytes { bytes in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            ).flatMapStatus {
                CMBlockBufferReplaceDataBytes(
                    with: bytes.baseAddress!,
                    blockBuffer: blockBuffer!,
                    offsetIntoDestination: 0,
                    dataLength: data.count
                )
            }
        }
        guard blockStatus == noErr, let blockBuffer else {
            throw H264DecoderError.blockBufferFailed(blockStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: presentationTimeNanoseconds,
                timescale: 1_000_000_000
            ),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = data.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw H264DecoderError.sampleBufferFailed(sampleStatus)
        }

        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression, ._EnableTemporalProcessing],
            infoFlagsOut: nil,
            outputHandler: { [pixelBufferHandler] status, _, imageBuffer, time, _ in
                guard status == noErr, let imageBuffer else {
                    return
                }
                pixelBufferHandler(imageBuffer, time)
            }
        )
        guard decodeStatus == noErr else {
            throw H264DecoderError.decodeFailed(decodeStatus)
        }
    }
}

private extension OSStatus {
    func flatMapStatus(_ next: () -> OSStatus) -> OSStatus {
        self == noErr ? next() : self
    }
}
