import Foundation

/// A minimal, dependency-free least-squares helper shared by
/// `CarbRatioEstimator` and `CorrectionFactorEstimator`.
///
/// Both estimators fit a line *forced through the origin* (`y = slope * x`)
/// rather than a general `y = slope * x + intercept` line. That's a
/// deliberate choice, not a simplification for its own sake: physiologically,
/// zero grams of carbohydrate should require zero bolus units to cover the
/// meal, and zero glucose above target should require zero correction units.
/// A free intercept would let sampling noise in a modest data set (these are
/// meals from one person's real life, not a controlled trial) manufacture a
/// phantom constant dose with no physiological meaning, and that constant
/// would silently bias every future suggestion. Forcing the origin encodes
/// the one fact we're already certain of and lets the data speak only to the
/// question we actually care about: the per-gram / per-mg/dL rate.
enum LinearRegression {

    struct Fit {
        let slope: Double
        /// Uncentered R^2 (1 - SS_res / sum(y^2)), the standard measure of
        /// fit quality for regression-through-the-origin models. It is not
        /// directly comparable to the R^2 of a fitted-intercept model, but
        /// it's consistent across both estimators here, and that's all we
        /// need it for: a relative sense of how tight the fit is.
        let rSquared: Double
    }

    /// Fits `y = slope * x` through the origin via ordinary least squares.
    /// Returns `nil` if there isn't enough variance in `x` to fit a slope
    /// (e.g. every meal happened to have the same carb count).
    static func fitThroughOrigin(x: [Double], y: [Double]) -> Fit? {
        precondition(x.count == y.count, "x and y must be the same length")
        guard !x.isEmpty else { return nil }

        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = x.reduce(0) { $0 + $1 * $1 }
        guard sumXX > 0 else { return nil }

        let slope = sumXY / sumXX

        let sumYY = y.reduce(0) { $0 + $1 * $1 }
        guard sumYY > 0 else {
            // Every y is zero: the fit is trivially perfect regardless of slope.
            return Fit(slope: slope, rSquared: 1.0)
        }

        let sumSquaredResiduals = zip(x, y).reduce(0.0) { partial, pair in
            let residual = pair.1 - slope * pair.0
            return partial + residual * residual
        }
        let rSquared = 1.0 - (sumSquaredResiduals / sumYY)
        return Fit(slope: slope, rSquared: rSquared)
    }
}
