import Foundation

/// The four sliders, all normalised 0–1.
///
/// Every one of them lives in the cheap half of the pipeline, so moving one
/// re-blends cached layers instead of re-running the solver. Grouping them into
/// one value is what makes undo a matter of swapping a struct — and what lets
/// a whole tuning session be saved as four numbers beside the project.
///
/// Simple and Advanced are *not* in here. They decide how many of these four
/// are on screen, not what any of them is worth, so they are a property of the
/// panel rather than of the project — see `ProjectDetailViewModel.ConfigurationMode`.
nonisolated struct ReliefSettings: Equatable, Hashable, Codable {
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
