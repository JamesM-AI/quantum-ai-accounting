import Foundation

/// A small, evidence-grounded summary of "how much activity has actually
/// worked for this person" -- built from their own correction history, not
/// a generic step-count prescription.
public struct ActivityTargetSuggestion: Sendable {
    /// Median `stepsAfterWindow` among events that both (a) had activity
    /// following (steps > 0 or a workout) and (b) resolved `.successful`.
    /// Nil if there aren't at least `minimumSampleCount` such events.
    public let medianSuccessfulSteps: Int?
    public let sampleCount: Int

    public init(medianSuccessfulSteps: Int?, sampleCount: Int) {
        self.medianSuccessfulSteps = medianSuccessfulSteps
        self.sampleCount = sampleCount
    }
}

/// Surfaces a concrete, historical "this is what has worked for you" number
/// -- e.g. so the UI can say "in your history, corrections followed by
/// about N steps of activity tended to resolve without a low" -- rather
/// than a generic, one-size-fits-all activity recommendation.
public enum ActivityTargetEstimator {

    /// - Parameter minimumSampleCount: Below this many qualifying events,
    ///   `medianSuccessfulSteps` is withheld (`nil`) rather than computed
    ///   from too small a sample -- `sampleCount` is still reported so the
    ///   UI can show "only N so far, keep logging" instead of nothing.
    public static func suggest(events: [CorrectionEvent], minimumSampleCount: Int = 5) -> ActivityTargetSuggestion {
        let qualifying = events.filter { event in
            (event.stepsAfterWindow > 0 || event.hadWorkoutAfter) && event.outcome == .successful
        }

        guard qualifying.count >= minimumSampleCount else {
            return ActivityTargetSuggestion(medianSuccessfulSteps: nil, sampleCount: qualifying.count)
        }

        let steps = qualifying.map(\.stepsAfterWindow).sorted()
        let median = median(of: steps)

        return ActivityTargetSuggestion(medianSuccessfulSteps: median, sampleCount: qualifying.count)
    }

    /// Median of an already-sorted, non-empty array of step counts. For an
    /// even count, averages the two middle values (rounded to the nearest
    /// whole step rather than truncated, so a mid-value like 500.5 doesn't
    /// silently drift down).
    private static func median(of sortedSteps: [Int]) -> Int {
        let count = sortedSteps.count
        if count % 2 == 1 {
            return sortedSteps[count / 2]
        }
        let lower = sortedSteps[count / 2 - 1]
        let upper = sortedSteps[count / 2]
        return Int((Double(lower + upper) / 2.0).rounded())
    }
}
