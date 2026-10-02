import Foundation
import GlucoseCore

/// Computes the fraction of a bolus still "on board" (active, not yet
/// metabolized) as a function of time, and sums that across a set of past
/// doses to produce a total insulin-on-board (IOB) figure in units.
///
/// Only doses with `reason == .bolus` contribute. Basal insulin is
/// intentionally excluded from this bolus-correction IOB figure, per
/// standard bolus-wizard practice (basal is assumed to be handled by a
/// separate ongoing background rate and double-counting it here would
/// under-suggest correction doses) -- though some advanced looping
/// workflows do fold basal deviations into IOB. This package sticks to the
/// simpler, more conservative convention.
public enum InsulinOnBoardModel {

    /// Fraction of `durationMinutes` (DIA) at which the bilinear curve's
    /// inflection point sits. Chosen to roughly mirror where rapid-acting
    /// insulin activity is understood to peak (commonly cited as ~1/3 of
    /// the way through DIA for a typical 3-5 hour action window).
    private static let bilinearPeakFraction: Double = 1.0 / 3.0

    /// Fraction of the original dose still remaining at the bilinear
    /// curve's inflection point. 0.5 means "half the dose has been used by
    /// the time activity peaks" -- a simplification, not a clinical curve.
    private static let bilinearPeakRemainingFraction: Double = 0.5

    /// Fraction of `durationMinutes` used as the exponential model's peak
    /// activity time (tp). Real-world peak time depends on insulin type
    /// (e.g. Fiasp vs. Humalog) and is usually a fixed clinical constant
    /// rather than a fraction of DIA, but this package only has a
    /// user-configured DIA to work with, not an insulin-type selector, so
    /// we approximate peak as a fixed fraction of DIA. 1/3 both keeps the
    /// exponential model's characteristic equation well-behaved for any
    /// DIA (see comment in `exponentialRemainingFraction`) and lands in
    /// the commonly-cited range for rapid-acting analogs.
    private static let exponentialPeakFraction: Double = 1.0 / 3.0

    /// Total insulin (in units) still active from `bolusDoses` at `date`.
    ///
    /// - Parameters:
    ///   - bolusDoses: Doses to consider; non-bolus (basal) doses are
    ///     ignored, as are doses in the future or already fully absorbed.
    ///   - date: The instant to evaluate IOB at (normally "now").
    ///   - durationMinutes: Insulin action duration (DIA), from
    ///     `UserSettings.insulinActionDurationMinutes`.
    ///   - model: Which decay curve to use.
    public static func currentIOB(
        bolusDoses: [InsulinDose],
        at date: Date,
        durationMinutes: Int,
        model: IOBModelType
    ) -> Double {
        guard durationMinutes > 0 else { return 0 }
        let duration = Double(durationMinutes)

        var totalUnitsOnBoard = 0.0
        for dose in bolusDoses {
            guard dose.reason == .bolus else { continue }

            let minutesAgo = date.timeIntervalSince(dose.timestamp) / 60.0
            // Skip doses that are in the future relative to `date`, or that
            // are already fully absorbed (outside the DIA window).
            guard minutesAgo >= 0, minutesAgo < duration else { continue }

            let remainingFraction: Double
            switch model {
            case .bilinear:
                remainingFraction = bilinearRemainingFraction(minutesAgo: minutesAgo, duration: duration)
            case .exponential:
                remainingFraction = exponentialRemainingFraction(minutesAgo: minutesAgo, duration: duration)
            }

            totalUnitsOnBoard += dose.units * remainingFraction
        }

        return max(0, totalUnitsOnBoard)
    }

    /// The simpler/older of the two models: a two-segment ("bilinear")
    /// piecewise-linear approximation of remaining IOB fraction, similar in
    /// spirit to the linear decay curves used by early pump bolus wizards
    /// before exponential models became the norm. This is a deliberately
    /// simple approximation, not a reproduction of any specific
    /// manufacturer's clinical curve.
    private static func bilinearRemainingFraction(minutesAgo: Double, duration: Double) -> Double {
        let peak = duration * bilinearPeakFraction

        if minutesAgo <= peak {
            // Segment 1: remaining fraction falls linearly from 1.0 (at
            // t=0) to `bilinearPeakRemainingFraction` (at t=peak).
            let progress = peak > 0 ? minutesAgo / peak : 1
            return 1 - progress * (1 - bilinearPeakRemainingFraction)
        } else {
            // Segment 2: remaining fraction falls linearly from
            // `bilinearPeakRemainingFraction` (at t=peak) to 0 (at t=duration).
            let tailSpan = duration - peak
            let progress = tailSpan > 0 ? (minutesAgo - peak) / tailSpan : 1
            return bilinearPeakRemainingFraction * (1 - progress)
        }
    }

    /// The two-parameter exponential IOB decay curve widely referenced in
    /// open-source automated-insulin-delivery documentation (e.g. the
    /// formula popularized in Loop/OpenAPS community write-ups), expressed
    /// in terms of DIA (`duration`) and peak activity time (`tp`).
    ///
    /// tau = tp * (1 - tp/duration) / (1 - 2*tp/duration)
    /// a   = 2*tau/duration
    /// S   = 1 / (1 - a + (1+a) * e^(-duration/tau))
    /// IOB(t) = 1 - S*(1-a) * ((t^2 / (tau*duration*(1-a)) - t/tau - 1) * e^(-t/tau) + 1)
    ///
    /// Fixing `tp = duration/3` keeps `(1 - 2*tp/duration)` at a constant
    /// 1/3 regardless of `duration`, which avoids the divide-by-zero
    /// singularity this formula has when tp == duration/2.
    ///
    /// TODO: verify against a canonical reference implementation before
    /// relying on this for real dosing. This formula is transcribed from
    /// memory of community documentation, not derived from a primary
    /// pharmacokinetic source, and an error here directly affects a
    /// dosing suggestion.
    private static func exponentialRemainingFraction(minutesAgo: Double, duration: Double) -> Double {
        let t = minutesAgo
        let td = duration
        let tp = duration * exponentialPeakFraction

        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))

        let iob = 1 - s * (1 - a) * ((pow(t, 2) / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)

        // Clamp for numerical safety; the closed-form curve should already
        // stay within [0, 1] over the [0, duration) domain we call it with.
        return max(0, min(1, iob))
    }
}
