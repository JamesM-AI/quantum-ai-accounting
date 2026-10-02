import Foundation
import RatioLearning

/// A single steps-vs-glucose-response data point, prepared for a UI-layer
/// scatter/trend chart. This package does no rendering itself -- see the
/// package-level scope note in `ActivityAdjustedRatioEstimator.swift`.
public struct ActivityGlucosePoint: Sendable {
    public let date: Date

    /// `stepsBeforeWindow + stepsAfterWindow` from the source context.
    public let combinedSteps: Int

    /// `postGlucosePeakMgdl - preGlucoseMgdl`; `nil` if either input reading
    /// is missing.
    public let glucoseExcursionMgdl: Double?

    public let isConfounded: Bool

    public init(date: Date, combinedSteps: Int, glucoseExcursionMgdl: Double?, isConfounded: Bool) {
        self.date = date
        self.combinedSteps = combinedSteps
        self.glucoseExcursionMgdl = glucoseExcursionMgdl
        self.isConfounded = isConfounded
    }
}

public enum ActivityTrendBuilder {

    /// One point per context, including confounded events (marked via
    /// `isConfounded` rather than dropped) so the UI can choose to visually
    /// de-emphasize them instead of having them vanish unexplained.
    public static func buildPoints(contexts: [MealActivityContext]) -> [ActivityGlucosePoint] {
        contexts.map { context in
            let event = context.mealEvent
            let excursion: Double?
            if let pre = event.preGlucoseMgdl, let peak = event.postGlucosePeakMgdl {
                excursion = peak - pre
            } else {
                excursion = nil
            }

            return ActivityGlucosePoint(
                date: event.anchorTime,
                combinedSteps: context.stepsBeforeWindow + context.stepsAfterWindow,
                glucoseExcursionMgdl: excursion,
                isConfounded: event.isConfounded
            )
        }
    }
}
