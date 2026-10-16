import AVFoundation
import CoreMedia
import ImageIO
import UIKit

/// The metadata that links a still and a movie into one Live Photo.
///
/// - Still: the Apple maker-note dictionary carries the pair's content
///   identifier under key "17".
/// - Movie: a top-level QuickTime metadata item
///   `com.apple.quicktime.content.identifier` with the same identifier, and a
///   timed metadata track holding one `com.apple.quicktime.still-image-time`
///   sample at the time of the key photo. Optionally (recipe switches), the
///   sample also carries an identity still-image transform and its reference
///   dimensions, and the track references the video track, as camera files do.
///
/// Only public SDK identifiers are used, except the two keys the SDK has no
/// constant for (maker-note "17" and still-image-time), which are spelled out.
enum LivePhotoMetadata {
    /// Apple maker-note key that holds the Live Photo content identifier.
    static let makerAppleContentIdentifierKey = "17"
    /// No public constant exists; this is the identifier camera files use.
    static let stillImageTimeIdentifier = "mdta/com.apple.quicktime.still-image-time"
    static let stillImageTransformIdentifier =
        kCMMetadataIdentifier_QuickTimeMetadataLivePhotoStillImageTransform as String
    static let stillImageTransformReferenceDimensionsIdentifier =
        kCMMetadataIdentifier_QuickTimeMetadataLivePhotoStillImageTransformReferenceDimensions as String

    // MARK: Still

    static func stillImageProperties(contentIdentifier: String, compressionQuality: Double) -> [CFString: Any] {
        [
            kCGImagePropertyMakerAppleDictionary: [makerAppleContentIdentifierKey: contentIdentifier],
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
            kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue,
        ]
    }

    // MARK: Movie

    static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataContentIdentifier
        item.value = identifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    /// Every identifier and data type the timed metadata track will carry.
    private static func specifications(includeTransform: Bool) -> [(identifier: String, dataType: String)] {
        var specs = [(stillImageTimeIdentifier, kCMMetadataBaseDataType_SInt8 as String)]
        if includeTransform {
            specs.append((stillImageTransformIdentifier, kCMMetadataBaseDataType_PerspectiveTransformF64 as String))
            specs.append((stillImageTransformReferenceDimensionsIdentifier, kCMMetadataBaseDataType_DimensionsF32 as String))
        }
        return specs
    }

    static func stillImageTimeFormatDescription(includeTransform: Bool) throws -> CMFormatDescription {
        let specs: [[String: Any]] = specifications(includeTransform: includeTransform).map {
            [
                kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: $0.identifier,
                kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: $0.dataType,
            ]
        }
        var description: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: specs as CFArray,
            formatDescriptionOut: &description)
        guard status == noErr, let description else { throw LivePhotoWriteError.metadataFormatFailed(status) }
        return description
    }

    /// The single timed sample. `transformReferenceSize` adds the identity
    /// transform and its reference dimensions (the video size).
    static func stillImageTimeGroup(
        value: Int, at time: CMTime, duration: CMTime, transformReferenceSize: PixelSize?
    ) -> AVTimedMetadataGroup {
        let stillImageTime = AVMutableMetadataItem()
        stillImageTime.identifier = AVMetadataIdentifier(rawValue: stillImageTimeIdentifier)
        stillImageTime.value = NSNumber(value: Int8(clamping: value))
        stillImageTime.dataType = kCMMetadataBaseDataType_SInt8 as String
        var items: [AVMetadataItem] = [stillImageTime]

        if let size = transformReferenceSize {
            // Row-major 3x3 identity: the still is exactly the video frame.
            let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
            let transform = AVMutableMetadataItem()
            transform.identifier = AVMetadataIdentifier(rawValue: stillImageTransformIdentifier)
            transform.value = identity.map { NSNumber(value: $0) } as NSArray
            transform.dataType = kCMMetadataBaseDataType_PerspectiveTransformF64 as String

            let dimensions = AVMutableMetadataItem()
            dimensions.identifier = AVMetadataIdentifier(rawValue: stillImageTransformReferenceDimensionsIdentifier)
            dimensions.value = NSValue(cgSize: CGSize(width: size.width, height: size.height))
            dimensions.dataType = kCMMetadataBaseDataType_DimensionsF32 as String
            items += [transform, dimensions]
        }
        return AVTimedMetadataGroup(items: items, timeRange: CMTimeRange(start: time, duration: duration))
    }
}
