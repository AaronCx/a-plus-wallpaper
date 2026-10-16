import Foundation
import os
import Photos

enum PhotoLibraryError: Error, CustomStringConvertible {
    case notAuthorized(PHAuthorizationStatus, PHAccessLevel)
    case saveFailed(String)
    case assetNotFound(String)
    case notALivePhoto(String)
    case livePhotoLoadFailed(String)
    case resourceMissing(String)

    var description: String {
        switch self {
        case .notAuthorized(let status, let level):
            "Photos access (\(level == .addOnly ? "add only" : "read and write")) is \(status.debugName)."
        case .saveFailed(let message): "Saving to Photos failed: \(message)"
        case .assetNotFound(let id): "No asset with identifier \(id)."
        case .notALivePhoto(let detail): "The saved asset is not a Live Photo: \(detail)"
        case .livePhotoLoadFailed(let message): "Could not load a PHLivePhoto: \(message)"
        case .resourceMissing(let type): "The asset has no \(type) resource."
        }
    }
}

extension PHAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        case .limited: "limited"
        @unknown default: "unknown (\(rawValue))"
        }
    }
}

/// Saving, reading back and checking Live Photos in the system library.
enum PhotoLibraryBridge {
    /// Saves the pair as one Live Photo asset and returns its local identifier.
    static func save(_ pair: LivePhotoPair) async throws -> String {
        let placeholderIdentifier = OSAllocatedUnfairLock<String?>(initialState: nil)
        let stillURL = pair.stillURL
        let movieURL = pair.movieURL
        let baseName = pair.baseFileName
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.originalFilename = "\(baseName).HEIC"
                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.originalFilename = "\(baseName).MOV"
                request.addResource(with: .photo, fileURL: stillURL, options: photoOptions)
                request.addResource(with: .pairedVideo, fileURL: movieURL, options: videoOptions)
                let identifier = request.placeholderForCreatedAsset?.localIdentifier
                placeholderIdentifier.withLock { $0 = identifier }
            }
        } catch {
            throw PhotoLibraryError.saveFailed(String(describing: error))
        }
        guard let identifier = placeholderIdentifier.withLock({ $0 }) else {
            throw PhotoLibraryError.saveFailed("no placeholder identifier was returned")
        }
        return identifier
    }

    static func fetchAsset(localIdentifier: String) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            throw PhotoLibraryError.assetNotFound(localIdentifier)
        }
        return asset
    }

    /// Loads the library asset as a `PHLivePhoto` (full quality, local only).
    static func requestLivePhoto(for asset: PHAsset) async throws -> PHLivePhoto {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            PHImageManager.default().requestLivePhoto(
                for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options
            ) { livePhoto, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let errorText = (info?[PHImageErrorKey] as? Error).map { String(describing: $0) }
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if degraded && livePhoto != nil && errorText == nil { return }
                guard resumed.withLock({ wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }) else { return }
                if let livePhoto {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.livePhotoLoadFailed(
                        errorText ?? (cancelled ? "cancelled" : "no live photo and no error")))
                }
            }
        }
    }

    /// Builds a `PHLivePhoto` straight from the files, without the library.
    /// This is Photos' own pairing check.
    static func loadLivePhoto(from pair: LivePhotoPair) async throws -> PHLivePhoto {
        let urls = [pair.stillURL, pair.movieURL]
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            _ = PHLivePhoto.request(
                withResourceFileURLs: urls, placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit
            ) { livePhoto, info in
                let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                let errorText = (info[PHLivePhotoInfoErrorKey] as? Error).map { String(describing: $0) }
                let cancelled = (info[PHLivePhotoInfoCancelledKey] as? Bool) ?? false
                if degraded && errorText == nil && !cancelled { return }
                guard resumed.withLock({ wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }) else { return }
                if let livePhoto, errorText == nil {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.livePhotoLoadFailed(
                        errorText ?? (cancelled ? "cancelled" : "no live photo and no error")))
                }
            }
        }
    }

    /// Copies one of the asset's stored resources back out to a file.
    static func exportResource(_ type: PHAssetResourceType, of asset: PHAsset, to url: URL) async throws {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == type }) else {
            throw PhotoLibraryError.resourceMissing(type == .pairedVideo ? "paired video" : "photo")
        }
        try? FileManager.default.removeItem(at: url)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
    }
}
