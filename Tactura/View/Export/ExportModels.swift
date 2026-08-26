import Foundation

/// What the app can actually write today.
///
/// Deliberately shorter than the mock's dropdown. The mock offers `.glb`, but
/// `Export.swift` states plainly that GLB was dropped on device and USDZ has a
/// config flag with no implementation behind it. Listing a format the pipeline
/// cannot produce turns a picker into a promise the app breaks, so the menu
/// grows when the writers do — not before.
enum ExportFormat: String, CaseIterable, Identifiable {
    case stl
    case heightMap

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .stl:       "stl"
        case .heightMap: "png"
        }
    }

    var label: String { ".\(fileExtension)" }

    var detail: String {
        switch self {
        case .stl:       "Solid for 3D printing"
        case .heightMap: "16-bit height map"
        }
    }
}

/// Where an export run is, for the progress dialog.
enum ExportStage: Equatable {
    case idle
    case running(fraction: Double, phase: String, started: Date)
    case finished(URL)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

extension ExportStage {
    /// Remaining time, derived from the rate actually observed so far. The
    /// conversion beside it runs on the same estimate — see `ProgressEstimate`.
    var remaining: Duration? {
        guard case .running(let fraction, _, let started) = self else { return nil }
        return ProgressEstimate.remaining(fraction: fraction, since: started)
    }
}
