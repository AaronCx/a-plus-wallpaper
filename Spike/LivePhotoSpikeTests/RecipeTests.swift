import Foundation
import Testing
@testable import LivePhotoSpike

@Suite("Variant recipe")
struct RecipeTests {
    @Test("The bundled recipe is the full 3 x 2 x 2 hardware matrix")
    func bundledRecipeIsTheFullMatrix() throws {
        let recipe = try LivePhotoRecipe.loadBundled()
        #expect(recipe.variants.count == 12)

        let combinations = Set(recipe.variants.map { "\($0.durationSeconds)|\($0.framesPerSecond)|\($0.codec.rawValue)" })
        var expected = Set<String>()
        for duration in [1.5, 2.0, 3.0] {
            for fps in [30, 60] {
                for codec in LivePhotoVariant.Codec.allCases {
                    expected.insert("\(duration)|\(fps)|\(codec.rawValue)")
                }
            }
        }
        #expect(combinations == expected)
    }

    @Test("Frame counts and the still frame follow from the recipe")
    func frameCountsAndStillFrame() throws {
        let recipe = try LivePhotoRecipe.loadBundled()
        for variant in recipe.variants {
            #expect(variant.frameCount == Int((variant.durationSeconds * Double(variant.framesPerSecond)).rounded()))
            let still = recipe.stillFrameIndex(for: variant)
            #expect((0..<variant.frameCount).contains(still), "\(variant.id)")
        }
    }

    @Test("Invalid recipes are rejected", arguments: [
        #"{"schemaVersion":2}"#,
        #"{"schemaVersion":1,"seed":1,"still":{"timeFraction":1.5,"compressionQuality":0.9},"video":{"bitsPerPixel":{"hevc":0.1},"keyFrameIntervalSeconds":1,"allowFrameReordering":false},"stillImageTimeTrack":{"value":0,"durationFrames":1,"includeStillImageTransform":true,"associateWithVideoTrack":true},"variants":[{"id":"a","durationSeconds":1,"framesPerSecond":30,"codec":"hevc"}]}"#,
        #"{"schemaVersion":1,"seed":1,"still":{"timeFraction":0.5,"compressionQuality":0.9},"video":{"bitsPerPixel":{"hevc":0.1},"keyFrameIntervalSeconds":1,"allowFrameReordering":false},"stillImageTimeTrack":{"value":0,"durationFrames":1,"includeStillImageTransform":true,"associateWithVideoTrack":true},"variants":[{"id":"a","durationSeconds":1,"framesPerSecond":30,"codec":"hevc"},{"id":"a","durationSeconds":2,"framesPerSecond":30,"codec":"hevc"}]}"#,
        #"{"schemaVersion":1,"seed":1,"still":{"timeFraction":0.5,"compressionQuality":0.9},"video":{"bitsPerPixel":{"hevc":0.1},"keyFrameIntervalSeconds":1,"allowFrameReordering":false},"stillImageTimeTrack":{"value":0,"durationFrames":1,"includeStillImageTransform":true,"associateWithVideoTrack":true},"variants":[{"id":"a","durationSeconds":1,"framesPerSecond":29,"codec":"hevc"}]}"#,
        #"{"schemaVersion":1,"seed":1,"still":{"timeFraction":0.5,"compressionQuality":0.9},"video":{"bitsPerPixel":{"hevc":0.1},"keyFrameIntervalSeconds":1,"allowFrameReordering":false},"stillImageTimeTrack":{"value":0,"durationFrames":1,"includeStillImageTransform":true,"associateWithVideoTrack":true},"variants":[{"id":"a","durationSeconds":1,"framesPerSecond":30,"codec":"h264"}]}"#,
        #"{"schemaVersion":1,"seed":1,"still":{"timeFraction":0.5,"compressionQuality":0.9},"video":{"bitsPerPixel":{"hevc":0.1},"keyFrameIntervalSeconds":1,"allowFrameReordering":false},"stillImageTimeTrack":{"value":300,"durationFrames":1,"includeStillImageTransform":true,"associateWithVideoTrack":true},"variants":[{"id":"a","durationSeconds":1,"framesPerSecond":30,"codec":"hevc"}]}"#,
    ])
    func invalidRecipesAreRejected(json: String) {
        #expect(throws: (any Error).self) {
            _ = try LivePhotoRecipe.decode(Data(json.utf8))
        }
    }
}
