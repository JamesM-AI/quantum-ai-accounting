import Foundation

/// A minimal least-squares helper, private to this package.
///
/// `RatioLearning` has its own equivalent (`LinearRegression`), but that type
/// isn't public API, so it can't be imported here -- this is a small,
/// intentionally duplicated equivalent kept in lockstep with the same
/// statistical shape: a line forced through the origin (`y = slope * x`),
/// for the same reason `RatioLearning` forces it -- zero steps/zero excess
/// glucose should imply zero of whatever we're regressing against, and a free
/// intercept would let sampling noise in a modest, real-life data set
/// manufacture a phantom constant with no physiological meaning.
enum LinearRegressionThroughOrigin {

    /// Fits `y = slope * x` through the origin via ordinary least squares.
    /// Returns `nil` if there are fewer than 2 points, or if there isn't
    /// enough variance in `x` to fit a slope (e.g. every point has the same
    /// x value).
    static func fit(x: [Double], y: [Double]) -> (slope: Double, rSquared: Double)? {
        precondition(x.count == y.count, "x and y must be the same length")
        guard x.count >= 2 else { return nil }

        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = x.reduce(0) { $0 + $1 * $1 }
        guard sumXX > 0 else { return nil }

        let slope = sumXY / sumXX

        let sumYY = y.reduce(0) { $0 + $1 * $1 }
        guard sumYY > 0 else {
            // Every y is zero: the fit is trivially perfect regardless of slope.
            return (slope: slope, rSquared: 1.0)
        }

        let sumSquaredResiduals = zip(x, y).reduce(0.0) { partial, pair in
            let residual = pair.1 - slope * pair.0
            return partial + residual * residual
        }
        let rSquared = 1.0 - (sumSquaredResiduals / sumYY)
        return (slope: slope, rSquared: rSquared)
    }
}
