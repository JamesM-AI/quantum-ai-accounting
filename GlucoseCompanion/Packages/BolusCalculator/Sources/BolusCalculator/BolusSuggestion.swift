import Foundation
import GlucoseCore

/// A plain-data snapshot of the `TimeOfDayProfile` that informed a
/// suggestion. Deliberately not the live SwiftData `@Model` object -- this
/// package should not hold onto (or require callers to keep alive) a
/// managed-object reference any longer than the moment of calculation, and
/// the UI/history layer only ever needs these few fields to explain "why".
public struct TimeOfDayProfileSnapshot: Sendable {
    public let blockName: String
    public let carbRatio: Double
    public let correctionFactor: Double
    public let confidence: ConfidenceLevel
    public let dataPointCount: Int

    public init(
        blockName: String,
        carbRatio: Double,
        correctionFactor: Double,
        confidence: ConfidenceLevel,
        dataPointCount: Int
    ) {
        self.blockName = blockName
        self.carbRatio = carbRatio
        self.correctionFactor = correctionFactor
        self.confidence = confidence
        self.dataPointCount = dataPointCount
    }
}

/// Non-fatal conditions attached to an otherwise-valid suggestion. These
/// are surfaced to the user, never swallowed -- e.g. a clamp to max dose
/// must always be visible, not silently applied.
public enum BolusWarning: Sendable {
    /// The raw computed dose exceeded `maxBolusUnits` and was clamped down
    /// to it. Carries the pre-clamp value so the UI can show both numbers.
    case exceedsMaxDose(clampedFrom: Double)
    /// The raw computed dose is unusually large compared to the person's
    /// own recent bolusing history.
    case unusuallyHighVersusHistory(recentAverage: Double)
    /// The time-block profile used has low or insufficient confidence
    /// (not enough learned data, or still on defaults).
    case lowConfidenceProfile(confidence: ConfidenceLevel)
    /// The correction component used a learned, activity-adjusted
    /// correction factor (see `ActivityAdjustedCorrectionFactor`) instead of
    /// the block's normal one -- always flagged, never applied silently.
    /// Carries both values so the UI can show exactly what changed.
    case activityAdjustedCorrectionApplied(
        baselineMgdlPerUnit: Double,
        adjustedMgdlPerUnit: Double,
        confidence: ConfidenceLevel,
        dataPointCount: Int
    )
}

/// A learned correction factor (mg/dL drop per unit) specific to occasions
/// when the person indicates they plan to be physically active after a
/// correction dose, as opposed to the block's normal (non-activity)
/// correction factor. Computed entirely outside this package (see the
/// `CorrectionLearning` package) from historical correction-only doses and
/// their outcomes; passed in here as plain data so this package's own
/// dependency graph stays limited to `GlucoseCore`.
///
/// `BolusCalculator.calculate` only ever uses this to make a correction
/// SMALLER than the block's baseline, never larger -- see the doc comment
/// on `calculate` for why.
public struct ActivityAdjustedCorrectionFactor: Sendable {
    public let mgdlPerUnit: Double
    public let confidence: ConfidenceLevel
    public let dataPointCount: Int

    public init(mgdlPerUnit: Double, confidence: ConfidenceLevel, dataPointCount: Int) {
        self.mgdlPerUnit = mgdlPerUnit
        self.confidence = confidence
        self.dataPointCount = dataPointCount
    }
}

/// A suggested bolus dose, always carrying its full breakdown so the UI
/// can show its work rather than a bare number. This is a suggestion only
/// -- nothing in this package delivers it anywhere.
public struct BolusSuggestion: Sendable {
    public let suggestedUnits: Double
    public let carbComponentUnits: Double
    public let correctionComponentUnits: Double
    public let insulinOnBoardUnits: Double
    public let usedProfile: TimeOfDayProfileSnapshot
    public let warnings: [BolusWarning]

    public init(
        suggestedUnits: Double,
        carbComponentUnits: Double,
        correctionComponentUnits: Double,
        insulinOnBoardUnits: Double,
        usedProfile: TimeOfDayProfileSnapshot,
        warnings: [BolusWarning]
    ) {
        self.suggestedUnits = suggestedUnits
        self.carbComponentUnits = carbComponentUnits
        self.correctionComponentUnits = correctionComponentUnits
        self.insulinOnBoardUnits = insulinOnBoardUnits
        self.usedProfile = usedProfile
        self.warnings = warnings
    }
}

/// Outcome of a bolus calculation attempt.
///
/// Refusals are explicit cases rather than thrown errors deliberately:
/// "not configured", "glucose too low", "stale reading", and "profile not
/// ready" are routine, expected outcomes the UI must branch on and present
/// clearly to the user -- not exceptional failures to be caught and
/// logged. Modeling them as `Error` would invite a call site that
/// `try?`-swallows a safety refusal into `nil` and falls through to some
/// other default; an explicit, exhaustively-switched-over enum case
/// cannot be silently discarded that way.
public enum BolusCalculationResult: Sendable {
    case suggestion(BolusSuggestion)
    /// `UserSettings.isConfigured` is false, or `maxBolusUnits <= 0`.
    case refusedNotConfigured
    /// Current glucose is below the configured safety floor.
    case refusedGlucoseTooLow(currentMgdl: Double)
    /// The glucose reading used is older than the allowed staleness window.
    case refusedStaleGlucose(readingAgeMinutes: Double)
    /// The active time-of-day profile has no usable carb ratio and/or
    /// correction factor yet (no learned value and no user override).
    case refusedProfileNotReady
}
