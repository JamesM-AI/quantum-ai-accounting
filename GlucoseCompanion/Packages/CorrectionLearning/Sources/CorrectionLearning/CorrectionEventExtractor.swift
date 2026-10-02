import Foundation
import GlucoseCore
import RatioLearning

/// Reconstructs standalone (non-meal-linked) `CorrectionEvent`s from raw
/// logged data.
public enum CorrectionEventExtractor {

    private static let preWindowMinutes: TimeInterval = 15

    /// Reconstructs standalone correction events from raw logs.
    ///
    /// - Parameters:
    ///   - mealEvents: Already-extracted meal events (via
    ///     `RatioLearning.MealExcursionMatcher.extractEvents`, called by the
    ///     caller, NOT by this function) -- used only to identify which
    ///     bolus doses are already meal-linked, so they're excluded here.
    ///     Excluding them avoids double-counting the same dose as both a
    ///     meal event (in `RatioLearning`) and a standalone correction event
    ///     here, which would let one physical dose inflate two separate
    ///     learned models. This also avoids duplicating the carb-pairing
    ///     logic that already lives in `RatioLearning`.
    ///   - targetRangeHighMgdl/targetRangeLowMgdl/lowGlucoseSafetyFloorMgdl:
    ///     from the user's `UserSettings` (passed as plain values, not the
    ///     model, to keep this package's surface small).
    ///   - insulinActionDurationMinutes: from `UserSettings`, defines the
    ///     "action window" used both for finding the minimum glucose and
    ///     for the "glucose at action end" classification point.
    ///   - activityWindowHours: how far after the dose to look for step/
    ///     workout activity (default 3.0 -- independent of the action
    ///     window, since meaningful activity can start any time in the
    ///     hours after a correction).
    ///   - closeToActionEndToleranceMinutes: how much slack to allow when
    ///     looking for "the reading closest to the end of the action
    ///     window" (default 20, mirroring RatioLearning's own tolerance
    ///     conventions).
    public static func extractEvents(
        insulinDoses: [InsulinDose],
        glucoseReadings: [GlucoseReading],
        stepSamples: [StepSample],
        workouts: [WorkoutSession],
        mealEvents: [MealEvent],
        targetRangeLowMgdl: Double,
        targetRangeHighMgdl: Double,
        lowGlucoseSafetyFloorMgdl: Double,
        insulinActionDurationMinutes: Int,
        activityWindowHours: Double = 3.0,
        closeToActionEndToleranceMinutes: Double = 20
    ) -> [CorrectionEvent] {
        let claimedBolusIDs = Set(mealEvents.map { $0.bolusDose.id })
        let candidates = insulinDoses.filter { $0.reason == .bolus && !claimedBolusIDs.contains($0.id) }

        let preWindowSeconds = preWindowMinutes * 60
        let activityWindowSeconds = activityWindowHours * 3600
        let actionWindowSeconds = TimeInterval(insulinActionDurationMinutes) * 60
        let actionEndToleranceSeconds = closeToActionEndToleranceMinutes * 60

        return candidates.compactMap { dose in
            // Only events that started above the target range carry a
            // meaningful correction signal -- this function models corrections
            // of an actual high, not every miscellaneous standalone bolus
            // (e.g. a manually-logged extra dose with no preceding high).
            guard let preGlucose = mostRecentReading(
                glucoseReadings,
                atOrBefore: dose.timestamp,
                notBefore: dose.timestamp.addingTimeInterval(-preWindowSeconds)
            ), preGlucose > targetRangeHighMgdl else {
                return nil
            }

            let activityWindowStart = dose.timestamp
            let activityWindowEnd = dose.timestamp.addingTimeInterval(activityWindowSeconds)

            let stepsAfterWindow = stepSamples
                .filter { $0.startDate < activityWindowEnd && $0.endDate > activityWindowStart }
                .reduce(0) { $0 + $1.stepCount }

            let activityWindow = DateInterval(start: activityWindowStart, end: activityWindowEnd)
            let hadWorkoutAfter = workouts.contains { $0.interval.intersects(activityWindow) }

            let actionEnd = dose.timestamp.addingTimeInterval(actionWindowSeconds)
            let minGlucose = glucoseReadings
                .filter { $0.timestamp > dose.timestamp && $0.timestamp < actionEnd }
                .map(\.mgdl)
                .min()

            let glucoseAtActionEnd = closestReading(
                glucoseReadings,
                to: actionEnd,
                tolerance: actionEndToleranceSeconds
            )

            let outcome = classify(
                minGlucoseMgdl: minGlucose,
                glucoseAtActionEndMgdl: glucoseAtActionEnd,
                targetRangeHighMgdl: targetRangeHighMgdl,
                lowGlucoseSafetyFloorMgdl: lowGlucoseSafetyFloorMgdl
            )

            return CorrectionEvent(
                bolusDose: dose,
                preGlucoseMgdl: preGlucose,
                stepsAfterWindow: stepsAfterWindow,
                hadWorkoutAfter: hadWorkoutAfter,
                minGlucoseMgdl: minGlucose,
                glucoseAtActionEndMgdl: glucoseAtActionEnd,
                outcome: outcome
            )
        }
    }

    private static func classify(
        minGlucoseMgdl: Double?,
        glucoseAtActionEndMgdl: Double?,
        targetRangeHighMgdl: Double,
        lowGlucoseSafetyFloorMgdl: Double
    ) -> CorrectionOutcome {
        guard let minGlucoseMgdl, let glucoseAtActionEndMgdl else {
            return .indeterminate
        }
        if minGlucoseMgdl < lowGlucoseSafetyFloorMgdl {
            return .overcorrected
        }
        if glucoseAtActionEndMgdl > targetRangeHighMgdl {
            return .undercorrected
        }
        return .successful
    }

    private static func mostRecentReading(
        _ readings: [GlucoseReading],
        atOrBefore: Date,
        notBefore: Date
    ) -> Double? {
        readings
            .filter { $0.timestamp <= atOrBefore && $0.timestamp >= notBefore }
            .max(by: { $0.timestamp < $1.timestamp })
            .map(\.mgdl)
    }

    private static func closestReading(
        _ readings: [GlucoseReading],
        to target: Date,
        tolerance: TimeInterval
    ) -> Double? {
        readings
            .filter { abs($0.timestamp.timeIntervalSince(target)) <= tolerance }
            .min(by: { abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target)) })
            .map(\.mgdl)
    }
}
