import Foundation
import UIKit

/// What the spike knows about the device and its screen.
struct DeviceInfo: Codable, Sendable, Equatable {
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool
    let nativePixelSize: PixelSize
    let nativeScale: Double

    /// Reads the screen from the given window scene. `UIScreen.main` is
    /// deprecated, so the scene is the source of truth.
    @MainActor
    static func current(in scene: UIWindowScene) -> DeviceInfo {
        let screen = scene.screen
        // nativeBounds is in pixels and always portrait-up.
        let native = screen.nativeBounds.size
        return DeviceInfo(
            modelIdentifier: modelIdentifier(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            isSimulator: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil,
            nativePixelSize: PixelSize(width: Int(native.width.rounded()), height: Int(native.height.rounded())),
            nativeScale: Double(screen.nativeScale))
    }

    /// The first foreground (or any) connected window scene.
    @MainActor
    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
