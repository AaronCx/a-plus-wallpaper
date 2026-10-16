import Foundation
import Photos
import Testing
@testable import LivePhotoSpike

/// Phase 0 DoD: save a generated pair with PHAssetCreationRequest, read it
/// back from the library, and assert it loads as a PHLivePhoto.
@Suite("Photos round trip", .serialized, .timeLimit(.minutes(10)))
struct PhotosRoundTripTests {
    @Test("A saved pair comes back from the library as a PHLivePhoto with its metadata intact")
    func roundTrip() async throws {
        try TestSupport.requireReadWriteAccess()
        let generator = try TestSupport.makeGenerator()
        let variant = try #require(generator.recipe.variants.first)
        let size = try await TestSupport.nativePixelSize()
        let pair = try await generator.generate(variant, size: size)

        let localIdentifier = try await PhotoLibraryBridge.save(pair)
        let asset = try PhotoLibraryBridge.fetchAsset(localIdentifier: localIdentifier)

        #expect(asset.mediaType == .image)
        #expect(asset.mediaSubtypes.contains(.photoLive))
        #expect(asset.playbackStyle == .livePhoto)
        #expect(asset.pixelWidth == size.width)
        #expect(asset.pixelHeight == size.height)

        let resourceTypes = Set(PHAssetResource.assetResources(for: asset).map(\.type))
        #expect(resourceTypes.contains(.photo))
        #expect(resourceTypes.contains(.pairedVideo))

        let livePhoto = try await PhotoLibraryBridge.requestLivePhoto(for: asset)
        #expect(livePhoto.size.width > 0)

        // What Photos stored, not what we wrote: export both resources back out.
        let directory = try TestSupport.temporaryDirectory("roundtrip")
        let exportedMovie = directory.appendingPathComponent("exported.MOV")
        let exportedStill = directory.appendingPathComponent("exported.HEIC")
        try await PhotoLibraryBridge.exportResource(.pairedVideo, of: asset, to: exportedMovie)
        try await PhotoLibraryBridge.exportResource(.photo, of: asset, to: exportedStill)

        let movie = try await LivePhotoInspector.inspectMovie(at: exportedMovie)
        #expect(movie.contentIdentifier == pair.contentIdentifier)
        #expect(movie.stillImageTime?.numberValue == generator.recipe.stillImageTimeTrack.value)
        if generator.recipe.stillImageTimeTrack.includeStillImageTransform {
            #expect(movie.timedItem(LivePhotoMetadata.stillImageTransformIdentifier) != nil)
        }
        #expect(movie.metadataTrackReferencesVideo == generator.recipe.stillImageTimeTrack.associateWithVideoTrack)
        let still = try LivePhotoInspector.inspectStill(at: exportedStill)
        #expect(still.contentIdentifier == pair.contentIdentifier)
    }

    @Test("Photos refuses to save a still and movie whose identifiers don't match")
    func mismatchedPairIsNotSaved() async throws {
        try TestSupport.requireReadWriteAccess()
        let generator = try TestSupport.makeGenerator()
        let variant = try #require(generator.recipe.variants.first)
        let size = PixelSize(width: 390, height: 844)
        let first = try await generator.generate(variant, size: size)
        let second = try await generator.generate(variant, size: size)
        let mismatched = LivePhotoPair(
            contentIdentifier: first.contentIdentifier, variant: variant, size: size,
            stillURL: first.stillURL, movieURL: second.movieURL,
            stillFrameIndex: first.stillFrameIndex, averageBitRate: first.averageBitRate)

        // Control: a matching pair at the same size saves.
        _ = try await PhotoLibraryBridge.save(first)
        await #expect(throws: PhotoLibraryError.self) {
            _ = try await PhotoLibraryBridge.save(mismatched)
        }
    }
}
