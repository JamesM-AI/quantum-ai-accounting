import Foundation
import GlucoseCore
import RatioLearning

/// Learned correction sensitivity, split by whether meaningful activity
/// followed the dose.
public struct CorrectionSensitivityEstimate: Sendable {
    /// Fit only from events where meaningful activity followed the
    /// correction (steps >= activityStepsThreshold, or a workout).
    public let withActivity: RatioEstimate?
    /// Fit only from events with no meaningful activity following.
    public let withoutActivity: RatioEstimate?

    public init(withActivity: RatioEstimate?, withoutActivity: RatioEstimate?) {
        self.withActivity = withActivity
        self.withoutActivity = withoutActivity
    }
}

/// Learns two mg/dL-per-unit sensitivity values from historical standalone
/// correction events -- one for occasions followed by meaningful activity,
/// one for occasions with none -- so the app can tell whether this person's
/// corrections tend to behave differently when they're active afterward.
///
/// Like `RatioLearning`'s estimators, this never fabricates a value: when
/// there isn't enough clean data in a cohort to fit a trustworthy line, that
/// cohort's estimate is `nil` rather than a guess. "We don't know yet" and
/// "we computed a low-confidence number" are kept impossible to confuse.
public enum CorrectionSensitivityEstimator {

    /// Regresses `bolusDose.units` against `(preGlucoseMgdl - targetMidpointMgdl)`
    /// forced through the origin (same approach as `RatioLearning`'s
    /// `CorrectionFactorEstimator`), separately for the two activity
    /// cohorts. The resulting mg/dL-per-unit value for each cohort is
    /// `1 / slope`. Only events with `outcome != .indeterminate` are used
    /// (an event with no usable follow-up glucose data can't tell you
    /// anything about how well the correction worked).
    public static func estimate(
        events: [CorrectionEvent],
        targetMidpointMgdl: Double,
        minimumDataPoints: Int = 8,
        activityStepsThreshold: Int = 1000
    ) -> CorrectionSensitivityEstimate {
        let usable = events.filter { $0.outcome != .indeterminate }

        let withActivityEvents = usable.filter { hadMeaningfulActivity($0, threshold: activityStepsThreshold) }
        let withoutActivityEvents = usable.filter { !hadMeaningfulActivity($0, threshold: activityStepsThreshold) }

        return CorrectionSensitivityEstimate(
            withActivity: fit(
                events: withActivityEvents,
                targetMidpointMgdl: targetMidpointMgdl,
                minimumDataPoints: minimumDataPoints
            ),
            withoutActivity: fit(
                events: withoutActivityEvents,
                targetMidpointMgdl: targetMidpointMgdl,
                minimumDataPoints: minimumDataPoints
            )
        )
    }

    private static func hadMeaningfulActivity(_ event: CorrectionEvent, threshold: Int) -> Bool {
        event.stepsAfterWindow >= threshold || event.hadWorkoutAfter
    }

    private static func fit(
        events: [CorrectionEvent],
        targetMidpointMgdl: Double,
        minimumDataPoints: Int
    ) -> RatioEstimate? {
        // Built as a single compactMap (rather than a filter followed by a
        // separate map) so the excess-glucose and correction-units arrays
        // fed to the regression are guaranteed to stay index-aligned and
        // the same length by construction.
        let samples: [(excessGlucose: Double, correctionUnits: Double)] = events.compactMap { event in
            guard event.preGlucoseMgdl > targetMidpointMgdl else { return nil }
            return (event.preGlucoseMgdl - targetMidpointMgdl, event.bolusDose.units)
        }

        guard samples.count >= minimumDataPoints else { return nil }

        // correctionUnits = slope * excessGlucose, forced through the
        // origin: zero glucose above target should mean zero correction
        // units, by definition of "correction".
        guard let regression = LinearRegressionThroughOrigin.fit(
            x: samples.map(\.excessGlucose),
            y: samples.map(\.correctionUnits)
        ), regression.slope > 0 else {
            return nil
        }

        let mgdlPerUnit = 1.0 / regression.slope
        return RatioEstimate(
            value: mgdlPerUnit,
            dataPointCount: samples.count,
            rSquared: regression.rSquared,
            confidence: confidence(forDataPointCount: samples.count)
        )
    }

    /// Confidence tiers by sample size only (not fit quality), matching
    /// `RatioLearning.RatioEstimate`'s own tiering convention exactly for
    /// consistency across the app. That helper isn't public in
    /// `RatioLearning`, so it's re-declared here rather than imported.
    private static func confidence(forDataPointCount count: Int) -> ConfidenceLevel {
        switch count {
        case ..<8: return .insufficientData // callers should not reach this; see `fit(...)` gating
        case 8..<20: return .low
        case 20..<40: return .medium
        default: return .high
        }
    }
}
