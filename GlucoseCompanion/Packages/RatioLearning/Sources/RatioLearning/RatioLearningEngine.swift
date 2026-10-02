import Foundation
import GlucoseCore

/// The single orchestrating entry point for this package. Intended to be
/// called from a daily background job or a manual "Recalculate" button in
/// the app.
///
/// IMPORTANT -- this package never persists anything. It has no
/// `ModelContext` and cannot have one (it only depends on `GlucoseCore` for
/// model *types*, not for SwiftData plumbing). `recompute` reads the arrays
/// you pass in and returns brand-new `TimeOfDayProfile` instances carrying
/// the freshly computed `learnedCarbRatio`, `learnedCorrectionFactor`,
/// `dataPointCount`, `confidence`, and `lastComputedAt`. It is the caller's
/// responsibility to copy those five fields onto the actual managed
/// `TimeOfDayProfile` objects living in their `ModelContext` and save. The
/// objects returned here should not themselves be inserted into a context or
/// treated as replacements for the live ones -- `id`, `blockName`,
/// `startHour`, `endHour`, and the `userOverride*` fields are carried over
/// only so the returned object is a convenient, complete snapshot to read
/// values off of.
public enum RatioLearningEngine {

    public static func recompute(
        profiles: [TimeOfDayProfile],
        carbEntries: [CarbEntry],
        insulinDoses: [InsulinDose],
        glucoseReadings: [GlucoseReading],
        targetMidpointMgdl: Double,
        excludeWindows: [DateInterval] = [],
        now: Date = Date()
    ) -> [TimeOfDayProfile] {
        // Extracted once and shared across every block: matching carbs to
        // boluses and flagging confounds doesn't depend on the time-of-day
        // grouping, so there's no reason to redo it per profile.
        let events = MealExcursionMatcher.extractEvents(
            carbEntries: carbEntries,
            insulinDoses: insulinDoses,
            glucoseReadings: glucoseReadings,
            excludeWindows: excludeWindows
        )

        let calendar = Calendar.current

        return profiles.map { profile in
            let blockEvents = events.filter { event in
                let hour = calendar.component(.hour, from: event.carbEntry.timestamp)
                return profile.contains(hour: hour)
            }

            let carbRatioEstimate = CarbRatioEstimator.estimate(
                events: blockEvents,
                targetMidpointMgdl: targetMidpointMgdl
            )

            // The correction estimator subtracts out the carb-covering
            // portion of each dose using whatever carb ratio we just
            // learned for this same block/run. If we didn't learn one this
            // run, it falls back to treating the whole dose as correction
            // (see CorrectionFactorEstimator's doc comment on that
            // trade-off) rather than reusing a stale ratio from a previous
            // run that this run's data may no longer support.
            let correctionEstimate = CorrectionFactorEstimator.estimate(
                events: blockEvents,
                carbRatio: carbRatioEstimate?.value,
                targetMidpointMgdl: targetMidpointMgdl
            )

            return updatedProfile(
                from: profile,
                carbRatioEstimate: carbRatioEstimate,
                correctionEstimate: correctionEstimate,
                now: now
            )
        }
    }

    private static func updatedProfile(
        from profile: TimeOfDayProfile,
        carbRatioEstimate: RatioEstimate?,
        correctionEstimate: RatioEstimate?,
        now: Date
    ) -> TimeOfDayProfile {
        // A profile's `dataPointCount` and `confidence` describe the block
        // as a whole, but the two regressions can draw on different
        // (overlapping but distinct) subsets of events -- near-target
        // meals for carb ratio, above-target meals for correction factor.
        // We report the more conservative (smaller/lower) of the two so the
        // combined confidence never overstates the weaker-supported number,
        // and so a profile is never labeled with more confidence than its
        // least-supported learned value deserves.
        let dataPointCount: Int
        let confidence: ConfidenceLevel
        switch (carbRatioEstimate, correctionEstimate) {
        case let (carb?, correction?):
            dataPointCount = min(carb.dataPointCount, correction.dataPointCount)
            confidence = weaker(carb.confidence, correction.confidence)
        case let (carb?, nil):
            dataPointCount = carb.dataPointCount
            confidence = carb.confidence
        case let (nil, correction?):
            dataPointCount = correction.dataPointCount
            confidence = correction.confidence
        case (nil, nil):
            dataPointCount = 0
            confidence = .insufficientData
        }

        return TimeOfDayProfile(
            id: profile.id,
            blockName: profile.blockName,
            startHour: profile.startHour,
            endHour: profile.endHour,
            // A `nil` estimate means "not enough clean data this run" --
            // we deliberately do not fall back to a previous run's learned
            // value here, since keeping an old number while dropping its
            // confidence would be a silent, hard-to-detect downgrade. A
            // clear `nil` is the honest representation of "we don't
            // currently have a trustworthy learned value."
            learnedCarbRatio: carbRatioEstimate?.value,
            learnedCorrectionFactor: correctionEstimate?.value,
            dataPointCount: dataPointCount,
            confidence: confidence,
            lastComputedAt: now,
            // User overrides are never touched by this package.
            userOverrideCarbRatio: profile.userOverrideCarbRatio,
            userOverrideCorrectionFactor: profile.userOverrideCorrectionFactor
        )
    }

    private static func weaker(_ a: ConfidenceLevel, _ b: ConfidenceLevel) -> ConfidenceLevel {
        func rank(_ level: ConfidenceLevel) -> Int {
            switch level {
            case .insufficientData: return 0
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            }
        }
        return rank(a) <= rank(b) ? a : b
    }
}
