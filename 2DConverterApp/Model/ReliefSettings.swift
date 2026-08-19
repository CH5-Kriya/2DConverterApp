import Foundation

/// A named starting point for the four sliders. "Details" is the pipeline's own
/// default tuning; "Simple" trades surface detail for a shape that prints
/// cleanly at a coarse layer height.
nonisolated enum ReliefPreset: String, CaseIterable, Identifiable, Codable {
    case simple = "Simple"
    case details = "Details"

    var id: Self { self }

    var settings: ReliefSettings {
        switch self {
        case .simple:
            ReliefSettings(preset: .simple, depth: 0.5, smoothness: 0.8,
                           texture: 0.25, outline: 0.6)
        case .details:
            ReliefSettings(preset: .details, depth: ReliefSliders.depthDefault,
                           smoothness: ReliefSliders.smoothDefault,
                           texture: ReliefSliders.textureDefault,
                           outline: ReliefSliders.outlineDefault)
        }
    }
}

/// The four sliders, all normalised 0–1, plus the preset they came from.
///
/// Every one of them lives in the cheap half of the pipeline, so moving one
/// re-blends cached layers instead of re-running the solver. Grouping them into
/// one value is what makes undo a matter of swapping a struct — and what lets
/// a whole tuning session be saved as seven numbers beside the project.
nonisolated struct ReliefSettings: Equatable, Hashable, Codable {
    var preset: ReliefPreset = .details
    var depth: Double = ReliefSliders.depthDefault       // mesh.relief_mm
    var smoothness: Double = ReliefSliders.smoothDefault // lambda_rough vs lambda_main
    var texture: Double = ReliefSliders.textureDefault   // lambda_detail
    var outline: Double = ReliefSliders.outlineDefault   // ordering_strength
}

/// Slider positions mapped onto the pipeline's own parameters.
nonisolated enum ReliefSliders {
    static let depthDefault = 0.72      // ~30 mm, the reference export
    static let smoothDefault = 0.5
    static let textureDefault = 0.8     // lambda_detail 0.04 of a 0.05 cap
    static let outlineDefault = 1.0

    static func reliefMm(_ t: Double) -> Double { 4 + t * 36 }        // 4–40 mm
    static func lambdaRough(_ t: Double) -> Double { t * 0.7 }        // 0–0.7
    static func lambdaMain(_ t: Double) -> Double { 0.7 - t * 0.5 }   // 0.7–0.2
    static func lambdaDetail(_ t: Double) -> Double { t * 0.05 }      // capped at 0.05
}
