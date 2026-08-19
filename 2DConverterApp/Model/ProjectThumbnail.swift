import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The small copy of an import that the project lists draw.
enum ProjectThumbnail {

    /// 480 px on the long edge: twice the largest plate a card draws on the
    /// densest iPad, so it stays sharp without carrying a photograph.
    static let maxPixel = 480

    /// Built through ImageIO rather than `UIImage`, so a 12-megapixel import is
    /// never fully decoded to produce a square the size of a stamp.
    static func make(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
