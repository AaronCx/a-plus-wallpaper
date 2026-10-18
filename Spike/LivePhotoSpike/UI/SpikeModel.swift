import Foundation
import Observation
import Photos
import UIKit

/// State for the debug screen: generates each variant, saves it to Photos and,
/// when read access has been granted, checks Photos stored it as a Live Photo.
@MainActor
@Observable
final class SpikeModel {
    enum VariantStatus: Equatable {
        case idle
        case rendering(Double)
        case saving
        case saved(localIdentifier: String, isLive: Bool?)
        case failed(String)
    }

    private(set) var recipe: LivePhotoRecipe?
    private(set) var deviceInfo: DeviceInfo?
    private(set) var statuses: [String: VariantStatus] = [:]
    private(set) var preview: PHLivePhoto?
    private(set) var previewVariantLabel: String?
    private(set) var isBusy = false
    private(set) var setupError: String?
    private(set) var verifyError: String?

    @ObservationIgnored private var generator: LivePhotoGenerator?
    @ObservationIgnored private var previewDirectory: URL?

    var variants: [LivePhotoVariant] { recipe?.variants ?? [] }

    func status(of variant: LivePhotoVariant) -> VariantStatus { statuses[variant.id] ?? .idle }

    /// Loads the recipe and Metal; reads the screen from the window scene.
    func start() {
        guard generator == nil else { return }
        if let scene = DeviceInfo.activeWindowScene() {
            deviceInfo = DeviceInfo.current(in: scene)
        }
        do {
            let recipe = try LivePhotoRecipe.loadBundled()
            self.recipe = recipe
            generator = LivePhotoGenerator(renderer: try SpikeFrameRenderer(), recipe: recipe)
        } catch {
            setupError = String(describing: error)
        }
        // Leftovers from a previous launch; Photos keeps its own copies. Once
        // per process: on iPad every window has its own model, and a second
        // window must not delete files the first one is still writing.
        if !Self.isRunningTests && !Self.didClearScratch {
            Self.didClearScratch = true
            try? FileManager.default.removeItem(at: LivePhotoGenerator.scratchDirectory())
        }
    }

    func saveAll() async {
        for variant in variants {
            await save(variant)
        }
    }

    func save(_ variant: LivePhotoVariant) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await saveThrowing(variant)
        } catch {
            statuses[variant.id] = .failed(String(describing: error))
        }
    }

    /// Requests read access (once) and re-checks every saved variant.
    func verifySaved() async {
        verifyError = nil
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            verifyError = PhotoLibraryError.notAuthorized(status, .readWrite).description
            return
        }
        for (id, state) in statuses {
            if case .saved(let localIdentifier, _) = state {
                switch Self.libraryCheck(localIdentifier) {
                case .live: statuses[id] = .saved(localIdentifier: localIdentifier, isLive: true)
                case .notLive: statuses[id] = .saved(localIdentifier: localIdentifier, isLive: false)
                case .notFound: statuses[id] = .failed("Saved earlier, but no longer in Photos.")
                }
            }
        }
    }

    private func saveThrowing(_ variant: LivePhotoVariant) async throws {
        guard let generator else { throw PhotoLibraryError.saveFailed(setupError ?? "the renderer is not ready") }
        if deviceInfo == nil, let scene = DeviceInfo.activeWindowScene() {
            deviceInfo = DeviceInfo.current(in: scene)
        }
        guard let size = deviceInfo?.nativePixelSize else {
            throw PhotoLibraryError.saveFailed("no window scene to read the screen size from")
        }

        let addStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard addStatus == .authorized || addStatus == .limited else {
            throw PhotoLibraryError.notAuthorized(addStatus, .addOnly)
        }

        statuses[variant.id] = .rendering(0)
        let pair = try await generator.generate(variant, size: size) { fraction in
            Task { @MainActor [weak self] in
                if case .rendering = self?.statuses[variant.id] {
                    self?.statuses[variant.id] = .rendering(fraction)
                }
            }
        }

        statuses[variant.id] = .saving
        // Photos' own pairing check, and the in-app preview.
        let livePhoto = try await PhotoLibraryBridge.loadLivePhoto(from: pair)
        let localIdentifier = try await PhotoLibraryBridge.save(pair)
        replacePreview(with: livePhoto, label: variant.label, directory: pair.stillURL.deletingLastPathComponent())

        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        var isLive: Bool?
        if readStatus == .authorized || readStatus == .limited {
            switch Self.libraryCheck(localIdentifier) {
            case .live: isLive = true
            case .notLive: isLive = false
            case .notFound: isLive = nil
            }
        }
        statuses[variant.id] = .saved(localIdentifier: localIdentifier, isLive: isLive)
    }

    private func replacePreview(with livePhoto: PHLivePhoto, label: String, directory: URL) {
        if let previewDirectory, previewDirectory != directory {
            try? FileManager.default.removeItem(at: previewDirectory)
        }
        preview = livePhoto
        previewVariantLabel = label
        previewDirectory = directory
    }

    private enum LibraryCheck {
        case live, notLive, notFound
    }

    private static func libraryCheck(_ localIdentifier: String) -> LibraryCheck {
        guard let asset = try? PhotoLibraryBridge.fetchAsset(localIdentifier: localIdentifier) else { return .notFound }
        return asset.mediaSubtypes.contains(.photoLive) ? .live : .notLive
    }

    private static var didClearScratch = false

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
