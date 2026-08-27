import Foundation

/// How long a run has left, from the rate it has actually shown so far.
///
/// Shared by the conversion and the export deliberately. They are the app's two
/// waits, they are the only two things it asks a person to sit through, and a
/// countdown that rounds one way beside the relief and another way beside the
/// file would read as two different apps. The two word it differently — the
/// conversion's card has room for "Estimated Time: 12 minutes" where the
/// panel's cramped row has room only for "12 minutes remaining" — but both
/// spell the *number* through `roundedPhrase`, so they cannot disagree about
/// how long is left.
enum ProgressEstimate {

    /// `nil` until enough of the run has elapsed for the extrapolation to mean
    /// anything. The mock shows "12 minutes" from the first frame; a countdown
    /// invented before there is any rate to measure is a guess wearing a
    /// number's clothes, and it is worse than showing nothing.
    static func remaining(fraction: Double, since started: Date) -> Duration? {
        guard fraction >= 0.15 else { return nil }
        let elapsed = Date.now.timeIntervalSince(started)
        guard elapsed > 1 else { return nil }
        let total = elapsed / fraction
        return .seconds(max(0, total - elapsed))
    }

    /// The clock that counts up beside the conversion's bar, in the design's
    /// `00:00:01`. Hours are always shown: a field that grows a segment partway
    /// through a long run shifts every digit beside it.
    static func elapsedClock(since started: Date) -> String {
        let total = max(0, Int(Date.now.timeIntervalSince(started)))
        return String(format: "%02d:%02d:%02d",
                      total / 3600, (total % 3600) / 60, total % 60)
    }
}

extension Duration {
    /// The quantity on its own — "12 minutes", "40 seconds" — rounded the way a
    /// person reads a wait rather than the way a timer counts one. Both phrases
    /// below are built from this, so neither can round differently.
    var roundedPhrase: String {
        let seconds = Int(components.seconds)
        if seconds >= 90 {
            let minutes = Int((Double(seconds) / 60).rounded())
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(max(5, (seconds / 5) * 5)) seconds"
    }

    /// The export panel's wording, where the row is only 238 pt wide.
    var remainingPhrase: String { "\(roundedPhrase) remaining" }

    /// The conversion card's wording, taken from the design's label.
    var estimatePhrase: String { "Estimated Time: \(roundedPhrase)" }
}
