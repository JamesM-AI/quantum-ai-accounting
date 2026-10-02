// BolusCalculator
//
// ARCHITECTURAL INVARIANT -- READ BEFORE ADDING ANY DEPENDENCY OR CODE HERE:
//
// This package computes a SUGGESTED insulin dose for a person with diabetes
// to review and, if they agree, log themselves. It is strictly personal
// decision-support.
//
//   * This package MUST contain ZERO networking, Bluetooth, or any code
//     path capable of reaching an insulin pump or otherwise delivering
//     insulin. No URLSession, no CoreBluetooth, no pump SDKs, no "auto
//     apply" hooks -- ever. This is an architectural invariant, not a
//     style preference, and it must hold no matter how convenient a future
//     integration might seem.
//   * The app (outside this package) never auto-delivers insulin. Every
//     `BolusSuggestion` this package produces is inert data: a number plus
//     its breakdown, for a human to look at and decide on.
//   * When required inputs are missing, stale, or unsafe, this package
//     refuses to guess -- see `BolusCalculationResult`'s refusal cases.
//
import Foundation
import GlucoseCore

public enum BolusCalculator {

    /// Computes a bolus suggestion, or an explicit refusal, from current
    /// glucose, carbs being eaten, the active time-of-day profile, and
    /// insulin-on-board.
    ///
    /// - Parameters:
    ///   - carbsGrams: Grams of carbohydrate to be covered.
    ///   - currentGlucoseMgdl: Most recent glucose reading, in mg/dL.
    ///   - glucoseReadingTimestamp: When that reading was taken.
    ///   - now: The instant the calculation is being made (normally
    ///     `Date()`, passed explicitly for testability).
    ///   - settings: User's configured targets, max dose, and IOB model.
    ///   - profile: The time-of-day profile active for this calculation
    ///     (caller selects it via `TimeOfDayProfile.contains(hour:)`).
    ///   - recentBolusDoses: Recent bolus history used only to judge
    ///     whether the new suggestion looks unusually large.
    ///   - allBolusDosesForIOB: Bolus doses within the IOB lookback window,
    ///     used to compute currently-active insulin.
    ///   - activityAdjustedCorrectionFactor: An optional learned correction
    ///     factor specific to "I plan to be active after this" (see
    ///     `ActivityAdjustedCorrectionFactor`'s doc comment). Deliberately
    ///     one-directional: it is only ever used when it implies a HIGHER
    ///     mg/dL-per-unit sensitivity than the block's baseline (i.e. a
    ///     smaller correction dose) and its confidence is not
    ///     `.insufficientData` -- the entire point is avoiding a low when
    ///     activity is planned, not second-guessing the baseline upward
    ///     from what could be statistical noise in the other direction.
    ///     When it would imply a *lower* sensitivity (larger dose), or has
    ///     insufficient data, it is silently ignored and the block's normal
    ///     correction factor is used exactly as if this parameter were nil.
    ///     Its effect is also capped (see `maxActivityAdjustmentMultiple`)
    ///     so a single outlier fit can't swing the dose too far, and its use
    ///     is always surfaced via `.activityAdjustedCorrectionApplied`,
    ///     never applied silently.
    public static func calculate(
        carbsGrams: Double,
        currentGlucoseMgdl: Double,
        glucoseReadingTimestamp: Date,
        now: Date,
        settings: UserSettings,
        profile: TimeOfDayProfile,
        recentBolusDoses: [InsulinDose],
        allBolusDosesForIOB: [InsulinDose],
        activityAdjustedCorrectionFactor: ActivityAdjustedCorrectionFactor? = nil
    ) -> BolusCalculationResult {

        // Caps how much smaller the activity-adjusted correction factor can
        // make the dose relative to the block's baseline (2x the mg/dL-per-
        // unit value means, at most, half the baseline correction units).
        let maxActivityAdjustmentMultiple = 2.0

        // Gate 1: hasn't finished setup, or has a max dose of 0/negative
        // (0 is not a usable ceiling -- treat it the same as unconfigured).
        guard settings.isConfigured, settings.maxBolusUnits > 0 else {
            return .refusedNotConfigured
        }

        // Gate 2: glucose reading is too old to act on.
        if SafetyGuardrails.staleness(readingTimestamp: glucoseReadingTimestamp, now: now) {
            let ageMinutes = now.timeIntervalSince(glucoseReadingTimestamp) / 60.0
            return .refusedStaleGlucose(readingAgeMinutes: ageMinutes)
        }

        // Gate 3: current glucose is below the hard safety floor.
        if SafetyGuardrails.isGlucoseTooLowToSuggest(currentMgdl: currentGlucoseMgdl, settings: settings) {
            return .refusedGlucoseTooLow(currentMgdl: currentGlucoseMgdl)
        }

        // Gate 4: this time block has no usable carb ratio / correction
        // factor yet (no learned value, no user override).
        guard
            let carbRatio = profile.effectiveCarbRatio, carbRatio > 0,
            let correctionFactor = profile.effectiveCorrectionFactor, correctionFactor > 0
        else {
            return .refusedProfileNotReady
        }

        // Only ever move the correction factor UP from baseline (higher
        // mg/dL-per-unit = each unit does more work = a smaller correction),
        // and only when there's actually enough data behind it -- see the
        // parameter doc comment on `calculate` for the full reasoning.
        var effectiveCorrectionFactor = correctionFactor
        var appliedActivityAdjustment: ActivityAdjustedCorrectionFactor?
        if let activityAdjustedCorrectionFactor,
           activityAdjustedCorrectionFactor.confidence != .insufficientData,
           activityAdjustedCorrectionFactor.mgdlPerUnit > correctionFactor {
            effectiveCorrectionFactor = min(
                activityAdjustedCorrectionFactor.mgdlPerUnit,
                correctionFactor * maxActivityAdjustmentMultiple
            )
            appliedActivityAdjustment = activityAdjustedCorrectionFactor
        }

        let carbComponent = carbsGrams / carbRatio
        let correctionComponent = max(0, currentGlucoseMgdl - settings.targetMidpointMgdl) / effectiveCorrectionFactor
        let insulinOnBoard = InsulinOnBoardModel.currentIOB(
            bolusDoses: allBolusDosesForIOB,
            at: now,
            durationMinutes: settings.insulinActionDurationMinutes,
            model: settings.iobModel
        )
        let rawUnits = max(0, carbComponent + correctionComponent - insulinOnBoard)

        var warnings: [BolusWarning] = []

        if let appliedActivityAdjustment {
            warnings.append(.activityAdjustedCorrectionApplied(
                baselineMgdlPerUnit: correctionFactor,
                adjustedMgdlPerUnit: effectiveCorrectionFactor,
                confidence: appliedActivityAdjustment.confidence,
                dataPointCount: appliedActivityAdjustment.dataPointCount
            ))
        }

        let (clampedUnits, wasClamped) = SafetyGuardrails.clamp(rawUnits, maxBolusUnits: settings.maxBolusUnits)
        if wasClamped {
            warnings.append(.exceedsMaxDose(clampedFrom: rawUnits))
        }

        if SafetyGuardrails.isUnusuallyHigh(rawUnits: rawUnits, recentBolusHistory: recentBolusDoses),
           let recentAverage = SafetyGuardrails.recentBolusAverage(recentBolusDoses) {
            warnings.append(.unusuallyHighVersusHistory(recentAverage: recentAverage))
        }

        if profile.confidence == .low || profile.confidence == .insufficientData {
            warnings.append(.lowConfidenceProfile(confidence: profile.confidence))
        }

        let usedProfile = TimeOfDayProfileSnapshot(
            blockName: profile.blockName,
            carbRatio: carbRatio,
            correctionFactor: correctionFactor,
            confidence: profile.confidence,
            dataPointCount: profile.dataPointCount
        )

        let suggestion = BolusSuggestion(
            suggestedUnits: clampedUnits,
            carbComponentUnits: carbComponent,
            correctionComponentUnits: correctionComponent,
            insulinOnBoardUnits: insulinOnBoard,
            usedProfile: usedProfile,
            warnings: warnings
        )

        return .suggestion(suggestion)
    }
}
