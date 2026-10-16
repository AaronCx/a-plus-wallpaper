import AVFoundation
import CoreMedia
import Foundation
import ImageIO

/// Reads back what actually ended up in a still or a movie file, independent of
/// the code that wrote it. Used by the tests and by the parameter report.
enum LivePhotoInspector {
    struct Still: Codable, Sendable, Equatable {
        let typeIdentifier: String?
        let width: Int?
        let height: Int?
        let contentIdentifier: String?
        let fileBytes: Int
    }

    struct TimedItem: Codable, Sendable, Equatable {
        let identifier: String?
        let dataType: String?
        let numberValue: Int?
        /// Non-numeric values (transform matrix, dimensions), as text.
        let valueDescription: String?
        let startSeconds: Double
        let durationSeconds: Double
    }

    struct Movie: Codable, Sendable, Equatable {
        let durationSeconds: Double
        let videoCodec: String?
        let width: Int?
        let height: Int?
        let nominalFrameRate: Double?
        let videoSampleCount: Int
        let estimatedDataRate: Double?
        let contentIdentifier: String?
        let metadataTrackCount: Int
        /// True when a metadata track references the video track (`tref cdsc`).
        let metadataTrackReferencesVideo: Bool
        let timedMetadata: [TimedItem]
        let fileBytes: Int

        var stillImageTime: TimedItem? { timedItem(LivePhotoMetadata.stillImageTimeIdentifier) }

        func timedItem(_ identifier: String) -> TimedItem? {
            timedMetadata.first { $0.identifier == identifier }
        }
    }

    enum InspectionError: Error, CustomStringConvertible {
        case unreadableImage(URL)

        var description: String {
            switch self {
            case .unreadableImage(let url): "ImageIO cannot read \(url.lastPathComponent)."
            }
        }
    }

    static func inspectStill(at url: URL) throws -> Still {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw InspectionError.unreadableImage(url) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        return Still(
            typeIdentifier: CGImageSourceGetType(source) as String?,
            width: properties[kCGImagePropertyPixelWidth] as? Int,
            height: properties[kCGImagePropertyPixelHeight] as? Int,
            contentIdentifier: makerApple?[LivePhotoMetadata.makerAppleContentIdentifierKey] as? String,
            fileBytes: fileSize(url))
    }

    static func inspectMovie(at url: URL) async throws -> Movie {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)

        var codec: String?
        var width: Int?
        var height: Int?
        var frameRate: Double?
        var dataRate: Double?
        var sampleCount = 0
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        if let video = videoTrack {
            let (size, rate, formats, estimatedRate) = try await video.load(
                .naturalSize, .nominalFrameRate, .formatDescriptions, .estimatedDataRate)
            width = Int(size.width.rounded())
            height = Int(size.height.rounded())
            frameRate = Double(rate)
            dataRate = Double(estimatedRate)
            codec = formats.first.map { fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) }
            sampleCount = try countSamples(of: video, in: asset)
        }

        let topLevel = try await asset.load(.metadata)
        let identifierItems = AVMetadataItem.metadataItems(
            from: topLevel, filteredByIdentifier: .quickTimeMetadataContentIdentifier)
        var contentIdentifier: String?
        if let item = identifierItems.first {
            contentIdentifier = try await item.load(.stringValue)
        }

        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        var timed: [TimedItem] = []
        var referencesVideo = false
        for track in metadataTracks {
            timed += try await readTimedMetadata(of: track, in: asset)
            let referents = try await track.loadAssociatedTracks(ofType: .metadataReferent)
            if let videoTrack, referents.contains(where: { $0.trackID == videoTrack.trackID }) {
                referencesVideo = true
            }
        }

        return Movie(
            durationSeconds: duration.seconds,
            videoCodec: codec,
            width: width,
            height: height,
            nominalFrameRate: frameRate,
            videoSampleCount: sampleCount,
            estimatedDataRate: dataRate,
            contentIdentifier: contentIdentifier,
            metadataTrackCount: metadataTracks.count,
            metadataTrackReferencesVideo: referencesVideo,
            timedMetadata: timed,
            fileBytes: fileSize(url))
    }

    private static func countSamples(of track: AVAssetTrack, in asset: AVAsset) throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return 0 }
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            count += CMSampleBufferGetNumSamples(sample)
        }
        return count
    }

    private static func readTimedMetadata(of track: AVAssetTrack, in asset: AVAsset) async throws -> [TimedItem] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        reader.add(output)
        guard reader.startReading() else { return [] }
        var groups: [AVTimedMetadataGroup] = []
        while let group = adaptor.nextTimedMetadataGroup() {
            groups.append(group)
        }
        var items: [TimedItem] = []
        for group in groups {
            for item in group.items {
                let number = try await item.load(.numberValue)
                let value = try await item.load(.value)
                items.append(TimedItem(
                    identifier: item.identifier?.rawValue,
                    dataType: item.dataType,
                    numberValue: number?.intValue,
                    valueDescription: number == nil ? value.map { String(describing: $0) } : nil,
                    startSeconds: group.timeRange.start.seconds,
                    durationSeconds: group.timeRange.duration.seconds))
            }
        }
        return items
    }

    static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
