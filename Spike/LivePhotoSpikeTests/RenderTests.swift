import CoreGraphics
import Testing
import UIKit
@testable import LivePhotoSpike

@Suite("Offscreen rendering")
struct RenderTests {
    @Test("Renders at the screen's native pixel size")
    func rendersAtNativeSize() async throws {
        let size = try await TestSupport.nativePixelSize()
        let image = try await TestSupport.makeGenerator().renderImage(t: 0.75, size: size)
        #expect(image.width == size.width)
        #expect(image.height == size.height)
        #expect(try TestSupport.lumaStandardDeviation(image) > 4, "the frame should not be a flat colour")
    }

    @Test("The export size is the screen's native pixels, not points")
    @MainActor
    func exportSizeIsNativePixels() async throws {
        let size = try await TestSupport.nativePixelSize()
        let screen = try #require(DeviceInfo.activeWindowScene()).screen
        // Read the screen directly, and derive it a second way from points x scale.
        #expect(size.width == Int(screen.nativeBounds.width.rounded()))
        #expect(size.height == Int(screen.nativeBounds.height.rounded()))
        let fromPoints = [screen.bounds.width, screen.bounds.height].map { Int(($0 * screen.nativeScale).rounded()) }.sorted()
        #expect(fromPoints == [size.width, size.height].sorted())
        #expect(size.width > Int(screen.bounds.width.rounded()) || screen.nativeScale == 1, "pixels, not points")
    }

    @Test("Same seed and time give identical pixels on the same device")
    func deterministicOnOneDevice() async throws {
        let generator = try TestSupport.makeGenerator()
        let size = PixelSize(width: 390, height: 844)
        let first = try await generator.renderImage(t: 1.25, size: size)
        let second = try await generator.renderImage(t: 1.25, size: size)
        #expect(try TestSupport.rgbaBytes(first) == TestSupport.rgbaBytes(second))
    }

    @Test("Frames change over time, so there is motion to show")
    func framesChangeOverTime() async throws {
        let generator = try TestSupport.makeGenerator()
        let size = PixelSize(width: 390, height: 844)
        let start = try await generator.renderImage(t: 0, size: size)
        let end = try await generator.renderImage(t: 1.5, size: size)
        #expect(try TestSupport.meanAbsoluteDifference(start, end) > 3)
    }
}
