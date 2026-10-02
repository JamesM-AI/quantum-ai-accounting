import Foundation
import GlucoseCore
import RatioLearning

/// Learns carb-ratio and correction-factor trends broken down by the
/// activity level (`ActivityBucket`) around each meal event.
///
/// SCOPE BOUNDARY -- read before touching this file: the output of this
/// estimator is informational/trend-only for this iteration. It exists so a
/// person can see "on days/times I'm more active, here's how my numbers tend
/// to look" and factor that into their own judgment. It must NOT be wired
/// into, or otherwise influence, the dose `BolusCalculator` suggests. If a
/// future iteration wants activity to affect the actual suggested dose, that
/// is a deliberate, separate decision requiring its own safety review -- it
/// should not happen implicitly by some caller quietly plumbing this type's
/// output into `BolusCalculator`.
///
/// Thresholds and statistical approach mirror `RatioLearning`'s
/// `CarbRatioEstimator` / `CorrectionFactorEstimator` for consistency: linear
/// regression forced through the origin, confidence tiered by sample count
/// only, `nil` (not a fabricated value) when there isn't enough clean data.
public struct ActivityAdjustedProfile: Sendable {
    public let bucket: ActivityBucket
    public let carbRatio: RatioEstimate?
    public let correctionFactor: RatioEstimate?

    public init(bucket: ActivityBucket, carbRatio: RatioEstimate?, correctionFactor: RatioEstimate?) {
        self.bucket = bucket
        self.carbRatio = carbRatio
        self.correctionFactor = correctionFactor
    }
}

public enum ActivityAdjustedRatioEstimator {

    /// Same near-target tolerance `CarbRatioEstimator` uses: only events
    /// whose pre-meal glucose was already close to target qualify for the
    /// carb-ratio fit, so correction work mixed into the same dose doesn't
    /// bias the carbs-vs-units slope.
    private static let preGlucoseToleranceMgdl: Double = 15.0

    /// One `ActivityAdjustedProfile` per `ActivityBucket` case, always all
    /// three (even if both estimates are nil for a bucket with no/too-little
    /// data) so callers can render a consistent "not enough data for this
    /// activity level yet" state rather than a bucket silently disappearing.
    public static func estimate(
        contexts: [MealActivityContext],
        targetMidpointMgdl: Double,
        minimumDataPoints: Int = 8
    ) -> [ActivityAdjustedProfile] {
        ActivityBucket.allCases.map { bucket in
            let bucketContexts = contexts.filter { $0.bucket == bucket && !$0.mealEvent.isConfounded }

            let carbRatio = estimateCarbRatio(
                from: bucketContexts,
                targetMidpointMgdl: targetMidpointMgdl,
                minimumDataPoints: minimumDataPoints
            )
            let correctionFactor = estimateCorrectionFactor(
                from: bucketContexts,
                carbRatio: carbRatio?.value,
                targetMidpointMgdl: targetMidpointMgdl,
                minimumDataPoints: minimumDataPoints
            )

            return ActivityAdjustedProfile(bucket: bucket, carbRatio: carbRatio, correctionFactor: correctionFactor)
        }
    }

    /// Mirrors `CarbRatioEstimator.estimate`, but regressing only over
    /// events already filtered to a single `ActivityBucket`.
    private static func estimateCarbRatio(
        from contexts: [MealActivityContext],
        targetMidpointMgdl: Double,
        minimumDataPoints: Int
    ) -> RatioEstimate? {
        let samples: [(grams: Double, units: Double)] = contexts.compactMap { context in
            let event = context.mealEvent
            guard let pre = event.preGlucoseMgdl,
                  abs(pre - targetMidpointMgdl) <= preGlucoseToleranceMgdl else { return nil }
            return (event.carbEntry.grams, event.bolusDose.units)
        }

        guard samples.count >= minimumDataPoints else { return nil }

        guard let fit = LinearRegressionThroughOrigin.fit(
            x: samples.map(\.grams),
            y: samples.map(\.units)
        ), fit.slope > 0 else {
            return nil
        }

        let gramsPerUnit = 1.0 / fit.slope
        return RatioEstimate(
            value: gramsPerUnit,
            dataPointCount: samples.count,
            rSquared: fit.rSquared,
            confidence: confidence(forDataPointCount: samples.count)
        )
    }

    /// Mirrors `CorrectionFactorEstimator.estimate`, but regressing only
    /// over events already filtered to a single `ActivityBucket`. As in
    /// `CorrectionFactorEstimator`, when no carb ratio is available for this
    /// same bucket, the full dose is treated as correction -- only
    /// reasonable when the bucket's meals carry little carb weight, but
    /// preferable to inventing a carb ratio from a different bucket's data.
    private static func estimateCorrectionFactor(
        from contexts: [MealActivityContext],
        carbRatio: Double?,
        targetMidpointMgdl: Double,
        minimumDataPoints: Int
    ) -> RatioEstimate? {
        let samples: [(excessGlucose: Double, correctionUnits: Double)] = contexts.compactMap { context in
            let event = context.mealEvent
            guard let pre = event.preGlucoseMgdl, pre > targetMidpointMgdl else { return nil }

            let carbCoveringUnits = carbRatio.map { event.carbEntry.grams / $0 } ?? 0
            let correctionUnits = event.bolusDose.units - carbCoveringUnits
            return (pre - targetMidpointMgdl, correctionUnits)
        }

        guard samples.count >= minimumDataPoints else { return nil }

        guard let fit = LinearRegressionThroughOrigin.fit(
            x: samples.map(\.excessGlucose),
            y: samples.map(\.correctionUnits)
        ), fit.slope > 0 else {
            return nil
        }

        let mgdlPerUnit = 1.0 / fit.slope
        return RatioEstimate(
            value: mgdlPerUnit,
            dataPointCount: samples.count,
            rSquared: fit.rSquared,
            confidence: confidence(forDataPointCount: samples.count)
        )
    }

    /// Mirrors `RatioEstimate`'s own (non-public, so not directly callable
    /// from this package) `confidence(forDataPointCount:)` tiering exactly,
    /// for consistency with the rest of the app: sample-size-only tiers,
    /// never a composite score blending in fit quality.
    private static func confidence(forDataPointCount count: Int) -> ConfidenceLevel {
        switch count {
        case ..<8: return .insufficientData
        case 8..<20: return .low
        case 20..<40: return .medium
        default: return .high
        }
    }
}
