import Foundation
import Photos
import Testing
import UIKit
@testable import LivePhotoSpike

enum TestSupport {
    static let bundleIdentifier = "com.aaroncx.apluswallpaper.spike"

    /// The host app's screen size in native pixels, read from its window scene.
    @MainActor
    static func nativePixelSize() async throws -> PixelSize {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while clock.now < deadline {
            if let scene = DeviceInfo.activeWindowScene() {
                return DeviceInfo.current(in: scene).nativePixelSize
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("The test host never connected a window scene.")
        throw CancellationError()
    }

    @MainActor
    static func deviceInfo() async throws -> DeviceInfo {
        _ = try await nativePixelSize()
        let scene = try #require(DeviceInfo.activeWindowScene())
        return DeviceInfo.current(in: scene)
    }

    static func makeGenerator() throws -> LivePhotoGenerator {
        LivePhotoGenerator(renderer: try SpikeFrameRenderer(), recipe: try LivePhotoRecipe.loadBundled())
    }

    /// Fails (never skips) when the simulator has not been granted access.
    /// Never requests access: an unanswered prompt in a unit test can leave
    /// the simulator's grant set to "denied" for later runs.
    static func requireReadWriteAccess() throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        try #require(
            status == .authorized,
            """
            Photos read/write access is \(status.debugName). Run the tests through \
            scripts/spike-test.sh, which installs the app and grants access first.
            """)
    }

    static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePhotoSpikeTests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Mean absolute difference per channel (0...255) between two same-sized images.
    static func meanAbsoluteDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let pixelsA = try rgbaBytes(a)
        let pixelsB = try rgbaBytes(b)
        try #require(pixelsA.count == pixelsB.count)
        var total = 0
        for index in pixelsA.indices where index % 4 != 3 {
            total += abs(Int(pixelsA[index]) - Int(pixelsB[index]))
        }
        return Double(total) / Double(pixelsA.count / 4 * 3)
    }

    /// Standard deviation of luma (0...255), a cheap "is this not a flat colour" check.
    static func lumaStandardDeviation(_ image: CGImage) throws -> Double {
        let pixels = try rgbaBytes(image)
        var values: [Double] = []
        values.reserveCapacity(pixels.count / 4)
        var index = 0
        while index < pixels.count {
            values.append(0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2]))
            index += 4
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }

    static func rgbaBytes(_ image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return bytes
    }
}
