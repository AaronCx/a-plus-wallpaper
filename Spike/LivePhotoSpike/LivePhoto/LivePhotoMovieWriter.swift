import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

enum LivePhotoWriteError: Error, CustomStringConvertible {
    case writerFailed(String)
    case inputRejected(String)
    case timedOut(String)
    case metadataFormatFailed(OSStatus)
    case noPixelBufferPool
    case pixelBufferFromPoolFailed(CVReturn)
    case stillEncodingFailed(String)

    var description: String {
        switch self {
        case .writerFailed(let message): "AVAssetWriter failed: \(message)"
        case .inputRejected(let what): "AVAssetWriter rejected \(what)."
        case .timedOut(let what): "Timed out waiting for \(what)."
        case .metadataFormatFailed(let status): "Could not create the metadata format description (\(status))."
        case .noPixelBufferPool: "The pixel buffer adaptor has no pool."
        case .pixelBufferFromPoolFailed(let status): "Could not get a pixel buffer from the pool (\(status))."
        case .stillEncodingFailed(let message): "Still image encoding failed: \(message)"
        }
    }
}

/// Writes the video half of a Live Photo pair: a QuickTime movie whose frames
/// stream through a `CVPixelBufferPool` (never all in memory), tagged with the
/// pair's content identifier and a still-image-time timed metadata track.
enum LivePhotoMovieWriter {
    /// Timescale shared by the movie and every sample time; divisible by all
    /// supported frame rates.
    static let timescale: CMTimeScale = 600

    struct Settings: Sendable {
        let variant: LivePhotoVariant
        let size: PixelSize
        let averageBitRate: Int
        let keyFrameInterval: Int
        let allowFrameReordering: Bool
        let stillFrameIndex: Int
        let stillImageTimeValue: Int
        let stillImageTimeDurationFrames: Int
        let includeStillImageTransform: Bool
        let associateMetadataWithVideo: Bool

        var frameDuration: CMTime { CMTime(value: CMTimeValue(timescale) / CMTimeValue(variant.framesPerSecond), timescale: timescale) }
        func time(ofFrame index: Int) -> CMTime { CMTimeMultiply(frameDuration, multiplier: Int32(index)) }
        var stillImageTime: CMTime { time(ofFrame: stillFrameIndex) }
        var clipDuration: CMTime { time(ofFrame: variant.frameCount) }
    }

    static func videoOutputSettings(for settings: Settings) -> [String: Any] {
        let codec: AVVideoCodecType
        let profile: String
        switch settings.variant.codec {
        case .hevc:
            codec = .hevc
            profile = kVTProfileLevel_HEVC_Main_AutoLevel as String
        case .h264:
            codec = .h264
            profile = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: settings.size.width,
            AVVideoHeightKey: settings.size.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.averageBitRate,
                AVVideoExpectedSourceFrameRateKey: settings.variant.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: settings.keyFrameInterval,
                AVVideoAllowFrameReorderingKey: settings.allowFrameReordering,
                AVVideoProfileLevelKey: profile,
            ],
        ]
    }

    /// Writes the movie. `renderFrame` fills each pooled pixel buffer for frame `index`.
    static func write(
        to url: URL,
        contentIdentifier: String,
        settings: Settings,
        renderFrame: (_ index: Int, _ buffer: CVPixelBuffer) async throws -> Void,
        progress: (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieTimeScale = timescale
        writer.metadata = [LivePhotoMetadata.contentIdentifierItem(contentIdentifier)]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings(for: settings))
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = timescale
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: SpikeFrameRenderer.pixelBufferAttributes(for: settings.size))
        guard writer.canAdd(videoInput) else { throw LivePhotoWriteError.inputRejected("the video input") }
        writer.add(videoInput)

        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata, outputSettings: nil,
            sourceFormatHint: try LivePhotoMetadata.stillImageTimeFormatDescription(
                includeTransform: settings.includeStillImageTransform))
        metadataInput.expectsMediaDataInRealTime = false
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else { throw LivePhotoWriteError.inputRejected("the metadata input") }
        writer.add(metadataInput)

        if settings.associateMetadataWithVideo {
            // `tref cdsc`: the metadata track describes the video track.
            let referent = AVAssetTrack.AssociationType.metadataReferent.rawValue
            guard metadataInput.canAddTrackAssociation(withTrackOf: videoInput, type: referent) else {
                throw LivePhotoWriteError.inputRejected("the metadata-to-video track association")
            }
            metadataInput.addTrackAssociation(withTrackOf: videoInput, type: referent)
        }

        guard writer.startWriting() else {
            throw LivePhotoWriteError.writerFailed(writer.error?.localizedDescription ?? "startWriting returned false")
        }
        writer.startSession(atSourceTime: .zero)

        do {
            // The single still-image-time sample goes first and its input is
            // finished straight away, so the writer's interleaving never makes
            // the video input wait on a metadata track that has nothing more to say.
            try await waitUntilReady(metadataInput, of: writer, what: "the metadata input")
            let group = LivePhotoMetadata.stillImageTimeGroup(
                value: settings.stillImageTimeValue,
                at: settings.stillImageTime,
                duration: CMTimeMultiply(settings.frameDuration, multiplier: Int32(settings.stillImageTimeDurationFrames)),
                transformReferenceSize: settings.includeStillImageTransform ? settings.size : nil)
            guard metadataAdaptor.append(group) else {
                throw LivePhotoWriteError.writerFailed(writer.error?.localizedDescription ?? "metadata append failed")
            }
            metadataInput.markAsFinished()

            guard let pool = adaptor.pixelBufferPool else { throw LivePhotoWriteError.noPixelBufferPool }
            let frameCount = settings.variant.frameCount
            for index in 0..<frameCount {
                try Task.checkCancellation()
                try await waitUntilReady(videoInput, of: writer, what: "the video input")
                var buffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
                guard status == kCVReturnSuccess, let buffer else { throw LivePhotoWriteError.pixelBufferFromPoolFailed(status) }
                try await renderFrame(index, buffer)
                guard adaptor.append(buffer, withPresentationTime: settings.time(ofFrame: index)) else {
                    throw LivePhotoWriteError.writerFailed(writer.error?.localizedDescription ?? "frame \(index) append failed")
                }
                progress(Double(index + 1) / Double(frameCount))
            }
            videoInput.markAsFinished()
            writer.endSession(atSourceTime: settings.clipDuration)
            await writer.finishWriting()
        } catch {
            writer.cancelWriting()
            throw error
        }

        guard writer.status == .completed else {
            throw LivePhotoWriteError.writerFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    /// Offline writing: inputs are almost always ready, so a short poll is
    /// simpler than bridging `requestMediaDataWhenReady` into Swift concurrency.
    private static func waitUntilReady(_ input: AVAssetWriterInput, of writer: AVAssetWriter, what: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed {
                throw LivePhotoWriteError.writerFailed(writer.error?.localizedDescription ?? "failed while waiting")
            }
            if clock.now > deadline { throw LivePhotoWriteError.timedOut(what) }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
