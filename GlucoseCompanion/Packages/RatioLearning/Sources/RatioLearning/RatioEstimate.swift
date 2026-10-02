import GlucoseCore

/// Result of a single regression run, shared by `CarbRatioEstimator` and
/// `CorrectionFactorEstimator`.
///
/// There is no `.insufficientData` case represented here on purpose: when
/// there isn't enough clean data to fit a trustworthy line, the estimator
/// returns `nil` from `estimate(...)` rather than constructing a
/// `RatioEstimate` with a made-up or zero value. Callers translate a `nil`
/// result into `ConfidenceLevel.insufficientData` when writing back to a
/// `TimeOfDayProfile`. This keeps "we don't know yet" impossible to confuse
/// with "we computed a low-confidence value."
public struct RatioEstimate {
    /// The learned ratio itself (grams/unit for carb ratio, mg/dL/unit for
    /// correction factor).
    public let value: Double
    /// Number of qualifying (non-confounded, in-range) events the fit was
    /// computed from.
    public let dataPointCount: Int
    /// Uncentered R^2 of the regression-through-origin fit. See
    /// `LinearRegression` for why the fit is forced through the origin.
    public let rSquared: Double
    public let confidence: ConfidenceLevel

    public init(value: Double, dataPointCount: Int, rSquared: Double, confidence: ConfidenceLevel) {
        self.value = value
        self.dataPointCount = dataPointCount
        self.rSquared = rSquared
        self.confidence = confidence
    }

    /// Confidence tiers by sample size only (not fit quality). This is a
    /// deliberately conservative, easy-to-explain rule: "we saw N clean
    /// meals" is something a person managing their own insulin can reason
    /// about and check; a composite score blending R^2 and N would be
    /// harder to audit and easier to accidentally over-trust.
    static func confidence(forDataPointCount count: Int) -> ConfidenceLevel {
        switch count {
        case ..<8: return .insufficientData // callers should not reach this; see `estimate(...)` gating
        case 8..<20: return .low
        case 20..<40: return .medium
        default: return .high
        }
    }
}
