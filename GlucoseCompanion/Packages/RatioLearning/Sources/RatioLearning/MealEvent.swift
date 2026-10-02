import Foundation
import GlucoseCore

/// A single "meal + covering bolus" event, reconstructed after the fact from
/// raw `CarbEntry` / `InsulinDose` / `GlucoseReading` logs.
///
/// This is the unit of evidence the estimators regress over. It deliberately
/// carries the *source* records (`carbEntry`, `bolusDose`) rather than copying
/// out only the numbers, so calling code (and, eventually, a "why did you
/// learn this ratio" UI) can always trace a learned value back to the exact
/// meals that produced it.
public struct MealEvent {
    public let carbEntry: CarbEntry
    public let bolusDose: InsulinDose

    /// Most recent glucose reading in the 15 minutes before the event started.
    /// `nil` if no such reading exists (e.g. sensor warm-up gap).
    public let preGlucoseMgdl: Double?

    /// Highest glucose reading observed in the post-meal window.
    public let postGlucosePeakMgdl: Double?

    /// Glucose reading closest to exactly 3 hours after the event started.
    public let postGlucoseAt3hMgdl: Double?

    /// True when this event's data cannot be trusted in isolation -- see
    /// `MealExcursionMatcher` for the exact rules. Confounded events are
    /// still returned (never silently dropped) so the app can show the user
    /// an "excluded from learning" list rather than have data vanish
    /// unexplained.
    public let isConfounded: Bool
    public let confoundedReason: String?

    public init(
        carbEntry: CarbEntry,
        bolusDose: InsulinDose,
        preGlucoseMgdl: Double?,
        postGlucosePeakMgdl: Double?,
        postGlucoseAt3hMgdl: Double?,
        isConfounded: Bool,
        confoundedReason: String?
    ) {
        self.carbEntry = carbEntry
        self.bolusDose = bolusDose
        self.preGlucoseMgdl = preGlucoseMgdl
        self.postGlucosePeakMgdl = postGlucosePeakMgdl
        self.postGlucoseAt3hMgdl = postGlucoseAt3hMgdl
        self.isConfounded = isConfounded
        self.confoundedReason = confoundedReason
    }

    /// The event's anchor time: the earlier of the carb entry and its
    /// matched bolus, since either could have been logged first.
    public var anchorTime: Date {
        min(carbEntry.timestamp, bolusDose.timestamp)
    }
}
