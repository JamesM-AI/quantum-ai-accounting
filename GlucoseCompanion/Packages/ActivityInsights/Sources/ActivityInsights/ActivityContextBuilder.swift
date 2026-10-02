import Foundation
import GlucoseCore
import RatioLearning

/// Builds `MealActivityContext` values by joining `MealEvent`s (already
/// extracted by `RatioLearning.MealExcursionMatcher` -- this package does not
/// do its own meal/bolus/glucose matching) with raw `StepSample` data.
public enum ActivityContextBuilder {

    /// Below this combined (before + after) step count, an event is
    /// classified `.sedentary`. This is a deliberately simple, round-number
    /// heuristic -- not a clinically validated threshold -- chosen as a
    /// reasonable starting point. A future iteration may want these
    /// configurable, or informed by real usage data once enough history
    /// accumulates.
    private static let sedentaryUpperBound = 500

    /// At or above this combined step count, an event is classified
    /// `.active`. Same caveat as `sedentaryUpperBound`: a round-number
    /// heuristic, not a validated clinical cutoff.
    private static let activeLowerBound = 2500

    public static func buildContexts(
        mealEvents: [MealEvent],
        stepSamples: [StepSample],
        beforeWindowHours: Double = 2.0,
        afterWindowHours: Double = 2.0,
        calendar: Calendar = .current
    ) -> [MealActivityContext] {
        mealEvents.map { mealEvent in
            let anchorTime = mealEvent.anchorTime
            let beforeWindowStart = anchorTime.addingTimeInterval(-beforeWindowHours * 3600)
            let afterWindowEnd = anchorTime.addingTimeInterval(afterWindowHours * 3600)

            let stepsBefore = sumOverlappingSteps(
                stepSamples,
                windowStart: beforeWindowStart,
                windowEnd: anchorTime
            )
            let stepsAfter = sumOverlappingSteps(
                stepSamples,
                windowStart: anchorTime,
                windowEnd: afterWindowEnd
            )
            let stepsBackground = stepSamples
                .filter { calendar.isDate($0.startDate, inSameDayAs: anchorTime) }
                .reduce(0) { $0 + $1.stepCount }

            let combined = stepsBefore + stepsAfter
            let bucket: ActivityBucket
            if combined < sedentaryUpperBound {
                bucket = .sedentary
            } else if combined < activeLowerBound {
                bucket = .lightlyActive
            } else {
                bucket = .active
            }

            return MealActivityContext(
                mealEvent: mealEvent,
                stepsBeforeWindow: stepsBefore,
                stepsAfterWindow: stepsAfter,
                stepsBackgroundDaily: stepsBackground,
                bucket: bucket
            )
        }
    }

    /// Sums `stepCount` for every sample whose `[startDate, endDate)` overlaps
    /// `[windowStart, windowEnd)` at all. A sample straddling a window
    /// boundary counts in full for that window rather than being fractionally
    /// prorated -- step data isn't precise enough for that to be meaningful.
    private static func sumOverlappingSteps(
        _ samples: [StepSample],
        windowStart: Date,
        windowEnd: Date
    ) -> Int {
        samples
            .filter { $0.startDate < windowEnd && $0.endDate > windowStart }
            .reduce(0) { $0 + $1.stepCount }
    }
}
