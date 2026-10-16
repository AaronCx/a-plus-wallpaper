import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A generated still + movie pair on disk.
struct LivePhotoPair: Sendable {
    let contentIdentifier: String
    let variant: LivePhotoVariant
    let size: PixelSize
    let stillURL: URL
    let movieURL: URL
    let stillFrameIndex: Int
    let averageBitRate: Int

    var stillTimeSeconds: Double { Double(stillFrameIndex) / Double(variant.framesPerSecond) }

    /// Base file name shown in Photos' info panel, e.g. `APW-spike-2.0s-60fps-hevc`.
    var baseFileName: String { Self.baseFileName(for: variant) }

    static func baseFileName(for variant: LivePhotoVariant) -> String { "APW-spike-\(variant.id)" }
}

/// Renders the spike shader and writes a linked HEIC + MOV pair.
struct LivePhotoGenerator: Sendable {
    let renderer: SpikeFrameRenderer
    let recipe: LivePhotoRecipe

    init(renderer: SpikeFrameRenderer, recipe: LivePhotoRecipe) {
        self.renderer = renderer
        self.recipe = recipe
    }

    static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoSpike", isDirectory: true)
    }

    func averageBitRate(for variant: LivePhotoVariant, size: PixelSize) -> Int {
        // validate() guarantees a value for every variant's codec.
        let bitsPerPixel = recipe.bitsPerPixel(for: variant.codec) ?? 0
        return Int((bitsPerPixel * Double(size.width * size.height * variant.framesPerSecond)).rounded())
    }

    /// Generates the pair for `variant` at `size` (the screen's native pixels).
    func generate(
        _ variant: LivePhotoVariant,
        size: PixelSize,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> LivePhotoPair {
        let directory = Self.scratchDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let contentIdentifier = UUID().uuidString
        let baseName = LivePhotoPair.baseFileName(for: variant)
        let stillFrameIndex = recipe.stillFrameIndex(for: variant)
        let bitRate = averageBitRate(for: variant, size: size)
        let pair = LivePhotoPair(
            contentIdentifier: contentIdentifier,
            variant: variant,
            size: size,
            stillURL: directory.appendingPathComponent("\(baseName).HEIC"),
            movieURL: directory.appendingPathComponent("\(baseName).MOV"),
            stillFrameIndex: stillFrameIndex,
            averageBitRate: bitRate)
        let label = "a+wallpaper spike · \(variant.label)"

        // The still is the exact frame the movie shows at the still-image time.
        let stillBuffer = try SpikeFrameRenderer.makePixelBuffer(size: size)
        try await renderer.render(seed: recipe.seed, t: pair.stillTimeSeconds, into: stillBuffer)
        FrameLabel.draw(label, into: stillBuffer)
        try Self.writeHEIC(
            stillBuffer, to: pair.stillURL,
            properties: LivePhotoMetadata.stillImageProperties(
                contentIdentifier: contentIdentifier, compressionQuality: recipe.still.compressionQuality))

        let settings = LivePhotoMovieWriter.Settings(
            variant: variant,
            size: size,
            averageBitRate: bitRate,
            keyFrameInterval: max(1, Int((recipe.video.keyFrameIntervalSeconds * Double(variant.framesPerSecond)).rounded())),
            allowFrameReordering: recipe.video.allowFrameReordering,
            stillFrameIndex: stillFrameIndex,
            stillImageTimeValue: recipe.stillImageTimeTrack.value,
            stillImageTimeDurationTicks: recipe.stillImageTimeTrack.durationTicks,
            includeStillImageTransform: recipe.stillImageTimeTrack.includeStillImageTransform,
            associateMetadataWithVideo: recipe.stillImageTimeTrack.associateWithVideoTrack)
        let renderer = self.renderer
        let seed = recipe.seed
        try await LivePhotoMovieWriter.write(
            to: pair.movieURL,
            contentIdentifier: contentIdentifier,
            settings: settings,
            renderFrame: { index, buffer in
                try await renderer.render(seed: seed, t: Double(index) / Double(variant.framesPerSecond), into: buffer)
                FrameLabel.draw(label, into: buffer)
            },
            progress: progress)
        renderer.flushTextureCache()
        return pair
    }

    /// Renders one frame and returns it as a `CGImage` (used by tests and the debug preview).
    func renderImage(t: Double, size: PixelSize) async throws -> CGImage {
        let buffer = try SpikeFrameRenderer.makePixelBuffer(size: size)
        try await renderer.render(seed: recipe.seed, t: t, into: buffer)
        return try Self.makeImage(buffer)
    }

    static func makeImage(_ buffer: CVPixelBuffer) throws -> CGImage {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = context.makeImage()
        else { throw LivePhotoWriteError.stillEncodingFailed("could not wrap the pixel buffer as an image") }
        return image
    }

    static func writeHEIC(_ buffer: CVPixelBuffer, to url: URL, properties: [CFString: Any]) throws {
        let image = try makeImage(buffer)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw LivePhotoWriteError.stillEncodingFailed("HEIC is not available as an image destination")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoWriteError.stillEncodingFailed("CGImageDestinationFinalize returned false")
        }
    }
}
