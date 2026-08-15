import SwiftUI

/// The crop rectangle drawn over the image: a dimmed surround, a thirds grid,
/// and four corner grips.
///
/// The grid is not decoration. Judging where a relief should be cut is a
/// compositional decision, and thirds are the cheapest scaffolding for it.
struct CropOverlay: View {
    @Binding var crop: CropRect
    let aspectRatio: Double?

    /// How close to a corner a touch counts as grabbing it. Generous, because
    /// fingers are not cursors.
    private let grabRadius: CGFloat = 44

    @State private var dragStart: CropRect?
    @State private var activeCorner: CropCorner?

    var body: some View {
        GeometryReader { proxy in
            let frame = rect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                dimmedSurround(frame: frame, size: proxy.size)
                grid(frame: frame)

                Rectangle()
                    .strokeBorder(.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                ForEach(CropCorner.allCases, id: \.self) { corner in
                    grip(corner, frame: frame)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(in: proxy.size))
        }
    }

    // MARK: Geometry

    private func rect(in size: CGSize) -> CGRect {
        CGRect(x: crop.x * size.width,
               y: crop.y * size.height,
               width: crop.width * size.width,
               height: crop.height * size.height)
    }

    private func dimmedSurround(frame: CGRect, size: CGSize) -> some View {
        Rectangle()
            .fill(.black.opacity(0.45))
            .frame(width: size.width, height: size.height)
            .reverseMask {
                Rectangle()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            .allowsHitTesting(false)
    }

    private func grid(frame: CGRect) -> some View {
        Path { path in
            for i in 1...2 {
                let x = frame.minX + frame.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: frame.minY))
                path.addLine(to: CGPoint(x: x, y: frame.maxY))

                let y = frame.minY + frame.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: frame.minX, y: y))
                path.addLine(to: CGPoint(x: frame.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.55), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func grip(_ corner: CropCorner, frame: CGRect) -> some View {
        let point = CGPoint(x: frame.minX + frame.width * corner.unitPoint.x,
                            y: frame.minY + frame.height * corner.unitPoint.y)
        return CornerGrip(corner: corner)
            .frame(width: 26, height: 26)
            .position(point)
            .allowsHitTesting(false)
    }

    // MARK: Dragging

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil {
                    dragStart = start
                    activeCorner = nearestCorner(to: value.startLocation,
                                                 in: size, rect: rect(in: size))
                }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height

                crop = (activeCorner.map { resize(start, corner: $0, dx: dx, dy: dy) }
                        ?? move(start, dx: dx, dy: dy)).clamped()
            }
            .onEnded { _ in
                dragStart = nil
                activeCorner = nil
            }
    }

    private func nearestCorner(to point: CGPoint, in size: CGSize,
                               rect: CGRect) -> CropCorner? {
        let candidates = CropCorner.allCases.map { corner -> (CropCorner, CGFloat) in
            let p = CGPoint(x: rect.minX + rect.width * corner.unitPoint.x,
                            y: rect.minY + rect.height * corner.unitPoint.y)
            return (corner, hypot(p.x - point.x, p.y - point.y))
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }), best.1 <= grabRadius
        else { return nil }
        return best.0
    }

    private func move(_ start: CropRect, dx: Double, dy: Double) -> CropRect {
        var next = start
        next.x += dx
        next.y += dy
        return next
    }

    private func resize(_ start: CropRect, corner: CropCorner,
                        dx: Double, dy: Double) -> CropRect {
        var next = start

        switch corner {
        case .topLeading:
            next.x += dx; next.width -= dx
            next.y += dy; next.height -= dy
        case .topTrailing:
            next.width += dx
            next.y += dy; next.height -= dy
        case .bottomLeading:
            next.x += dx; next.width -= dx
            next.height += dy
        case .bottomTrailing:
            next.width += dx
            next.height += dy
        }

        // A locked ratio drives height from width, then pulls the anchored edge
        // back so the corner opposite the one being dragged stays put.
        if let ratio = aspectRatio {
            let anchored = next
            next.height = anchored.width / ratio
            if corner == .topLeading || corner == .topTrailing {
                next.y = start.y + start.height - next.height
            }
        }
        return next
    }
}

/// The thick L at each corner, the part a finger aims for.
private struct CornerGrip: View {
    let corner: CropCorner

    var body: some View {
        Path { path in
            let length: CGFloat = 26
            let thickness: CGFloat = 5
            let flipX = corner.unitPoint.x == 1
            let flipY = corner.unitPoint.y == 1

            let x0: CGFloat = flipX ? length - thickness : 0
            let y0: CGFloat = flipY ? length - thickness : 0
            path.addRect(CGRect(x: flipX ? 0 : 0, y: y0, width: length, height: thickness))
            path.addRect(CGRect(x: x0, y: 0, width: thickness, height: length))
        }
        .fill(.white)
    }
}

private extension View {
    /// Punches a hole in a fill — the surround dim needs the crop cut out of it.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .topLeading) {
                    mask().blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}
