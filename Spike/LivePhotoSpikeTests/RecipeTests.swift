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

    /// A complete, valid recipe; each invalid case below changes one thing.
    static let validRecipe = #"""
    {"schemaVersion":1,"seed":1,"still":{"timeFraction":0.5,"compressionQuality":0.9},
     "video":{"bitsPerPixel":{"hevc":0.1,"h264":0.1},"keyFrameIntervalSeconds":1,"allowFrameReordering":false},
     "stillImageTimeTrack":{"value":-1,"durationTicks":1,"includeStillImageTransform":true,"associateWithVideoTrack":true},
     "variants":[{"id":"a","durationSeconds":1,"framesPerSecond":30,"codec":"hevc"}]}
    """#

    enum InvalidCase: String, CaseIterable, Sendable {
        case schemaVersion2, stillTimeOutOfRange, duplicateVariantIDs, unsupportedFrameRate,
             noBitRateForCodec, stillImageTimeValueTooBig, zeroTicks, tooManyTicks

        func apply(to recipe: inout [String: Any]) {
            var variants = recipe["variants"] as! [[String: Any]]
            var still = recipe["still"] as! [String: Any]
            var video = recipe["video"] as! [String: Any]
            var track = recipe["stillImageTimeTrack"] as! [String: Any]
            switch self {
            case .schemaVersion2: recipe["schemaVersion"] = 2
            case .stillTimeOutOfRange: still["timeFraction"] = 1.5
            case .duplicateVariantIDs: variants.append(variants[0])
            case .unsupportedFrameRate: variants[0]["framesPerSecond"] = 29
            case .noBitRateForCodec: video["bitsPerPixel"] = ["h264": 0.1]
            case .stillImageTimeValueTooBig: track["value"] = 300
            case .zeroTicks: track["durationTicks"] = 0
            case .tooManyTicks: track["durationTicks"] = 601
            }
            recipe["variants"] = variants
            recipe["still"] = still
            recipe["video"] = video
            recipe["stillImageTimeTrack"] = track
        }
    }

    @Test("The valid fixture decodes (control for the invalid cases)")
    func validFixtureDecodes() throws {
        _ = try LivePhotoRecipe.decode(Data(Self.validRecipe.utf8))
    }

    @Test("Invalid recipes fail validation", arguments: InvalidCase.allCases)
    func invalidRecipesAreRejected(invalid: InvalidCase) throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(Self.validRecipe.utf8)) as? [String: Any])
        invalid.apply(to: &object)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: LivePhotoRecipe.LoadError.self) {
            _ = try LivePhotoRecipe.decode(data)
        }
    }
}
