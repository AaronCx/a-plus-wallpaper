import CoreVideo
import Metal

/// Output size in pixels.
struct PixelSize: Sendable, Hashable, Codable, CustomStringConvertible {
    let width: Int
    let height: Int

    var description: String { "\(width)x\(height)" }
}

enum SpikeRenderError: Error, CustomStringConvertible {
    case noMetalDevice
    case noCommandQueue
    case shaderFunctionMissing(String)
    case textureCacheCreationFailed(CVReturn)
    case textureFromPixelBufferFailed(CVReturn)
    case commandEncodingFailed
    case gpuFailed(String)
    case pixelBufferCreationFailed(CVReturn)

    var description: String {
        switch self {
        case .noMetalDevice: "No Metal device is available."
        case .noCommandQueue: "Could not create a Metal command queue."
        case .shaderFunctionMissing(let name): "Shader function \(name) is missing from the default library."
        case .textureCacheCreationFailed(let status): "CVMetalTextureCacheCreate failed (\(status))."
        case .textureFromPixelBufferFailed(let status): "Could not wrap a pixel buffer as a Metal texture (\(status))."
        case .commandEncodingFailed: "Could not encode the compute pass."
        case .gpuFailed(let message): "The GPU pass failed: \(message)"
        case .pixelBufferCreationFailed(let status): "Could not create a pixel buffer (\(status))."
        }
    }
}

/// Renders the spike shader straight into `CVPixelBuffer`s through a Metal
/// texture cache, so frames go from the GPU into the buffers the video encoder
/// consumes without a CPU copy. The same code path renders the still and every
/// video frame, so the two cannot drift apart.
///
/// `@unchecked Sendable`: every stored property is immutable after `init`, and
/// Apple documents `MTLDevice`, `MTLCommandQueue`, `MTLComputePipelineState`
/// and `CVMetalTextureCache` as safe to use from multiple threads.
final class SpikeFrameRenderer: @unchecked Sendable {
    static let functionName = "spikeDrift"

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private let textureCache: CVMetalTextureCache

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw SpikeRenderError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw SpikeRenderError.noCommandQueue }
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: SpikeFrameRenderer.self))
        guard let function = library.makeFunction(name: Self.functionName) else {
            throw SpikeRenderError.shaderFunctionMissing(Self.functionName)
        }
        let pipeline = try device.makeComputePipelineState(function: function)

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else { throw SpikeRenderError.textureCacheCreationFailed(status) }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.textureCache = cache
    }

    /// Pixel buffer attributes every buffer we render into must have.
    static func pixelBufferAttributes(for size: PixelSize) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
    }

    /// A standalone buffer, used for the still image.
    static func makePixelBuffer(size: PixelSize) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA,
            pixelBufferAttributes(for: size) as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw SpikeRenderError.pixelBufferCreationFailed(status) }
        return buffer
    }

    /// Renders the frame at time `t` (seconds) into `pixelBuffer`, which must be
    /// 32BGRA and Metal-compatible. Returns once the GPU has finished.
    func render(seed: UInt32, t: Double, into pixelBuffer: CVPixelBuffer) async throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            throw SpikeRenderError.textureFromPixelBufferFailed(status)
        }

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SpikeRenderError.commandEncodingFailed
        }
        // Matches `SpikeUniforms` in SpikeDrift.metal: uint seed, float t, uint width, uint height.
        // Packed as 32-bit words so the layout is explicit.
        var uniforms: [UInt32] = [seed, Float(t).bitPattern, UInt32(width), UInt32(height)]
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&uniforms, length: uniforms.count * MemoryLayout<UInt32>.stride, index: 0)

        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / groupWidth)
        let threadsPerGroup = MTLSize(width: groupWidth, height: groupHeight, depth: 1)
        let groups = MTLSize(
            width: (width + groupWidth - 1) / groupWidth,
            height: (height + groupHeight - 1) / groupHeight,
            depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }
        if let error = commandBuffer.error {
            throw SpikeRenderError.gpuFailed(error.localizedDescription)
        }
        // The Metal texture borrows the pixel buffer's IOSurface; keep the
        // CoreVideo wrapper alive until the GPU is done with it.
        withExtendedLifetime(cvTexture) {}
    }
}
