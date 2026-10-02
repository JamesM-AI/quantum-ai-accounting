import Foundation
import GlucoseCore

/// A single standalone (non-meal-linked) correction dose, reconstructed
/// after the fact, with the activity and glucose-outcome context needed to
/// learn from it.
///
/// This carries the source `bolusDose` record (rather than copying out only
/// its units) for the same reason `RatioLearning.MealEvent` does: so a
/// learned value can always be traced back to the exact doses that produced
/// it.
public struct CorrectionEvent: Sendable {
    public let bolusDose: InsulinDose
    /// Most recent glucose reading within 15 minutes before the dose.
    public let preGlucoseMgdl: Double
    /// Total steps in the `activityWindowHours` after the dose.
    public let stepsAfterWindow: Int
    /// Whether a logged workout overlapped that same window.
    public let hadWorkoutAfter: Bool
    /// Lowest glucose reading seen during the insulin action window after
    /// the dose (nil if no readings exist in that window).
    public let minGlucoseMgdl: Double?
    /// Glucose reading closest to the end of the insulin action window
    /// (nil if no reading falls near enough to that time).
    public let glucoseAtActionEndMgdl: Double?
    public let outcome: CorrectionOutcome

    public init(
        bolusDose: InsulinDose,
        preGlucoseMgdl: Double,
        stepsAfterWindow: Int,
        hadWorkoutAfter: Bool,
        minGlucoseMgdl: Double?,
        glucoseAtActionEndMgdl: Double?,
        outcome: CorrectionOutcome
    ) {
        self.bolusDose = bolusDose
        self.preGlucoseMgdl = preGlucoseMgdl
        self.stepsAfterWindow = stepsAfterWindow
        self.hadWorkoutAfter = hadWorkoutAfter
        self.minGlucoseMgdl = minGlucoseMgdl
        self.glucoseAtActionEndMgdl = glucoseAtActionEndMgdl
        self.outcome = outcome
    }
}
