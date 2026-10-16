import Foundation
import Photos
import Testing
@testable import LivePhotoSpike

/// Phase 0 DoD: every hardware-test variant saves on the simulator and reads
/// back as a Live Photo. Writes one JSON report per variant (the exact
/// parameters that end up in docs/DECISIONS.md).
@Suite("Variant matrix", .serialized)
struct VariantMatrixTests {
    /// Loaded from the bundled recipe. RecipeTests separately asserts there are
    /// exactly 12, so an empty list here cannot pass silently.
    static let variantIDs: [String] = (try? LivePhotoRecipe.loadBundled().variants.map(\.id)) ?? []

    struct Report: Codable {
        struct Library: Codable {
            let isLivePhoto: Bool
            let resourceTypes: [Int]
            let livePhotoLoaded: Bool
            let pixelWidth: Int
            let pixelHeight: Int
            let storedStill: LivePhotoInspector.Still
            let storedMovie: LivePhotoInspector.Movie
        }

        let variantID: String
        let durationSeconds: Double
        let framesPerSecond: Int
        let codec: String
        let frameCount: Int
        let stillFrameIndex: Int
        let stillTimeSeconds: Double
        let targetAverageBitRate: Int
        let keyFrameIntervalFrames: Int
        let device: DeviceInfo
        let generationSeconds: Double
        let writtenStill: LivePhotoInspector.Still
        let writtenMovie: LivePhotoInspector.Movie
        let library: Library
    }

    @Test("Every variant saves to Photos and reads back as a Live Photo", arguments: variantIDs)
    func variantSavesAndLoads(variantID: String) async throws {
        try TestSupport.requireReadWriteAccess()
        let generator = try TestSupport.makeGenerator()
        let variant = try #require(generator.recipe.variants.first { $0.id == variantID })
        let device = try await TestSupport.deviceInfo()

        let clock = ContinuousClock()
        let started = clock.now
        let pair = try await generator.generate(variant, size: device.nativePixelSize)
        let generationTime = started.duration(to: clock.now)

        _ = try await PhotoLibraryBridge.loadLivePhoto(from: pair)
        let writtenStill = try LivePhotoInspector.inspectStill(at: pair.stillURL)
        let writtenMovie = try await LivePhotoInspector.inspectMovie(at: pair.movieURL)

        let localIdentifier = try await PhotoLibraryBridge.save(pair)
        let asset = try PhotoLibraryBridge.fetchAsset(localIdentifier: localIdentifier)
        let isLive = asset.mediaSubtypes.contains(.photoLive)
        #expect(isLive, "\(variant.id) was not stored as a Live Photo")
        let livePhoto = try await PhotoLibraryBridge.requestLivePhoto(for: asset)

        let directory = try TestSupport.temporaryDirectory(variant.id)
        let storedMovieURL = directory.appendingPathComponent("stored.MOV")
        let storedStillURL = directory.appendingPathComponent("stored.HEIC")
        try await PhotoLibraryBridge.exportResource(.pairedVideo, of: asset, to: storedMovieURL)
        try await PhotoLibraryBridge.exportResource(.photo, of: asset, to: storedStillURL)
        let storedMovie = try await LivePhotoInspector.inspectMovie(at: storedMovieURL)
        let storedStill = try LivePhotoInspector.inspectStill(at: storedStillURL)

        #expect(storedMovie.contentIdentifier == pair.contentIdentifier)
        #expect(storedStill.contentIdentifier == pair.contentIdentifier)
        #expect(storedMovie.stillImageTime != nil)
        #expect(storedMovie.videoSampleCount == variant.frameCount)

        let report = Report(
            variantID: variant.id,
            durationSeconds: variant.durationSeconds,
            framesPerSecond: variant.framesPerSecond,
            codec: variant.codec.rawValue,
            frameCount: variant.frameCount,
            stillFrameIndex: pair.stillFrameIndex,
            stillTimeSeconds: pair.stillTimeSeconds,
            targetAverageBitRate: pair.averageBitRate,
            keyFrameIntervalFrames: max(1, Int((generator.recipe.video.keyFrameIntervalSeconds * Double(variant.framesPerSecond)).rounded())),
            device: device,
            generationSeconds: Double(generationTime.components.seconds) + Double(generationTime.components.attoseconds) / 1e18,
            writtenStill: writtenStill,
            writtenMovie: writtenMovie,
            library: .init(
                isLivePhoto: isLive,
                resourceTypes: PHAssetResource.assetResources(for: asset).map(\.type.rawValue).sorted(),
                livePhotoLoaded: livePhoto.size.width > 0,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                storedStill: storedStill,
                storedMovie: storedMovie))
        try Self.write(report)
    }

    /// Saved to the host app's Documents/variant-reports (fetched with
    /// `xcrun simctl get_app_container`) and echoed to the log.
    private static func write(_ report: Report) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent("variant-reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(report.variantID).json"), options: .atomic)
        print("APW-VARIANT-REPORT \(String(decoding: data, as: UTF8.self))")
    }
}
