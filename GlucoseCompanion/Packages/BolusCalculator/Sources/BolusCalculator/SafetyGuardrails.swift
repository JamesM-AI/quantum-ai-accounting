import Foundation
import GlucoseCore

/// Pure, side-effect-free validation functions used by `BolusCalculator`.
///
/// These are kept in their own file, deliberately free of any orchestration
/// logic, so each safety rule can be read and audited in isolation from the
/// arithmetic that builds a suggestion.
public enum SafetyGuardrails {

    /// Whether a glucose reading is too old to trust for dosing purposes.
    /// Returns `true` (stale -> refuse) once `readingTimestamp` is more
    /// than `maxAgeMinutes` before `now`.
    public static func staleness(
        readingTimestamp: Date,
        now: Date,
        maxAgeMinutes: Double = 20
    ) -> Bool {
        let ageMinutes = now.timeIntervalSince(readingTimestamp) / 60.0
        return ageMinutes > maxAgeMinutes
    }

    /// Whether current glucose is low enough that the calculator must
    /// refuse to suggest a dose outright, rather than suggest a reduced
    /// one. Uses `lowGlucoseSafetyFloorMgdl`, which per its doc comment in
    /// GlucoseCore is an absolute floor independent of target range --
    /// i.e. this is a hard safety limit, not "below target".
    public static func isGlucoseTooLowToSuggest(
        currentMgdl: Double,
        settings: UserSettings
    ) -> Bool {
        currentMgdl < settings.lowGlucoseSafetyFloorMgdl
    }

    /// Caps a raw computed dose at the user's configured maximum,
    /// reporting whether clamping actually occurred so the caller can
    /// surface it as a warning rather than silently truncating.
    public static func clamp(
        _ rawUnits: Double,
        maxBolusUnits: Double
    ) -> (clamped: Double, wasClamped: Bool) {
        guard rawUnits > maxBolusUnits else {
            return (rawUnits, false)
        }
        return (maxBolusUnits, true)
    }

    /// Rolling average of recent bolus doses (most recent `sampleSize`
    /// bolus-reason doses, by timestamp), in units. Returns `nil` when
    /// there are fewer than 5 historical bolus doses -- not enough history
    /// to judge "unusual" against.
    public static func recentBolusAverage(
        _ recentBolusHistory: [InsulinDose],
        sampleSize: Int = 20
    ) -> Double? {
        let boluses = recentBolusHistory.filter { $0.reason == .bolus }
        guard boluses.count >= 5 else { return nil }

        let sample = boluses
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(sampleSize)
        let total = sample.reduce(0) { $0 + $1.units }
        return total / Double(sample.count)
    }

    /// Whether `rawUnits` is unusually high compared to the person's own
    /// recent bolusing history (more than `thresholdMultiplier` times the
    /// rolling average). Returns `false` when there isn't enough history
    /// to judge (see `recentBolusAverage`) -- an empty/short history is
    /// not itself grounds for a warning.
    public static func isUnusuallyHigh(
        rawUnits: Double,
        recentBolusHistory: [InsulinDose],
        thresholdMultiplier: Double = 3.0
    ) -> Bool {
        guard let average = recentBolusAverage(recentBolusHistory), average > 0 else {
            return false
        }
        return rawUnits > average * thresholdMultiplier
    }
}
