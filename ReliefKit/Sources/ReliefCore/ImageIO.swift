import CoreGraphics
import Foundation
import ImageIO
import ReliefNumerics

/// Loading and previewing, using CoreGraphics so the same code serves the iPad
/// app and the macOS verification CLI.
public enum ReliefImage {

    /// Load an image as float32 RGB in [0, 1], EXIF-oriented, with the longest
    /// edge scaled to `maxEdge` — matching `io_utils.load_image`.
    ///
    /// An earlier version decoded straight to size via
    /// `kCGImageSourceThumbnailMaxPixelSize`, which keeps the full-resolution
    /// bitmap out of memory. That was measurably wrong: CoreGraphics' thumbnail
    /// resampler differs from PIL's LANCZOS by **1.6% mean and 18% max** on a
    /// real painting. Every pipeline stage is held to 1e-6, so a 1.6% error in
    /// the *input* dominates everything downstream — it lands in the relief as
    /// high-frequency spikes, because the aliasing it introduces is exactly
    /// what Z_detail is built to amplify.
    ///
    /// So: decode at full size, then resize with the reference's own filter.
    /// The transient cost is the full bitmap (~50 MB on a 4096 px image), which
    /// is small next to the depth model and is released immediately.
    public static func load(data: Data, maxEdge: Int) -> Plane? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        // Honour EXIF orientation, as `ImageOps.exif_transpose` does.
        let image = orientedImage(decoded, source: source) ?? decoded
        guard var rgb = bytes(from: image) else { return nil }

        let w = image.width, h = image.height
        guard max(w, h) > maxEdge else {
            return plane(from: image)
        }

        // `scale = max_edge / max(size)`, then round each axis.
        let scale = Double(maxEdge) / Double(max(w, h))
        let outW = max(1, Int((Double(w) * scale).rounded()))
        let outH = max(1, Int((Double(h) * scale).rounded()))

        var values = [Float](repeating: 0, count: outW * outH * 3)
        rgb.withUnsafeBufferPointer { src in
            values.withUnsafeMutableBufferPointer { dst in
                relief_pil_lanczos_rgb(src.baseAddress!, h, w,
                                       Int32(outH), Int32(outW), dst.baseAddress!)
            }
        }
        rgb = []
        return Plane(rows: outH, cols: outW, channels: 3, values: values)
    }

    /// Tightly packed 8-bit RGB, dropping alpha.
    ///
    /// Drawn into the image's **own** colour space, not DeviceRGB.
    ///
    /// This matters more than it looks. PIL ignores embedded ICC profiles and
    /// hands back raw decoded samples; CoreGraphics honours them and converts.
    /// The sample painting carries a Display P3 profile, so drawing into
    /// DeviceRGB silently gamut-mapped every pixel — 1.5% mean and 18% max
    /// against the reference, with saturated colours moving furthest.
    ///
    /// That error enters at stage 0 and compounds: CIELAB shifts, so the CIE76
    /// merge picks different regions, so the albedo divide uses different
    /// means, and the depth model sees a different picture. Matching the
    /// reference means reading the samples as PIL does — untouched.
    private static func bytes(from image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3 + 0] = rgba[i * 4 + 0]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return rgb
    }

    /// Apply the EXIF orientation the file declares.
    private static func orientedImage(_ image: CGImage,
                                      source: CGImageSource) -> CGImage? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let raw = props[kCGImagePropertyOrientation] as? UInt32,
              raw != 1 else { return image }

        // Orientations 5-8 swap the axes.
        let swaps = raw >= 5
        let w = swaps ? image.height : image.width
        let h = swaps ? image.width : image.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }

        switch raw {
        case 2: ctx.translateBy(x: CGFloat(w), y: 0); ctx.scaleBy(x: -1, y: 1)
        case 3: ctx.translateBy(x: CGFloat(w), y: CGFloat(h)); ctx.rotate(by: .pi)
        case 4: ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        case 5: ctx.rotate(by: -.pi/2); ctx.scaleBy(x: -1, y: 1)
        case 6: ctx.translateBy(x: 0, y: CGFloat(h)); ctx.rotate(by: -.pi/2)
        case 7: ctx.translateBy(x: CGFloat(w), y: CGFloat(h)); ctx.rotate(by: .pi/2); ctx.scaleBy(x: -1, y: 1)
        case 8: ctx.translateBy(x: CGFloat(w), y: 0); ctx.rotate(by: .pi/2)
        default: break
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0,
                                   width: CGFloat(swaps ? h : w),
                                   height: CGFloat(swaps ? w : h)))
        return ctx.makeImage() ?? image
    }

    public static func plane(from image: CGImage) -> Plane? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        // Same reasoning as `bytes(from:)`: the image's own space, so no
        // gamut conversion happens behind our back.
        guard let ctx = CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
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

public extension ReliefImage {

    /// 16-bit grayscale PNG, matching the reference's `height16.png`.
    ///
    /// Sixteen bits rather than eight is the whole point of writing this file:
    /// 256 levels across an 8 mm relief is a 31 µm step, coarse enough to show
    /// as terracing when the map is re-imported and raised again.
    static func gray16PNG(_ samples: [UInt16], rows: Int, cols: Int) -> Data? {
        guard samples.count == rows * cols else { return nil }

        // PNG is big-endian; the samples arrive in host order.
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count * 2)
        for value in samples {
            bytes.append(UInt8(value >> 8))
            bytes.append(UInt8(value & 0xFF))
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.linearGray),
              let image = CGImage(width: cols,
                                  height: rows,
                                  bitsPerComponent: 16,
                                  bitsPerPixel: 16,
                                  bytesPerRow: cols * 2,
                                  space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                                      .union(.byteOrder16Big),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return nil }

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
