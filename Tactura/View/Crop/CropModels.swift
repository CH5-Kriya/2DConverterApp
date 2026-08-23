import Foundation
import CoreGraphics

/// The crop, in fractions of the source image rather than points on screen.
///
/// Normalised on purpose: the same rectangle has to survive the view being laid
/// out at whatever size the iPad gives it, and has to convert to pixels at the
/// end without carrying a scale factor around. Origin is top-left, matching how
/// the image itself is indexed.
struct CropRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    /// Never let the rectangle collapse to nothing: a crop that is one pixel
    /// wide is not a crop, it is a mistake that will only be discovered when
    /// the relief comes out as a stripe.
    static let minimumSide = 0.06

    func pixels(in size: CGSize) -> CGRect {
        CGRect(x: (x * size.width).rounded(),
               y: (y * size.height).rounded(),
               width: (width * size.width).rounded(),
               height: (height * size.height).rounded())
    }

    /// Clamp back inside the image after any edit.
    func clamped() -> CropRect {
        var rect = self
        rect.width = min(max(rect.width, Self.minimumSide), 1)
        rect.height = min(max(rect.height, Self.minimumSide), 1)
        rect.x = min(max(rect.x, 0), 1 - rect.width)
        rect.y = min(max(rect.y, 0), 1 - rect.height)
        return rect
    }
}

/// Which corner a drag is holding.
enum CropCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var unitPoint: CGPoint {
        switch self {
        case .topLeading:     CGPoint(x: 0, y: 0)
        case .topTrailing:    CGPoint(x: 1, y: 0)
        case .bottomLeading:  CGPoint(x: 0, y: 1)
        case .bottomTrailing: CGPoint(x: 1, y: 1)
        }
    }
}

/// Ratios worth offering for a relief that will be printed on a plate.
enum CropAspect: String, CaseIterable, Identifiable {
    case free
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free:        "Free transform"
        case .original:    "Original"
        case .square:      "1 : 1"
        case .fourThree:   "4 : 3"
        case .threeTwo:    "3 : 2"
        case .sixteenNine: "16 : 9"
        }
    }

    /// Width ÷ height in *image* terms, or nil when the drag is unconstrained.
    /// `original` needs the source's own ratio, so it is resolved by the caller.
    func ratio(originalAspect: Double) -> Double? {
        switch self {
        case .free:        nil
        case .original:    originalAspect
        case .square:      1
        case .fourThree:   4.0 / 3.0
        case .threeTwo:    3.0 / 2.0
        case .sixteenNine: 16.0 / 9.0
        }
    }
}
