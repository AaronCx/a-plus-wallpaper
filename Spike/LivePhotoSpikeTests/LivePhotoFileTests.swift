import CoreMedia
import Foundation
import Testing
@testable import LivePhotoSpike

/// Checks the files themselves, before Photos is involved.
@Suite("Live Photo files", .serialized, .timeLimit(.minutes(10)))
struct LivePhotoFileTests {
    /// One variant per codec and frame rate.
    static let formatSamples = ["1.5s-30fps-hevc", "1.5s-30fps-h264", "2.0s-60fps-hevc", "2.0s-60fps-h264"]

    @Test("Still and movie carry the same content identifier and the still-image-time track", arguments: formatSamples)
    func filesAreLinked(variantID: String) async throws {
        let generator = try TestSupport.makeGenerator()
        let recipe = generator.recipe
        let variant = try #require(recipe.variants.first { $0.id == variantID })
        let size = try await TestSupport.nativePixelSize()

        let pair = try await generator.generate(variant, size: size)

        let still = try LivePhotoInspector.inspectStill(at: pair.stillURL)
        #expect(still.typeIdentifier == "public.heic")
        #expect(still.width == size.width)
        #expect(still.height == size.height)
        #expect(still.contentIdentifier == pair.contentIdentifier)

        let movie = try await LivePhotoInspector.inspectMovie(at: pair.movieURL)
        #expect(movie.contentIdentifier == pair.contentIdentifier)
        #expect(movie.videoCodec == (variant.codec == .hevc ? "hvc1" : "avc1"))
        #expect(movie.width == size.width)
        #expect(movie.height == size.height)
        #expect(movie.videoSampleCount == variant.frameCount)
        #expect(abs(movie.durationSeconds - variant.durationSeconds) < 0.5 / Double(variant.framesPerSecond))
        #expect(movie.metadataTrackCount == 1)

        let stillImageTime = try #require(movie.stillImageTime, "no still-image-time sample in \(movie.timedMetadata)")
        #expect(stillImageTime.dataType == "com.apple.metadata.datatype.int8")
        #expect(stillImageTime.numberValue == recipe.stillImageTimeTrack.value)
        #expect(abs(stillImageTime.startSeconds - pair.stillTimeSeconds) < 0.001)
        #expect(abs(stillImageTime.durationSeconds - Double(recipe.stillImageTimeTrack.durationTicks) / 600) < 0.0001)
        // The key photo sits on a frame, at least 0.5 s into the clip.
        #expect(pair.stillTimeSeconds >= 0.5)

        if recipe.stillImageTimeTrack.includeStillImageTransform {
            let transform = try #require(movie.timedItem(LivePhotoMetadata.stillImageTransformIdentifier))
            let dimensions = try #require(movie.timedItem(LivePhotoMetadata.stillImageTransformReferenceDimensionsIdentifier))
            #expect(transform.startSeconds == stillImageTime.startSeconds, "same sample as the still-image time")
            #expect(dimensions.startSeconds == stillImageTime.startSeconds, "same sample as the still-image time")
            #expect(transform.dataType == kCMMetadataBaseDataType_PerspectiveTransformF64 as String)
            #expect(dimensions.dataType == kCMMetadataBaseDataType_DimensionsF32 as String)
            #expect(transform.numbers == [1, 0, 0, 0, 1, 0, 0, 0, 1])
            #expect(dimensions.numbers == [Double(size.width), Double(size.height)])
        }
        #expect(movie.metadataTrackReferencesVideo == recipe.stillImageTimeTrack.associateWithVideoTrack)
    }

    @Test("Photos accepts the files as a Live Photo pair without touching the library")
    func photosPairsTheFiles() async throws {
        let generator = try TestSupport.makeGenerator()
        let variant = try #require(generator.recipe.variants.first)
        let size = try await TestSupport.nativePixelSize()
        let pair = try await generator.generate(variant, size: size)

        let livePhoto = try await PhotoLibraryBridge.loadLivePhoto(from: pair)
        #expect(livePhoto.size.width > 0)
    }

    @Test("Mismatched identifiers are not accepted as a pair")
    func mismatchedPairIsRejected() async throws {
        let generator = try TestSupport.makeGenerator()
        let variant = try #require(generator.recipe.variants.first)
        let size = PixelSize(width: 390, height: 844)
        let first = try await generator.generate(variant, size: size)
        let second = try await generator.generate(variant, size: size)
        // Control: each pair on its own loads at this size.
        _ = try await PhotoLibraryBridge.loadLivePhoto(from: first)
        let mismatched = LivePhotoPair(
            contentIdentifier: first.contentIdentifier, variant: variant, size: size,
            stillURL: first.stillURL, movieURL: second.movieURL,
            stillFrameIndex: first.stillFrameIndex, averageBitRate: first.averageBitRate)

        await #expect(throws: PhotoLibraryError.self) {
            _ = try await PhotoLibraryBridge.loadLivePhoto(from: mismatched)
        }
    }
}
