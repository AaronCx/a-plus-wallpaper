import Foundation

/// One Live Photo variant from the hardware test matrix.
struct LivePhotoVariant: Codable, Sendable, Hashable, Identifiable {
    enum Codec: String, Codable, Sendable, CaseIterable {
        case hevc
        case h264

        var displayName: String {
            switch self {
            case .hevc: "HEVC"
            case .h264: "H.264"
            }
        }
    }

    let id: String
    let durationSeconds: Double
    let framesPerSecond: Int
    let codec: Codec

    var frameCount: Int { Int((durationSeconds * Double(framesPerSecond)).rounded()) }

    /// Short label burned into the frames and used in file names.
    var label: String {
        "\(String(format: "%.1f", durationSeconds))s · \(framesPerSecond) fps · \(codec.displayName)"
    }
}

/// Everything about how the spike writes a Live Photo, loaded from
/// `LivePhotoRecipe.json` so the parameters live in data, not code.
struct LivePhotoRecipe: Codable, Sendable {
    struct Still: Codable, Sendable {
        /// Position of the key photo inside the clip, 0...1.
        let timeFraction: Double
        /// HEIC lossy compression quality, 0...1.
        let compressionQuality: Double
    }

    struct Video: Codable, Sendable {
        /// Average bit rate = bitsPerPixel x width x height x fps.
        let bitsPerPixel: [String: Double]
        let keyFrameIntervalSeconds: Double
        let allowFrameReordering: Bool
    }

    struct StillImageTimeTrack: Codable, Sendable {
        /// Value stored in the `com.apple.quicktime.still-image-time` item.
        /// Camera files store -1; the time comes from the sample, not the value.
        let value: Int
        /// Duration of the timed metadata group, in frames of the variant.
        let durationFrames: Int
        /// Also write an identity `live-photo-still-image-transform` and its
        /// reference dimensions in the same sample, as camera files do.
        let includeStillImageTransform: Bool
        /// Link the metadata track to the video track (`tref cdsc`), as camera files do.
        let associateWithVideoTrack: Bool
    }

    let schemaVersion: Int
    let seed: UInt32
    let still: Still
    let video: Video
    let stillImageTimeTrack: StillImageTimeTrack
    let variants: [LivePhotoVariant]

    /// Nil when the recipe has no bit rate for the codec (rejected by `validate()`).
    func bitsPerPixel(for codec: LivePhotoVariant.Codec) -> Double? {
        video.bitsPerPixel[codec.rawValue]
    }

    /// Index of the frame used as the key photo for a variant.
    func stillFrameIndex(for variant: LivePhotoVariant) -> Int {
        let frames = variant.frameCount
        let index = Int((Double(frames) * still.timeFraction).rounded(.down))
        return min(max(index, 0), frames - 1)
    }

    enum LoadError: Error, CustomStringConvertible {
        case missingResource
        case invalid(String)

        var description: String {
            switch self {
            case .missingResource: "LivePhotoRecipe.json is missing from the app bundle."
            case .invalid(let reason): "LivePhotoRecipe.json is invalid: \(reason)"
            }
        }
    }

    static func loadBundled() throws -> LivePhotoRecipe {
        guard let url = Bundle(for: SpikeFrameRenderer.self).url(forResource: "LivePhotoRecipe", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> LivePhotoRecipe {
        let recipe = try JSONDecoder().decode(LivePhotoRecipe.self, from: data)
        try recipe.validate()
        return recipe
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw LoadError.invalid("unsupported schemaVersion \(schemaVersion)") }
        guard (0...1).contains(still.timeFraction) else { throw LoadError.invalid("still.timeFraction out of range") }
        guard (0...1).contains(still.compressionQuality) else { throw LoadError.invalid("still.compressionQuality out of range") }
        guard video.keyFrameIntervalSeconds > 0 else { throw LoadError.invalid("keyFrameIntervalSeconds must be positive") }
        guard stillImageTimeTrack.durationFrames >= 1 else { throw LoadError.invalid("stillImageTimeTrack.durationFrames must be >= 1") }
        guard Int(Int8.min)...Int(Int8.max) ~= stillImageTimeTrack.value else {
            throw LoadError.invalid("stillImageTimeTrack.value must fit in an Int8")
        }
        guard !variants.isEmpty else { throw LoadError.invalid("no variants") }
        guard Set(variants.map(\.id)).count == variants.count else { throw LoadError.invalid("duplicate variant ids") }
        for variant in variants {
            guard variant.durationSeconds > 0, variant.durationSeconds <= 10 else {
                throw LoadError.invalid("\(variant.id): duration out of range")
            }
            guard [24, 25, 30, 60].contains(variant.framesPerSecond) else {
                throw LoadError.invalid("\(variant.id): unsupported frame rate")
            }
            guard let bitsPerPixel = bitsPerPixel(for: variant.codec), bitsPerPixel > 0, bitsPerPixel < 1 else {
                throw LoadError.invalid("\(variant.id): no valid bit rate for \(variant.codec.rawValue)")
            }
        }
    }
}
