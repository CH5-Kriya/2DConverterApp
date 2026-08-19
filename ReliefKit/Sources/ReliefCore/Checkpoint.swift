import Foundation

/// A finished stage 1–5 run, kept so the tuner can go on working on a
/// conversion it did not just perform.
///
/// Deliberately *not* the whole `Analysis`. Stages 1–4 also produce the working
/// image, its Lab, the lightness and brightness fields and the raw depth, and
/// none of them is read again once `buildVolume` has run — every slider lands
/// in `blend`, which needs the four Z_* layers, the region map they are ordered
/// by, and the foreground mask. Carrying the rest would roughly triple both the
/// file on disk and what the app holds for a project someone merely revisited.
public struct ReliefCheckpoint: Sendable {
    public let labels: Plane
    public let regionCount: Int
    public let mask: [UInt8]
    public let zAi: Plane
    public let zRough: Plane
    public let zMain: Plane
    public let zDetail: Plane
    /// Carried so a restored project reports the run it actually came from
    /// rather than the defaults of the run it did not have to do again.
    public let routeMode: String
    public let depthBackend: String

    public init(labels: Plane, regionCount: Int, mask: [UInt8],
                zAi: Plane, zRough: Plane, zMain: Plane, zDetail: Plane,
                routeMode: String, depthBackend: String) {
        self.labels = labels
        self.regionCount = regionCount
        self.mask = mask
        self.zAi = zAi
        self.zRough = zRough
        self.zMain = zMain
        self.zDetail = zDetail
        self.routeMode = routeMode
        self.depthBackend = depthBackend
    }

    public var rows: Int { zAi.rows }
    public var cols: Int { zAi.cols }
}

// MARK: - On-disk form

extension ReliefCheckpoint {

    private static let magic: UInt32 = 0x52_4C_46_43   // "RLFC"
    private static let version: UInt32 = 1

    /// Quantised to 16 bits per sample rather than written as `Float`.
    ///
    /// The Z_* layers are bounded fields, so a per-plane range plus a 16-bit
    /// index resolves them to one part in 65535 of their own span — under a
    /// micron once `mesh.relief_mm` scales them, which is three orders of
    /// magnitude below anything a printer can lay down. It halves the file for
    /// an error the output cannot represent.
    public func encoded() -> Data {
        var body = ByteWriter()
        body.putScalar(Int32(rows))
        body.putScalar(Int32(cols))
        body.putScalar(Int32(regionCount))

        // Region indices are exact, not quantised — `enforceOrdering` groups by
        // them, so a label that rounds into its neighbour merges two regions.
        let wide = regionCount > Int(UInt16.max)
        body.putScalar(UInt8(wide ? 4 : 2))
        body.putString(routeMode)
        body.putString(depthBackend)

        if wide {
            body.putArray(labels.values.map { UInt32(max(0, $0)) })
        } else {
            body.putArray(labels.values.map { UInt16(max(0, min(Float(UInt16.max), $0))) })
        }
        body.putArray(mask)
        for plane in [zAi, zRough, zMain, zDetail] {
            let (low, span, samples) = Self.quantize(plane)
            body.putScalar(low)
            body.putScalar(span)
            body.putArray(samples)
        }

        var out = ByteWriter()
        out.putScalar(Self.magic)
        out.putScalar(Self.version)
        // LZFSE is Apple's own general-purpose codec: it takes roughly a fifth
        // off quantised height fields for a fraction of the time the write
        // itself costs. Falling back to raw keeps a compressor failure from
        // costing the checkpoint.
        if let squeezed = try? (body.data as NSData).compressed(using: .lzfse) as Data {
            out.putScalar(UInt8(1))
            out.data.append(squeezed)
        } else {
            out.putScalar(UInt8(0))
            out.data.append(body.data)
        }
        return out.data
    }

    /// `nil` for anything this build cannot read — a truncated write, a file
    /// from a newer format. The caller's answer to that is to convert again,
    /// which is slow but always correct, so there is nothing to throw about.
    public static func decode(_ data: Data) -> ReliefCheckpoint? {
        var header = ByteReader(data)
        guard header.scalar(UInt32.self) == magic,
              let fileVersion = header.scalar(UInt32.self), fileVersion == version,
              let compression = header.scalar(UInt8.self) else { return nil }

        let payload = data.dropFirst(header.offset)
        let raw: Data
        switch compression {
        case 0: raw = Data(payload)
        case 1:
            guard let expanded = try? (Data(payload) as NSData).decompressed(using: .lzfse) as Data
            else { return nil }
            raw = expanded
        default: return nil
        }

        var body = ByteReader(raw)
        guard let rows = body.scalar(Int32.self).map(Int.init),
              let cols = body.scalar(Int32.self).map(Int.init),
              let regionCount = body.scalar(Int32.self).map(Int.init),
              let labelWidth = body.scalar(UInt8.self),
              let routeMode = body.string(),
              let depthBackend = body.string(),
              rows > 0, cols > 0 else { return nil }

        let count = rows * cols
        let labelValues: [Float]
        switch labelWidth {
        case 2:
            guard let raw = body.array(UInt16.self, count: count, zero: 0) else { return nil }
            labelValues = raw.map { Float($0) }
        case 4:
            guard let raw = body.array(UInt32.self, count: count, zero: 0) else { return nil }
            // Spelled out rather than `map(Float.init)`: an unapplied `Float.init`
            // against a `UInt32` also matches `Float(bitPattern:)`, and that
            // overload turns every region index into a denormal near zero.
            labelValues = raw.map { Float($0) }
        default: return nil
        }

        guard let mask = body.array(UInt8.self, count: count, zero: 0) else { return nil }

        var planes: [Plane] = []
        for _ in 0..<4 {
            guard let low = body.scalar(Float.self),
                  let span = body.scalar(Float.self),
                  let samples = body.array(UInt16.self, count: count, zero: 0)
            else { return nil }
            planes.append(dequantize(low: low, span: span, samples,
                                     rows: rows, cols: cols))
        }

        return ReliefCheckpoint(
            labels: Plane(rows: rows, cols: cols, values: labelValues),
            regionCount: regionCount, mask: mask,
            zAi: planes[0], zRough: planes[1], zMain: planes[2], zDetail: planes[3],
            routeMode: routeMode, depthBackend: depthBackend)
    }

    private static func quantize(_ plane: Plane) -> (low: Float, span: Float, [UInt16]) {
        var low = Float.greatestFiniteMagnitude
        var high = -Float.greatestFiniteMagnitude
        for value in plane.values where value.isFinite {
            low = min(low, value)
            high = max(high, value)
        }
        // An all-NaN or empty plane leaves the bounds crossed; a flat one leaves
        // them equal. Both collapse to a constant field, which is what they are.
        guard low <= high else { return (0, 0, [UInt16](repeating: 0, count: plane.count)) }

        let span = high - low
        let scale = span > 0 ? Float(UInt16.max) / span : 0
        var out = [UInt16](repeating: 0, count: plane.count)
        for i in 0..<plane.count {
            let value = plane.values[i]
            guard value.isFinite else { continue }
            out[i] = UInt16(min(Float(UInt16.max), max(0, ((value - low) * scale).rounded())))
        }
        return (low, span, out)
    }

    private static func dequantize(low: Float, span: Float, _ samples: [UInt16],
                                   rows: Int, cols: Int) -> Plane {
        let scale = span / Float(UInt16.max)
        return Plane(rows: rows, cols: cols,
                     values: samples.map { low + Float($0) * scale })
    }
}

// MARK: - Bytes

/// Append-only byte buffer. Small enough to keep here rather than reach for a
/// serialisation library the package does not otherwise need.
private struct ByteWriter {
    var data = Data()

    mutating func putScalar<T>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    mutating func putString(_ text: String) {
        let bytes = Array(text.utf8)
        putScalar(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }

    mutating func putArray<T>(_ values: [T]) {
        values.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            data.append(Data(bytes: base,
                             count: buffer.count * MemoryLayout<T>.stride))
        }
    }
}

/// The reverse, and bounds-checked throughout: this reads a file, and a file
/// can be truncated, half-written, or from another build.
private struct ByteReader {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) { self.data = data }

    mutating func scalar<T>(_ type: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return nil }
        // `loadUnaligned` rather than a bound pointer: the strings ahead of the
        // arrays make every following offset arbitrary.
        let value = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset += size
        return value
    }

    mutating func string() -> String? {
        guard let length = scalar(UInt32.self).map(Int.init),
              offset + length <= data.count else { return nil }
        let start = data.startIndex + offset
        defer { offset += length }
        return String(decoding: data[start..<(start + length)], as: UTF8.self)
    }

    mutating func array<T>(_ type: T.Type, count: Int, zero: T) -> [T]? {
        let size = count * MemoryLayout<T>.stride
        guard count >= 0, offset + size <= data.count else { return nil }
        var out = [T](repeating: zero, count: count)
        let start = data.startIndex + offset
        let chunk = data[start..<(start + size)]
        _ = out.withUnsafeMutableBytes { chunk.copyBytes(to: $0) }
        offset += size
        return out
    }
}
