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
    /// Remaining time, derived from the rate actually observed so far.
    ///
    /// `nil` until enough of the run has elapsed for the extrapolation to mean
    /// anything. The mock shows "12 minutes remaining" from the first frame;
    /// a countdown invented before there is any rate to measure is a guess
    /// wearing a number's clothes, and it is worse than showing the phase.
    var remaining: Duration? {
        guard case .running(let fraction, _, let started) = self,
              fraction >= 0.15 else { return nil }
        let elapsed = Date.now.timeIntervalSince(started)
        guard elapsed > 1 else { return nil }
        let total = elapsed / fraction
        return .seconds(max(0, total - elapsed))
    }
}

extension Duration {
    /// "12 minutes remaining" / "40 seconds remaining", rounded the way a person
    /// reads a wait rather than the way a timer counts one.
    var remainingPhrase: String {
        let seconds = Int(components.seconds)
        if seconds >= 90 {
            let minutes = Int((Double(seconds) / 60).rounded())
            return "\(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        }
        let rounded = max(5, (seconds / 5) * 5)
        return "\(rounded) seconds remaining"
    }
}
