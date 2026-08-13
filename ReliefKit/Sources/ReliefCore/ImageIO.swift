import CoreGraphics
import Foundation
import ImageIO

/// Loading and previewing, using CoreGraphics so the same code serves the iPad
/// app and the macOS verification CLI.
public enum ReliefImage {

    /// Decode straight to the working resolution.
    ///
    /// `kCGImageSourceThumbnailMaxPixelSize` means the full-resolution bitmap
    /// is never resident — on a 4096 px painting that is the difference between
    /// 50 MB and 6 MB, and the memory budget on device has no room for the
    /// former alongside the depth model.
    public static func load(data: Data, maxEdge: Int) -> Plane? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary) else { return nil }
        return plane(from: image)
    }

    public static func plane(from image: CGImage) -> Plane? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var values = [Float](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            values[i * 3 + 0] = Float(bytes[i * 4 + 0]) / 255.0
            values[i * 3 + 1] = Float(bytes[i * 4 + 1]) / 255.0
            values[i * 3 + 2] = Float(bytes[i * 4 + 2]) / 255.0
        }
        return Plane(rows: h, cols: w, channels: 3, values: values)
    }

    /// Lambertian render of a height map under a raking light.
    ///
    /// Raking light is how relief legibility is actually judged by eye — a flat
    /// greyscale height map hides exactly the flatness problems that matter.
    public static func shade(_ height: Plane,
                             light: (Float, Float, Float) = (0.4, 0.5, 0.75),
                             zScale: Float = 40.0,
                             ambient: Float = 0.25) -> [Float] {
        let h = height.rows, w = height.cols
        let normalized = Volume.normalize01(height).values
        var out = [Float](repeating: 0, count: h * w)

        let mag = (light.0 * light.0 + light.1 * light.1 + light.2 * light.2).squareRoot()
        let lx = light.0 / mag, ly = light.1 / mag, lz = light.2 / mag

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let gx: Float = w > 1
                    ? (x == 0 ? normalized[i + 1] - normalized[i]
                     : x == w - 1 ? normalized[i] - normalized[i - 1]
                     : (normalized[i + 1] - normalized[i - 1]) / 2) * zScale
                    : 0
                let gy: Float = h > 1
                    ? (y == 0 ? normalized[i + w] - normalized[i]
                     : y == h - 1 ? normalized[i] - normalized[i - w]
                     : (normalized[i + w] - normalized[i - w]) / 2) * zScale
                    : 0
                let nx = -gx, ny = -gy, nz: Float = 1
                let n = (nx * nx + ny * ny + nz * nz).squareRoot() + 1e-9
                let lambert = Swift.max(0, Swift.min(1, (nx * lx + ny * ly + nz * lz) / n))
                out[i] = ambient + (1 - ambient) * lambert
            }
        }
        return out
    }

    /// 8-bit greyscale CGImage, for showing a height map or a shaded preview.
    public static func grayImage(_ values: [Float], rows: Int, cols: Int) -> CGImage? {
        var bytes = values.map { UInt8(Swift.max(0, Swift.min(1, $0)) * 255) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: cols, height: rows, bitsPerComponent: 8,
                       bitsPerPixel: 8, bytesPerRow: cols,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}
