import SwiftUI

/// Phase 0 throwaway spike: can iOS use a Live Photo we generate on the device
/// as a moving Lock Screen wallpaper? See docs/BRIEF.md, Phase 0.
@main
struct LivePhotoSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeDebugView()
        }
    }
}
